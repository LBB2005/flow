import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Local cleanup with a small Qwen3 model on the GPU via MLX.
actor MLXCleaner: Cleaner, ModelBackend {
    nonisolated let displayName = "Cleanup model (Qwen3)"

    private let repoID: String
    private var container: ModelContainer?

    init(repoID: String) {
        self.repoID = repoID
    }

    private var folderKey: String { "llmFolder.\(repoID)" }
    private var savedFolder: URL? {
        UserDefaults.standard.string(forKey: folderKey).map { URL(filePath: $0) }
    }

    func isDownloaded() -> Bool {
        guard let folder = savedFolder,
              let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        return files.contains("config.json") && files.contains { $0.hasSuffix(".safetensors") }
    }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let downloader: any Downloader = #hubDownloader()
        let folder = try await downloader.download(
            id: repoID,
            revision: "main",
            matching: ["*.safetensors", "*.json", "*.jinja"],
            useLatest: false,
            progressHandler: { progress($0.fractionCompleted) })
        UserDefaults.standard.set(folder.path, forKey: folderKey)
        Log.models.info("cleanup model downloaded to \(folder.path)")
    }

    func load() async throws {
        guard container == nil else { return }
        guard isDownloaded(), let folder = savedFolder else { throw ModelError.notDownloaded }
        // Loading from a local directory never touches the network (offline after first download).
        let configuration = ModelConfiguration(directory: folder, extraEOSTokens: ["<|im_end|>"])
        container = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration)
    }

    func unload() async {
        container = nil
    }

    func clean(_ transcript: String) async throws -> String {
        try await load()
        guard let container else { throw ModelError.notDownloaded }
        let session = ChatSession(
            container,
            instructions: CleanupPrompt.system,
            generateParameters: GenerateParameters(maxTokens: Self.maxTokens(for: transcript), temperature: 0),
            additionalContext: ["enable_thinking": false])
        var output = ""
        for try await chunk in session.streamResponse(to: CleanupPrompt.userMessage(for: transcript)) {
            try Task.checkCancellation()
            output += chunk
        }
        return Self.stripThinking(output)
    }

    /// Roughly 1 token ≈ 4 chars. Allows ~2× the input, capped at 2048.
    static func maxTokens(for transcript: String) -> Int {
        min(2048, transcript.count / 2 + 64)
    }

    /// Qwen3 can still emit an empty <think></think> block when thinking is disabled.
    static func stripThinking(_ text: String) -> String {
        text.replacing(#/<think>[\s\S]*?</think>/#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
