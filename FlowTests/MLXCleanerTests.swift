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
}
