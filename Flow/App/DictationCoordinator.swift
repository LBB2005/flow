import Foundation

/// Runs one dictation at a time: record → transcribe → clean → paste (spec §4–6).
@MainActor
final class DictationCoordinator {
    enum Phase: Equatable { case idle, recording, transcribing, cleaning, inserting }

    private(set) var phase: Phase = .idle
    /// The in-flight pipeline, exposed so tests can await it.
    private(set) var processing: Task<Void, Never>?

    var transcriber: Transcriber
    var cleaner: Cleaner
    /// Called after every dictation that reached processing (resets the keep-warm timer).
    var onDictationProcessed: (@MainActor () -> Void)?

    private let recorder: Recorder
    private let inserter: TextInserter
    private let pill: PillPresenter
    private let isCleanupEnabled: @MainActor () -> Bool
    private let blockedReason: @MainActor () -> String?
    private let cleanupTimeout: Duration

    init(
        recorder: Recorder,
        transcriber: Transcriber,
        cleaner: Cleaner,
        inserter: TextInserter,
        pill: PillPresenter,
        isCleanupEnabled: @escaping @MainActor () -> Bool,
        blockedReason: @escaping @MainActor () -> String? = { nil },
        cleanupTimeout: Duration = .seconds(5)
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.inserter = inserter
        self.pill = pill
        self.isCleanupEnabled = isCleanupEnabled
        self.blockedReason = blockedReason
        self.cleanupTimeout = cleanupTimeout
        recorder.onMaxDurationReached = { [weak self] in
            Log.audio.notice("max recording length reached")
            self?.handle(.finish)
        }
    }

    func handle(_ action: HotkeyAction) {
        switch action {
        case .begin:
            guard phase == .idle else {
                Log.pipeline.debug("busy (\(String(describing: self.phase))), ignoring hotkey")
                return
            }
            if let reason = blockedReason() {
                pill.show(.error(reason))
                return
            }
            do {
                try recorder.start()
                phase = .recording
            } catch {
                Log.audio.error("recorder failed to start: \(error.localizedDescription)")
                pill.show(.error("Microphone unavailable"))
            }

        case .confirm:
            guard phase == .recording else { return }
            pill.show(.listening)

        case .discard:
            guard phase == .recording else { return }
            recorder.cancel()
            phase = .idle
            pill.hide()

        case .cancel(let reason):
            guard phase == .recording else { return }
            recorder.cancel()
            phase = .idle
            if reason == .escape { pill.show(.cancelled) } else { pill.hide() }

        case .finish:
            guard phase == .recording else { return }
            let samples = recorder.stop()
            phase = .transcribing
            pill.show(.thinking)
            processing = Task { await self.process(samples) }
        }
    }

    private func process(_ samples: [Float]) async {
        defer {
            phase = .idle
            onDictationProcessed?()
        }
        guard !SilenceDetector.isSilent(samples) else {
            pill.show(.noSpeech)
            return
        }

        let raw: String
        do {
            raw = TranscriptNormalizer.normalize(try await transcriber.transcribe(samples))
        } catch {
            Log.pipeline.error("transcription failed: \(error.localizedDescription)")
            pill.show(.error("Transcription failed"))
            return
        }
        guard !raw.isEmpty else {
            pill.show(.noSpeech)
            return
        }

        var text = raw
        if isCleanupEnabled() {
            phase = .cleaning
            text = await cleaned(raw) ?? raw
        }

        phase = .inserting
        let result = await inserter.insert(text)
        pill.show(result == .pasted ? .success : .copied)
    }

    /// Returns the validated cleanup, or nil to fall back to the raw transcript.
    private func cleaned(_ raw: String) async -> String? {
        let cleaner = self.cleaner
        do {
            let output = try await withTimeout(cleanupTimeout) { try await cleaner.clean(raw) }
            switch CleanupValidator.validate(input: raw, output: output) {
            case .accept(let text):
                return text
            case .reject(let reason):
                Log.pipeline.notice("cleanup rejected: \(String(describing: reason))")
                return nil
            }
        } catch {
            Log.pipeline.notice("cleanup failed: \(String(describing: error))")
            return nil
        }
    }
}
