import Foundation
import WhisperKit

/// Local Whisper via WhisperKit (Core ML, Apple Neural Engine).
actor WhisperKitTranscriber: Transcriber, ModelBackend {
    nonisolated let displayName = "Speech recognition (Whisper)"

    private let variant: String
    private let downloadBase: URL
    private var pipe: WhisperKit?

    init(variant: String, downloadBase: URL = ModelPaths.root.appending(path: "whisper")) {
        self.variant = variant
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

    func load() async throws {
        guard pipe == nil else { return }
        guard isDownloaded(), let folder = savedFolder else { throw ModelError.notDownloaded }
        let config = WhisperKitConfig(
            model: variant,
            modelFolder: folder.path,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false)
        pipe = try await WhisperKit(config)
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
        let options = DecodingOptions(
            task: .transcribe,
            language: nil,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: true,
            skipSpecialTokens: true,
            withoutTimestamps: true)
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }
}
