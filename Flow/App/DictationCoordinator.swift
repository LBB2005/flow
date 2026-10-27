import Foundation

/// Runs one dictation at a time: record → transcribe → clean → paste (spec §4–6).
@MainActor
final class DictationCoordinator {
    enum Phase: Equatable { case idle, recording, transcribing, cleaning, inserting }

    /// Transcripts with fewer words than this skip the cleanup model and use `QuickCleaner` (spec §11 amendment 6).
    static let quickCleanupWordLimit = 8

    private(set) var phase: Phase = .idle
    /// The in-flight pipeline, exposed so tests can await it.
    private(set) var processing: Task<Void, Never>?

    var transcriber: Transcriber
    var cleaner: Cleaner
    /// Called when recording stops by itself (max length), so the hotkey can un-latch.
    var onAutoStop: (@MainActor () -> Void)?
    /// Called once the recorder has started, so models can load while the user speaks.
    var onRecordingStarted: (@MainActor () -> Void)?
    /// Called after every dictation that reached processing (resets the keep-warm timer).
    var onDictationProcessed: (@MainActor () -> Void)?

    private let recorder: Recorder
    private let inserter: TextInserter
    private let pill: PillPresenter
    private let media: MediaPauser
    private let isCleanupEnabled: @MainActor () -> Bool
    private let isIncrementalEnabled: @MainActor () -> Bool
    private let chunkConfig: ChunkPlanner.Config
    /// Transcribes while the user speaks (spec §11 amendment 10). Nil when off or not recording.
    private var incremental: IncrementalTranscription?
    private let blockedReason: @MainActor () -> String?
    private let cleanupTimeout: Duration

    init(
        recorder: Recorder,
        transcriber: Transcriber,
        cleaner: Cleaner,
        inserter: TextInserter,
        pill: PillPresenter,
        media: MediaPauser = NoMediaPauser(),
        isCleanupEnabled: @escaping @MainActor () -> Bool,
        isIncrementalEnabled: @escaping @MainActor () -> Bool = { false },
        chunkConfig: ChunkPlanner.Config = ChunkPlanner.Config(),
        blockedReason: @escaping @MainActor () -> String? = { nil },
        cleanupTimeout: Duration = .seconds(5)
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.inserter = inserter
        self.pill = pill
        self.media = media
        self.isCleanupEnabled = isCleanupEnabled
        self.isIncrementalEnabled = isIncrementalEnabled
        self.chunkConfig = chunkConfig
        self.blockedReason = blockedReason
        self.cleanupTimeout = cleanupTimeout
        recorder.onMaxDurationReached = { [weak self] in
            Log.audio.notice("max recording length reached")
            self?.handle(.finish)
            self?.onAutoStop?()
        }
        recorder.onSamples = { [weak self] samples in self?.incremental?.append(samples) }
    }

    func handle(_ action: HotkeyAction) {
        switch action {
        case .begin:
            guard phase == .idle else {
                Log.pipeline.notice("busy (\(String(describing: self.phase), privacy: .public)), ignoring hotkey")
                return
            }
            if let reason = blockedReason() {
                Log.pipeline.notice("blocked: \(reason, privacy: .public)")
                pill.show(.error(reason))
                return
            }
            media.pause()
            do {
                try recorder.start()
                phase = .recording
                // Created before any samples arrive: they're delivered on a later main-actor turn.
                incremental = isIncrementalEnabled()
                    ? IncrementalTranscription(transcriber: transcriber, config: chunkConfig) : nil
                onRecordingStarted?()
            } catch {
                Log.audio.error("recorder failed to start: \(error.localizedDescription)")
                pill.show(.error("Microphone unavailable"))
                media.resume()
            }

        case .confirm:
            guard phase == .recording else { return }
            pill.show(.listening)

        case .cancel(let reason):
            guard phase == .recording else { return }
            recorder.cancel()
            incremental?.cancel()
            incremental = nil
            phase = .idle
            media.resume()
            Log.pipeline.notice("cancelled (\(String(describing: reason), privacy: .public))")
            if reason == .escape { pill.show(.cancelled) } else { pill.hide() }

        case .finish:
            guard phase == .recording else { return }
            let samples = recorder.stop()
            let session = incremental
            incremental = nil
            phase = .transcribing
            pill.show(.thinking)
            processing = Task { await self.process(samples, incremental: session) }
        }
    }

    private func process(_ samples: [Float], incremental: IncrementalTranscription?) async {
        defer {
            phase = .idle
            media.resume()
            onDictationProcessed?()
        }
        guard !SilenceDetector.isSilent(samples) else {
            incremental?.cancel()
            Log.pipeline.notice("no speech: audio below silence threshold")
            pill.show(.noSpeech)
            return
        }

        let clock = ContinuousClock()
        let started = clock.now
        let raw: String
        do {
            raw = TranscriptNormalizer.normalize(try await transcribe(samples, incremental: incremental))
        } catch {
            Log.pipeline.error("transcription failed: \(error.localizedDescription)")
            pill.show(.error("Transcription failed"))
            return
        }
        guard !raw.isEmpty else {
            Log.pipeline.notice("no speech: empty transcript after normalizing")
            pill.show(.noSpeech)
            return
        }

        let transcribed = clock.now
        var text = raw
        var cleanup = "off"
        if isCleanupEnabled() {
            phase = .cleaning
            if raw.split(whereSeparator: \.isWhitespace).count < Self.quickCleanupWordLimit {
                cleanup = "quick"
                text = QuickCleaner.clean(raw)
                guard !text.isEmpty else {
                    Log.pipeline.notice("no speech: only fillers")
                    pill.show(.noSpeech)
                    return
                }
            } else {
                cleanup = "model"
                text = await cleaned(raw) ?? raw
            }
        }
        let cleanedAt = clock.now

        phase = .inserting
        await inserter.insert(text)
        let pastedAt = clock.now
        pill.show(.success)
        Log.pipeline.notice("""
            timing: audio \(samples.count / 16, privacy: .public) ms \
            (\(incremental?.chunkCount ?? 0, privacy: .public) pieces done while speaking), \
            transcribe \(Self.ms(transcribed - started), privacy: .public) ms, \
            cleanup (\(cleanup, privacy: .public)) \(Self.ms(cleanedAt - transcribed), privacy: .public) ms, \
            paste \(Self.ms(pastedAt - cleanedAt), privacy: .public) ms, \
            total \(Self.ms(pastedAt - started), privacy: .public) ms
            """)
    }

    /// The incremental transcript when there is one, else Whisper on the whole clip minus leading and trailing silence.
    private func transcribe(_ samples: [Float], incremental: IncrementalTranscription?) async throws -> String {
        if let incremental {
            do {
                return try await incremental.finish(samples)
            } catch {
                Log.pipeline.error("incremental transcription failed, transcribing the whole clip: \(String(describing: error), privacy: .public)")
            }
        }
        return try await transcriber.transcribe(SilenceDetector.trimmed(samples))
    }

    private static func ms(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
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
