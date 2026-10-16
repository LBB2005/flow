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
    private var loading: Task<Void, Error>?

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

    /// Loads once. Concurrent callers (warm-up, prepare, clean) share the in-flight load.
    func load() async throws {
        guard container == nil else { return }
        if let loading { return try await loading.value }
        guard isDownloaded(), let folder = savedFolder else { throw ModelError.notDownloaded }
        let task = Task { try await self.loadContainer(from: folder) }
        loading = task
        defer { loading = nil }
        try await task.value
    }

    private func loadContainer(from folder: URL) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        // Loading from a local directory never touches the network (offline after first download).
        let configuration = ModelConfiguration(directory: folder, extraEOSTokens: ["<|im_end|>"])
        container = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration)
        Log.models.notice("\(self.displayName, privacy: .public) loaded in \((clock.now - started) / .milliseconds(1), format: .fixed(precision: 0), privacy: .public) ms")
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
            history: Self.fewShotHistory,
            generateParameters: GenerateParameters(maxTokens: Self.maxTokens(for: transcript), temperature: 0),
            additionalContext: ["enable_thinking": false])
        var output = ""
        for try await chunk in session.streamResponse(to: CleanupPrompt.userMessage(for: transcript)) {
            try Task.checkCancellation()
            output += chunk
        }
        return Self.stripThinking(output)
    }

    /// The prompt's worked examples as prior chat turns, so the model sees the exact input → output shape.
    static var fewShotHistory: [Chat.Message] {
        CleanupPrompt.examples.flatMap { example -> [Chat.Message] in
            [.user(CleanupPrompt.userMessage(for: example.transcript)), .assistant(example.cleaned)]
        }
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
