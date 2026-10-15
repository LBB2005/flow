import AVFoundation

enum RecorderError: Error { case noInputDevice, unsupportedFormat }

@MainActor
final class AudioRecorder: Recorder {
    nonisolated static let sampleRate = 16_000.0
    static let maxDuration: TimeInterval = 300

    var onMaxDurationReached: (@MainActor () -> Void)?
    /// Normalized level (0…1) of each incoming chunk, for the waveform.
    var onLevel: (@MainActor (Float) -> Void)?
    /// CoreAudio device UID; nil = system default.
    var preferredDeviceUID: String?

    private let engine = AVAudioEngine()
    private var accumulator = SampleAccumulator(maxSamples: Int(sampleRate * maxDuration))
    private var isRecording = false

    func start() throws {
        guard !isRecording else { return }
        if let uid = preferredDeviceUID { AudioDevices.setInputDevice(uid: uid, on: engine) }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInputDevice }
        guard let converter = TapConverter(inputFormat: format, sampleRate: Self.sampleRate) else {
            throw RecorderError.unsupportedFormat
        }

        accumulator = SampleAccumulator(maxSamples: Int(Self.sampleRate * Self.maxDuration))
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
        isRecording = true
        Log.audio.debug("recording started (\(format.sampleRate) Hz, \(format.channelCount) ch)")
    }

    func stop() -> [Float] {
        teardown()
        Log.audio.debug("recording stopped: \(self.accumulator.samples.count) samples")
        return accumulator.samples
    }

    func cancel() {
        teardown()
        accumulator = SampleAccumulator(maxSamples: Int(Self.sampleRate * Self.maxDuration))
    }

    private func teardown() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
    }

    private func append(_ samples: [Float]) {
        guard isRecording else { return }
        onLevel?(AudioLevel.normalized(samples))
        if accumulator.append(samples) { onMaxDurationReached?() }
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
