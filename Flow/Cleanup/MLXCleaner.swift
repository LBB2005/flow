import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Local cleanup with a small Qwen3 model on the GPU via MLX.
actor MLXCleaner: Cleaner, ModelBackend {
    nonisolated let displayName = "Cleanup model (Qwen3)"

    private let repoID: String
    private let reusesPromptPrefix: Bool
    private var container: ModelContainer?
    /// The system prompt + few-shot turns, prefilled once per load. Nil when disabled or the template can't be split.
    private var prefix: PromptPrefix?
    private var loading: Task<Void, Error>?

    /// `reusesPromptPrefix: false` prefills the whole prompt on every clean (the reference behaviour, for tests).
    init(repoID: String, reusesPromptPrefix: Bool = true) {
        self.repoID = repoID
        self.reusesPromptPrefix = reusesPromptPrefix
    }

    /// Whether cleans start from the cached prompt prefix (for tests).
    var hasPromptPrefix: Bool { prefix != nil }

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
        Memory.cacheLimit = Self.gpuCacheLimit
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration)
        // Built before `container` is set, so no clean can start without it.
        if reusesPromptPrefix { prefix = await Self.buildPrefix(loaded) }
        container = loaded
        Log.models.notice("\(self.displayName, privacy: .public) loaded in \((clock.now - started) / .milliseconds(1), format: .fixed(precision: 0), privacy: .public) ms")
    }

    private static func buildPrefix(_ container: ModelContainer) async -> PromptPrefix? {
        do {
            let prefix = try await PromptPrefix.build(
                container: container,
                leading: leadingMessages,
                probe: .user(CleanupPrompt.userMessage(for: "probe")),
                additionalContext: templateContext)
            if let prefix {
                Log.models.info("cleanup prompt prefix cached (\(prefix.tokens.count) tokens)")
            } else {
                Log.models.error("cleanup prompt prefix can't be split from the template; prefilling the whole prompt")
            }
            return prefix
        } catch {
            Log.models.error("cleanup prompt prefix failed: \(error.localizedDescription)")
            return nil
        }
    }

    func unload() async {
        container = nil
        prefix = nil
        // Freed weights otherwise stay in MLX's buffer pool, so unloading wouldn't return the memory.
        Memory.clearCache()
    }

    func clean(_ transcript: String) async throws -> String {
        try await load()
        guard let container else { throw ModelError.notDownloaded }
        let message = Chat.Message.user(CleanupPrompt.userMessage(for: transcript))
        let parameters = GenerateParameters(maxTokens: Self.maxTokens(for: transcript), temperature: 0)
        let session: ChatSession
        if let prefix, try await prefix.continues(
            into: message, leading: Self.leadingMessages, container: container, additionalContext: Self.templateContext)
        {
            // Starts from a copy of the prefilled system prompt + examples; only this turn is prefilled.
            session = ChatSession(
                container, cache: prefix.cacheCopy(), generateParameters: parameters,
                additionalContext: Self.templateContext)
        } else {
            session = ChatSession(
                container, instructions: CleanupPrompt.system, history: Self.fewShotHistory,
                generateParameters: parameters, additionalContext: Self.templateContext)
        }
        var output = ""
        for try await chunk in session.streamResponse(to: message.content) {
            try Task.checkCancellation()
            output += chunk
        }
        return Self.stripThinking(output)
    }

    /// Cap on MLX's pool of freed GPU buffers. Uncapped it holds ~0.8 GB after loading (and ~1.2 GB after
    /// unloading) on a Mac that's already swapping; generation reuses same-sized buffers, so this costs nothing.
    static let gpuCacheLimit = 128 * 1024 * 1024

    /// Qwen3 thinking off (spec: `enable_thinking: false`).
    static let templateContext: [String: any Sendable] = ["enable_thinking": false]

    /// Everything before the transcript's turn: the system prompt and the worked examples.
    static var leadingMessages: [Chat.Message] { [.system(CleanupPrompt.system)] + fewShotHistory }

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
