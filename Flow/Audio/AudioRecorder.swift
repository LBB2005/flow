import AVFoundation

enum RecorderError: Error { case noInputDevice, unsupportedFormat }

@MainActor
final class AudioRecorder: Recorder {
    nonisolated static let sampleRate = 16_000.0
    static let maxDuration: TimeInterval = 300

    var onMaxDurationReached: (@MainActor () -> Void)?
    var onSamples: (@MainActor ([Float]) -> Void)?
    /// Normalized level (0…1) of each incoming chunk, for the waveform.
    var onLevel: (@MainActor (Float) -> Void)?
    /// CoreAudio device UID; nil = system default.
    var preferredDeviceUID: String?

    private var engine = AVAudioEngine()
    private var configurationObserver: NSObjectProtocol?
    private var accumulator = SampleAccumulator(maxSamples: Int(sampleRate * maxDuration))
    private var isRecording = false

    func start() throws {
        guard !isRecording else { return }
        // A fresh engine per recording: a reused one caches the input format, and Bluetooth
        // headsets change sample rate when their mic opens (AirPods: 48 kHz -> 24 kHz).
        // Installing a tap with the stale format raises an ObjC exception Swift can't catch.
        engine = AVAudioEngine()
        accumulator = SampleAccumulator(maxSamples: Int(Self.sampleRate * Self.maxDuration))
        let format = try startEngine()
        isRecording = true
        observeConfigurationChanges()
        Log.audio.notice("recording started (\(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch, device \(self.preferredDeviceUID ?? "system default", privacy: .public))")
    }

    func stop() -> [Float] {
        teardown()
        Log.audio.notice("recording stopped: \(self.accumulator.samples.count, privacy: .public) samples, level \(AudioLevel.normalized(self.accumulator.samples), privacy: .public)")
        return accumulator.samples
    }

    func cancel() {
        teardown()
        accumulator = SampleAccumulator(maxSamples: Int(Self.sampleRate * Self.maxDuration))
    }

    /// Selects the device, installs the tap with the current hardware format and starts the engine.
    private func startEngine() throws -> AVAudioFormat {
        let overrideUID = AudioDevices.overrideUID(
            preferred: preferredDeviceUID, systemDefault: AudioDevices.defaultInputUID())
        if let overrideUID { AudioDevices.setInputDevice(uid: overrideUID, on: engine) }
        let input = engine.inputNode
        var format = input.outputFormat(forBus: 0)
        let hardware = input.inputFormat(forBus: 0)
        if hardware.sampleRate != format.sampleRate {
            // Switching device keeps the output format of the route the engine opened first,
            // so tap with what the hardware actually delivers.
            Log.audio.notice("tap format \(format.sampleRate, privacy: .public) Hz is stale; using hardware \(hardware.sampleRate, privacy: .public) Hz")
            format = hardware
        }
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInputDevice }
        guard let converter = TapConverter(inputFormat: format, sampleRate: Self.sampleRate) else {
            throw RecorderError.unsupportedFormat
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format,
                         block: Self.makeTapBlock(converter: converter) { [weak self] samples in
                             Task { @MainActor in self?.append(samples) }
                         })
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        return format
    }

    /// The engine stops itself when the route changes mid-recording (e.g. AirPods switching
    /// to their headset profile once the mic opens), so reinstall the tap and keep going.
    private func observeConfigurationChanges() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterConfigurationChange() }
        }
    }

    private func restartAfterConfigurationChange() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            let format = try startEngine()
            Log.audio.notice("audio configuration changed; input restarted (\(format.sampleRate, privacy: .public) Hz)")
        } catch {
            Log.audio.error("audio configuration changed; input restart failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func teardown() {
        guard isRecording else { return }
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
    }

    private func append(_ samples: [Float]) {
        guard isRecording else { return }
        onLevel?(AudioLevel.normalized(samples))
        guard !accumulator.isFull else { return }
        // Exactly what the accumulator keeps, so listeners see the same audio `stop()` returns.
        let kept = samples.count <= accumulator.maxSamples - accumulator.samples.count
            ? samples : Array(samples.prefix(accumulator.maxSamples - accumulator.samples.count))
        onSamples?(kept)
        if accumulator.append(kept) { onMaxDurationReached?() }
    }

    /// Built in a nonisolated context so the block isn't inferred as @MainActor.
    /// It runs on the realtime audio thread.
    private nonisolated static func makeTapBlock(
        converter: TapConverter,
        sink: @escaping @Sendable ([Float]) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in sink(converter.convert(buffer)) }
    }
}
