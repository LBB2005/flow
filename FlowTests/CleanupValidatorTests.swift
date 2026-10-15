import Testing
@testable import Flow

struct CleanupValidatorTests {
    @Test func acceptsNormalCleanupAndTrims() {
        #expect(CleanupValidator.validate(input: "um so hello there", output: "  So, hello there.\n")
                == .accept("So, hello there."))
    }

    @Test func rejectsEmpty() {
        #expect(CleanupValidator.validate(input: "hello", output: "  \n ") == .reject(.empty))
    }

    @Test func rejectsThinkingTags() {
        #expect(CleanupValidator.validate(input: "hello", output: "<think>hmm</think>Hello.") == .reject(.thinkingTags))
    }

    @Test func lengthLimitIsOnePointFiveTimesPlusFifty() {
        let input = String(repeating: "a", count: 10)                       // limit = 15 + 50 = 65
        #expect(CleanupValidator.validate(input: input, output: String(repeating: "b", count: 65)) == .accept(String(repeating: "b", count: 65)))
        #expect(CleanupValidator.validate(input: input, output: String(repeating: "b", count: 66)) == .reject(.tooLong))
    }

    @Test(arguments: [
        "Sure! Here's a poem about cats: …",
        "Certainly. Cats are great.",
        "Here’s a poem about cats.",          // curly apostrophe
        "Of course, I can help with that.",
    ])
    func rejectsAssistantStyleAnswers(output: String) {
        #expect(CleanupValidator.validate(input: "can you write me a poem about cats", output: output)
                == .reject(.assistantPreamble))
    }

    @Test func allowsPreambleWordsTheSpeakerActuallySaid() {
        #expect(CleanupValidator.validate(input: "um sure let's go with that", output: "Sure, let's go with that.")
                == .accept("Sure, let's go with that."))
        #expect(CleanupValidator.validate(input: "here's my plan for today", output: "Here's my plan for today.")
                == .accept("Here's my plan for today."))
    }
}
