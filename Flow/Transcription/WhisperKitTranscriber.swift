import Foundation
import WhisperKit

/// Local Whisper via WhisperKit (Core ML, Apple Neural Engine).
actor WhisperKitTranscriber: Transcriber, ModelBackend {
    nonisolated let displayName = "Speech recognition (Whisper)"

    private let variant: String
    private let downloadBase: URL
    private let language: String?
    private var pipe: WhisperKit?
    private var loading: Task<Void, Error>?

    /// `language` is a Whisper language code. "en" (the default) skips language detection,
    /// which is faster and avoids mis-detected accents; nil auto-detects.
    init(variant: String, language: String? = "en", downloadBase: URL = ModelPaths.root.appending(path: "whisper")) {
        self.variant = variant
        self.language = language
        self.downloadBase = downloadBase
    }

    /// WhisperKit returns the folder it downloaded into; we remember it so later launches work offline.
    private var folderKey: String { "whisperFolder.\(variant)" }
    private var savedFolder: URL? {
        UserDefaults.standard.string(forKey: folderKey).map { URL(filePath: $0) }
    }

    func isDownloaded() -> Bool {
        guard let folder = savedFolder else { return false }
        return FileManager.default.fileExists(atPath: folder.appending(path: "AudioEncoder.mlmodelc").path)
    }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let folder = try await WhisperKit.download(
            variant: variant,
            downloadBase: downloadBase,
            progressCallback: { progress($0.fractionCompleted) })
        UserDefaults.standard.set(folder.path, forKey: folderKey)
        Log.models.info("whisper downloaded to \(folder.path)")
    }

    /// Loads once. Concurrent callers (warm-up, prepare, transcribe) share the in-flight load.
    func load() async throws {
        guard pipe == nil else { return }
        if let loading { return try await loading.value }
        guard isDownloaded(), let folder = savedFolder else { throw ModelError.notDownloaded }
        let task = Task { try await self.loadPipe(from: folder) }
        loading = task
        defer { loading = nil }
        try await task.value
    }

    private func loadPipe(from folder: URL) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let config = WhisperKitConfig(
            model: variant,
            modelFolder: folder.path,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false)
        pipe = try await WhisperKit(config)
        Log.models.notice("\(self.displayName, privacy: .public) loaded in \((clock.now - started) / .milliseconds(1), format: .fixed(precision: 0), privacy: .public) ms")
    }

    /// Waits for a transcription in progress, so its models aren't pulled out from under it.
    func unload() async {
        _ = try? await serially { await self.unloadNow() }
    }

    private func unloadNow() async {
        nonisolated(unsafe) let current = pipe
        pipe = nil
        lastRun = nil
        await current?.unloadModels()
    }

    /// When Whisper last ran; nil until it has run since loading.
    private var lastRun: ContinuousClock.Instant?
    /// After this long unused, the first transcription is slower (+150 ms after 5 min on an M4 Pro): the Neural
    /// Engine has gone cold. Measured with `LatencyBenchmarkTests`.
    static let coldAfter: Duration = .seconds(60)

    /// Loads if needed, and if Whisper hasn't run for a while, transcribes a moment of silence so the user's audio
    /// doesn't pay for the cold start. Runs in the queue ahead of the dictation it's warming up for.
    func warm() async throws {
        try await load()
        if let lastRun, ContinuousClock.now - lastRun < Self.coldAfter { return }
        let clock = ContinuousClock()
        let started = clock.now
        _ = try await transcribe([Float](repeating: 0, count: Self.minimumSamples))
        Log.models.notice("\(self.displayName, privacy: .public) warmed in \((clock.now - started) / .milliseconds(1), format: .fixed(precision: 0), privacy: .public) ms")
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await transcribe(samples, context: nil)
    }

    /// `context` is the transcript of the audio just before `samples` (incremental transcription); Whisper sees it
    /// as the previous text, which keeps casing and sentence flow across the cut.
    func transcribe(_ samples: [Float], context: String?) async throws -> String {
        try await serially { try await self.run(samples, context: context) }
    }

    private func run(_ samples: [Float], context: String?) async throws -> String {
        try await load()
        guard let pipe else { throw ModelError.notDownloaded }
        nonisolated(unsafe) let whisper = pipe
        var options = Self.decodingOptions(language: language)
        if let context, let tokenizer = whisper.tokenizer {
            options.promptTokens = Self.promptTokens(for: context, tokenizer: tokenizer)
        }
        let results = try await whisper.transcribe(audioArray: Self.padded(samples), decodeOptions: options)
        lastRun = .now
        return results.map(\.text).joined(separator: " ")
    }

    /// WhisperKit isn't safe to run twice at once, and the Neural Engine would only interleave the two anyway, so
    /// calls (background chunks, the final tail, warm-ups) run one after another in the order they arrive.
    private var queue: Task<Void, Never>?

    private func serially<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = queue
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await work()
        }
        queue = Task { _ = try? await task.value }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    /// WhisperKit never starts decoding in the last second of a clip (`windowClipTime`), so a clip of 1 s or less
    /// (a quick "yes") came back empty. Padding with silence is lossless: every window is zero-padded to 30 s anyway.
    static let minimumSamples = 2 * 16_000

    static func padded(_ samples: [Float]) -> [Float] {
        guard samples.count < minimumSamples else { return samples }
        return samples + [Float](repeating: 0, count: minimumSamples - samples.count)
    }

    /// The end of `context` as Whisper prompt tokens. Kept short: each one costs a decoder step (~8 ms).
    static let maxPromptTokens = 48

    private static func promptTokens(for context: String, tokenizer: any WhisperTokenizer) -> [Int]? {
        let text = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let tokens = tokenizer.encode(text: " " + text).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : Array(tokens.suffix(maxPromptTokens))
    }

    /// Greedy decoding with the language token prefilled. Detection runs only when no language is set.
    /// Clips longer than one 30 s window are split at the longest pause (VAD) instead of at exactly 30 s, which
    /// cut through a word and lost the rest of the sentence before it.
    static func decodingOptions(language: String?) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad)
    }
}
