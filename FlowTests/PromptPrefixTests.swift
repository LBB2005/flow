import Testing
@testable import Flow

struct PromptPrefixTests {
    @Test func splitReturnsTheTokensBeforeTheFragment() {
        #expect(PromptPrefix.split(full: [1, 2, 3, 4, 5], fragment: [4, 5]) == [1, 2, 3])
    }

    @Test func splitRejectsAFragmentTheFullRenderDoesNotEndWith() {
        // The template rendered the new turn differently at the end of the conversation: no safe prefix.
        #expect(PromptPrefix.split(full: [1, 2, 3, 4, 5], fragment: [4, 6]) == nil)
        #expect(PromptPrefix.split(full: [1, 2, 3], fragment: [1, 2, 3, 4]) == nil)
    }

    @Test func splitRejectsAnEmptyPrefixOrFragment() {
        #expect(PromptPrefix.split(full: [1, 2], fragment: [1, 2]) == nil)
        #expect(PromptPrefix.split(full: [1, 2], fragment: []) == nil)
    }
}
