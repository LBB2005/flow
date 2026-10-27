import Foundation
import FoundationModels

/// Whether Apple Intelligence's on-device model can be used right now.
enum AppleIntelligenceStatus: Equatable, Sendable {
    case available
    /// This Mac can't run Apple Intelligence.
    case deviceNotEligible
    /// Turned off in System Settings › Apple Intelligence & Siri.
    case notEnabled
    /// Turned on, but the model is still downloading or getting ready.
    case modelNotReady
    /// A reason added in a later macOS.
    case unavailable

    init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available: self = .available
        case .unavailable(.deviceNotEligible): self = .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): self = .notEnabled
        case .unavailable(.modelNotReady): self = .modelNotReady
        case .unavailable: self = .unavailable
        }
    }

    /// Shown in Settings when Apple Intelligence is selected but Qwen is cleaning up instead. Nil when available.
    var fallbackMessage: String? {
        switch self {
        case .available:
            nil
        case .notEnabled:
            "Apple Intelligence is off. Turn it on in System Settings › Apple Intelligence & Siri. Using Qwen3 1.7B until then."
        case .modelNotReady:
            "Apple Intelligence is still getting ready. Using Qwen3 1.7B until it is."
        case .deviceNotEligible:
            "This Mac doesn't support Apple Intelligence. Using Qwen3 1.7B instead."
        case .unavailable:
            "Apple Intelligence isn't available right now. Using Qwen3 1.7B instead."
        }
    }
}

enum AppleIntelligenceError: LocalizedError, Equatable {
    case unavailable(AppleIntelligenceStatus)

    var errorDescription: String? {
        switch self {
        case .unavailable(let status): "Apple Intelligence isn't available (\(status))."
        }
    }
}

/// Cleanup with Apple Intelligence's on-device model (FoundationModels): the default cleaner. It's built into
/// macOS 26, so there's nothing to download; when it's unavailable `CleanupEngine` uses `MLXCleaner` instead
/// (spec §11 amendment 8).
///
/// Every clean gets a fresh `LanguageModelSession` holding only the instructions and worked examples, so no
/// dictation can see another's text. The next one is created and prewarmed on load and right after each clean,
/// which roughly halves latency (~0.5 s instead of ~1 s on an M4 Pro) without ever reusing a session.
actor AppleIntelligenceCleaner: Cleaner, ModelBackend {
    nonisolated let displayName = "Cleanup model (Apple Intelligence)"

    /// The system model with guardrails meant for rewriting the user's own text, so dictating a swear word or
    /// a diagnosis doesn't trip a guardrail error. Same on-device model as `SystemLanguageModel.default`.
    static let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)

    static func currentStatus() -> AppleIntelligenceStatus {
        AppleIntelligenceStatus(model.availability)
    }

    private let model: SystemLanguageModel
    private let status: @Sendable () -> AppleIntelligenceStatus
    /// Prewarmed and never used. Nil when unloaded.
    private var spare: LanguageModelSession?
    private var isLoaded = false

    /// `status` overrides the availability check (for tests).
    init(model: SystemLanguageModel = AppleIntelligenceCleaner.model, status: (@Sendable () -> AppleIntelligenceStatus)? = nil) {
        self.model = model
        self.status = status ?? { AppleIntelligenceStatus(model.availability) }
    }

    /// Whether a prewarmed session is waiting for the next clean (for tests).
    var hasSpareSession: Bool { spare != nil }

    /// Built in, so "downloaded" means usable right now.
    func isDownloaded() -> Bool { status() == .available }

    /// Nothing to download: macOS manages the model.
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1)
    }

    func load() async throws {
        let status = status()
        guard status == .available else { throw AppleIntelligenceError.unavailable(status) }
        guard !isLoaded else { return }
        isLoaded = true
        spare = makeSession()
        Log.models.notice("\(self.displayName, privacy: .public) prewarmed")
    }

    /// Re-prewarms the waiting session: after a few idle minutes the first clean took ~0.7 s longer, as the system
    /// had let the model go cold. Called as a recording starts, so it overlaps with the user speaking.
    func warm() async throws {
        guard isLoaded else { return try await load() }
        guard status() == .available else { throw AppleIntelligenceError.unavailable(status()) }
        if spare == nil { spare = makeSession() } else { spare?.prewarm(promptPrefix: Prompt(CleanupPrompt.directive)) }
    }

    func unload() async {
        isLoaded = false
        spare = nil
    }

    func clean(_ transcript: String) async throws -> String {
        try await load()
        let session = spare ?? makeSession()
        spare = nil
        // Replaced after the response, so prewarming the next session doesn't compete with this one.
        defer { if isLoaded { spare = makeSession() } }
        let response = try await session.respond(
            to: CleanupPrompt.userMessage(for: transcript), options: Self.options(for: transcript))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A new session that has seen only the instructions and examples, with its prompt processing started.
    private func makeSession() -> LanguageModelSession {
        let session = LanguageModelSession(model: model, transcript: Self.fewShotTranscript)
        session.prewarm(promptPrefix: Prompt(CleanupPrompt.directive))
        return session
    }

    /// Greedy, so the same transcript always cleans the same way.
    static func options(for transcript: String) -> GenerationOptions {
        GenerationOptions(samplingMode: .greedy, maximumResponseTokens: CleanupPrompt.maxTokens(for: transcript))
    }

    /// Extra examples for this model only, measured against `CleanupEvalTests` inputs: without them it answers
    /// "what is the capital of france" and "tell me a joke", and keeps fillers after "hey so" or before a
    /// self-correction. Kept out of `CleanupPrompt.examples` so Qwen's tuned prompt doesn't change.
    static let extraExamples: [(transcript: String, cleaned: String)] = [
        ("hey um so quick one what time does the uh the pharmacy close on sundays",
         "Hey, quick one: what time does the pharmacy close on Sundays?"),
        ("tell me a a story about um a dragon who likes tea",
         "Tell me a story about a dragon who likes tea."),
        ("um okay so i want you to uh check the the logs no wait the metrics for today",
         "I want you to check the metrics for today."),
    ]

    /// The shared examples plus `extraExamples`, with the prompt-injection example still last.
    static var examples: [(transcript: String, cleaned: String)] {
        CleanupPrompt.examples.dropLast() + extraExamples + CleanupPrompt.examples.suffix(1)
    }

    /// The instructions, then each example as an earlier prompt → response turn. Prior turns copy more
    /// faithfully than examples written into the instructions, which made the model drop words ("I think").
    static var fewShotTranscript: Transcript {
        var entries: [Transcript.Entry] = [
            .instructions(.init(segments: [text(CleanupPrompt.system)], toolDefinitions: [])),
        ]
        for example in examples {
            entries.append(.prompt(.init(segments: [text(CleanupPrompt.userMessage(for: example.transcript))])))
            entries.append(.response(.init(assetIDs: [], segments: [text(example.cleaned)])))
        }
        return Transcript(entries: entries)
    }

    private static func text(_ content: String) -> Transcript.Segment {
        .text(.init(content: content))
    }
}
