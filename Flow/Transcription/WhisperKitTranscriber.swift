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

    func unload() async {
        nonisolated(unsafe) let current = pipe
        pipe = nil
        await current?.unloadModels()
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await load()
        guard let pipe else { throw ModelError.notDownloaded }
        nonisolated(unsafe) let whisper = pipe
        let options = Self.decodingOptions(language: language)
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }

    /// Greedy decoding with the language token prefilled. Detection runs only when no language is set.
    static func decodingOptions(language: String?) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true)
    }
}
