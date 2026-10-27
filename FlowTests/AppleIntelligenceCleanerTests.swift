import Foundation
import FoundationModels
import Testing
@testable import Flow

struct AppleIntelligenceCleanerTests {
    @Test func statusMapsEveryAvailability() {
        #expect(AppleIntelligenceStatus(.available) == .available)
        #expect(AppleIntelligenceStatus(.unavailable(.appleIntelligenceNotEnabled)) == .notEnabled)
        #expect(AppleIntelligenceStatus(.unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(AppleIntelligenceStatus(.unavailable(.modelNotReady)) == .modelNotReady)
    }

    @Test func onlyUnavailableStatusesExplainTheQwenFallback() {
        #expect(AppleIntelligenceStatus.available.fallbackMessage == nil)
        for status: AppleIntelligenceStatus in [.notEnabled, .deviceNotEligible, .modelNotReady, .unavailable] {
            let message = status.fallbackMessage ?? ""
            #expect(message.contains("Qwen3 1.7B"), "\(status): \(message)")
        }
        #expect(AppleIntelligenceStatus.notEnabled.fallbackMessage?.contains("System Settings") == true)
    }

    @Test func examplesAddAQuestionAndARequestButKeepTheInjectionExampleLast() {
        let examples = AppleIntelligenceCleaner.examples
        #expect(examples.count == CleanupPrompt.examples.count + AppleIntelligenceCleaner.extraExamples.count)
        #expect(examples.last?.transcript == CleanupPrompt.examples.last?.transcript)
        for shared in CleanupPrompt.examples {
            #expect(examples.contains { $0.transcript == shared.transcript && $0.cleaned == shared.cleaned })
        }
        #expect(AppleIntelligenceCleaner.extraExamples.contains { $0.cleaned.hasSuffix("?") })
    }

    @Test func transcriptIsInstructionsThenAlternatingExampleTurns() {
        let transcript = AppleIntelligenceCleaner.fewShotTranscript
        #expect(transcript.count == 1 + AppleIntelligenceCleaner.examples.count * 2)
        guard case .instructions(let instructions) = transcript.first else {
            Issue.record("first entry should be the instructions"); return
        }
        #expect(Self.text(instructions.segments) == CleanupPrompt.system)
        for (index, example) in AppleIntelligenceCleaner.examples.enumerated() {
            guard case .prompt(let prompt) = transcript[1 + index * 2],
                  case .response(let response) = transcript[2 + index * 2] else {
                Issue.record("example \(index) should be a prompt then a response"); return
            }
            #expect(Self.text(prompt.segments) == CleanupPrompt.userMessage(for: example.transcript))
            #expect(Self.text(response.segments) == example.cleaned)
        }
    }

    @Test func generationIsGreedyWithTheSharedTokenBudget() {
        let transcript = String(repeating: "a", count: 400)
        let options = AppleIntelligenceCleaner.options(for: transcript)
        #expect(options.samplingMode == .greedy)
        #expect(options.maximumResponseTokens == CleanupPrompt.maxTokens(for: transcript))
        #expect(CleanupPrompt.maxTokens(for: transcript) == MLXCleaner.maxTokens(for: transcript))
    }

    @Test func unavailableModelIsNotDownloadedAndFailsToLoadOrClean() async throws {
        let cleaner = AppleIntelligenceCleaner(status: { .notEnabled })
        #expect(!(await cleaner.isDownloaded()))
        try await cleaner.download { _ in }  // nothing to download: a no-op even when unavailable
        await #expect(throws: AppleIntelligenceError.unavailable(.notEnabled)) { try await cleaner.load() }
        await #expect(throws: AppleIntelligenceError.unavailable(.notEnabled)) { _ = try await cleaner.clean("hello there") }
        #expect(!(await cleaner.hasSpareSession))
    }

    private static func text(_ segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            if case .text(let text) = segment { text.content } else { "" }
        }.joined()
    }
}

struct CleanupEngineTests {
    @Test func appleIntelligenceIsUsedWhenAvailable() {
        #expect(CleanupEngine.resolve(.appleIntelligence, appleIntelligence: .available) == .appleIntelligence)
    }

    @Test func unavailableAppleIntelligenceFallsBackToQwen1_7B() {
        for status: AppleIntelligenceStatus in [.notEnabled, .deviceNotEligible, .modelNotReady, .unavailable] {
            #expect(CleanupEngine.resolve(.appleIntelligence, appleIntelligence: status)
                == .mlx(repoID: CleanupModelChoice.qwen3_1_7b.repoID))
        }
    }

    @Test func qwenChoicesIgnoreAppleIntelligence() {
        for status: AppleIntelligenceStatus in [.available, .notEnabled] {
            #expect(CleanupEngine.resolve(.qwen3_1_7b, appleIntelligence: status)
                == .mlx(repoID: CleanupModelChoice.qwen3_1_7b.repoID))
            #expect(CleanupEngine.resolve(.qwen3_4b, appleIntelligence: status)
                == .mlx(repoID: CleanupModelChoice.qwen3_4b.repoID))
        }
    }

    @Test func makesTheMatchingCleaner() {
        #expect(CleanupEngine.appleIntelligence.makeCleaner() is AppleIntelligenceCleaner)
        #expect(CleanupEngine.mlx(repoID: CleanupModelChoice.qwen3_4b.repoID).makeCleaner() is MLXCleaner)
    }
}

/// A cleanup backend that records which engine built it, so tests can see what `AppModel` installed.
actor FakeCleanupBackend: Cleaner, ModelBackend {
    nonisolated let engine: CleanupEngine
    nonisolated let displayName = "Fake cleaner"
    init(_ engine: CleanupEngine) { self.engine = engine }
    func clean(_ transcript: String) async throws -> String { transcript }
    func isDownloaded() -> Bool { true }
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {}
    func load() async throws {}
    func unload() async {}
}

/// Apple Intelligence availability a test can change, like the user flipping it in System Settings.
final class StatusBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: AppleIntelligenceStatus
    init(_ value: AppleIntelligenceStatus) { _value = value }
    var value: AppleIntelligenceStatus {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

@MainActor
struct AppModelCleanupTests {
    private func app(choice: CleanupModelChoice, status: StatusBox) -> AppModel {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "FlowTests.\(UUID().uuidString)")!)
        settings.cleanupModel = choice
        return AppModel(
            settings: settings,
            appleIntelligenceStatus: { status.value },
            makeCleaner: { FakeCleanupBackend($0) })
    }

    private func installedEngine(_ app: AppModel) -> CleanupEngine? {
        (app.coordinator.cleaner as? FakeCleanupBackend)?.engine
    }

    @Test func usesAppleIntelligenceWhenAvailable() {
        let app = app(choice: .appleIntelligence, status: StatusBox(.available))
        #expect(app.cleanupEngine == .appleIntelligence)
        #expect(installedEngine(app) == .appleIntelligence)
    }

    @Test func fallsBackToQwenWhenAppleIntelligenceIsOff() {
        let app = app(choice: .appleIntelligence, status: StatusBox(.notEnabled))
        #expect(app.appleIntelligence == .notEnabled)
        #expect(app.cleanupEngine == .mlx(repoID: CleanupModelChoice.qwen3_1_7b.repoID))
        #expect(installedEngine(app) == .mlx(repoID: CleanupModelChoice.qwen3_1_7b.repoID))
    }

    @Test func switchesToAppleIntelligenceOnceItIsTurnedOn() async {
        let status = StatusBox(.notEnabled)
        let app = app(choice: .appleIntelligence, status: status)
        status.value = .available
        app.refreshCleanupEngine()
        #expect(app.appleIntelligence == .available)
        #expect(app.cleanupEngine == .appleIntelligence)
        #expect(installedEngine(app) == .appleIntelligence)
        await app.models.prepare(.cleaner).value
        #expect(app.models.status(of: .cleaner) == .ready)
    }

    @Test func switchesBackToQwenIfAppleIntelligenceGoesAway() {
        let status = StatusBox(.available)
        let app = app(choice: .appleIntelligence, status: status)
        status.value = .modelNotReady
        app.refreshCleanupEngine()
        #expect(installedEngine(app) == .mlx(repoID: CleanupModelChoice.qwen3_1_7b.repoID))
    }

    @Test func pickingQwenInSettingsUsesQwen() {
        let app = app(choice: .appleIntelligence, status: StatusBox(.available))
        app.settings.cleanupModel = .qwen3_4b
        app.switchCleanupModel()
        #expect(installedEngine(app) == .mlx(repoID: CleanupModelChoice.qwen3_4b.repoID))
    }
}
