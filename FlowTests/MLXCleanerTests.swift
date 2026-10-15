import MLXLMCommon
import Testing
@testable import Flow

struct MLXCleanerTests {
    @Test func stripsThinkBlocks() {
        #expect(MLXCleaner.stripThinking("<think>\n\n</think>\n\nHello there.") == "Hello there.")
        #expect(MLXCleaner.stripThinking("<think>plan\nmore</think>Hi.") == "Hi.")
        #expect(MLXCleaner.stripThinking("  Plain.  ") == "Plain.")
    }

    @Test func tokenBudgetScalesWithInputAndIsCapped() {
        #expect(MLXCleaner.maxTokens(for: "") == 64)
        #expect(MLXCleaner.maxTokens(for: String(repeating: "a", count: 400)) == 264)
        #expect(MLXCleaner.maxTokens(for: String(repeating: "a", count: 100_000)) == 2048)
    }

    @Test func fewShotHistoryAlternatesWrappedTranscriptsAndCleanedReplies() {
        let history = MLXCleaner.fewShotHistory
        #expect(history.count == CleanupPrompt.examples.count * 2)
        for (index, example) in CleanupPrompt.examples.enumerated() {
            let user = history[index * 2], assistant = history[index * 2 + 1]
            #expect(user.role == .user)
            #expect(user.content == CleanupPrompt.userMessage(for: example.transcript))
            #expect(assistant.role == .assistant)
            #expect(assistant.content == example.cleaned)
        }
    }
}
