import Testing
@testable import Flow

struct QuickCleanerTests {
    @Test(arguments: [
        ("um I think so", "I think so."),
        ("Uh, sounds good.", "Sounds good."),
        ("UM hello", "Hello."),
        ("hmm, okay", "Okay."),
        ("mm yes", "Yes."),
        ("er, erm, fine", "Fine."),
        ("send it, uh, tomorrow", "Send it, tomorrow."),
        ("Umm, uhh, hmmm sure", "Sure."),
    ])
    func dropsStandaloneFillers(input: String, expected: String) {
        #expect(QuickCleaner.clean(input) == expected)
    }

    @Test(arguments: [
        ("I left my umbrella", "I left my umbrella."),
        ("ask her about the error", "Ask her about the error."),
        ("summer plans", "Summer plans."),
        ("uh-huh", "Uh-huh."),
    ])
    func leavesWordsThatOnlyContainFillers(input: String, expected: String) {
        #expect(QuickCleaner.clean(input) == expected)
    }

    @Test func fillerKeepsTheSentenceEndItCarried() {
        #expect(QuickCleaner.clean("Is it ready, uh?") == "Is it ready?")
        #expect(QuickCleaner.clean("That's it um.") == "That's it.")
        #expect(QuickCleaner.clean("you're coming, uh?") == "You're coming?")
    }

    @Test(arguments: [
        ("i i i think", "I think."),
        ("the the problem", "The problem."),
        ("The the end", "The end."),
        ("I, I think so", "I think so."),
        ("I- I think so", "I think so."),
        ("we we we should go", "We should go."),
        ("the um the plan", "The plan."),
        ("Done. The the end", "Done. The end."),
        ("yes i i think", "Yes I think."),
    ])
    func collapsesImmediateRepeats(input: String, expected: String) {
        #expect(QuickCleaner.clean(input) == expected)
    }

    @Test func keepsRepeatsAcrossSentencesAndGrammaticalDoubles() {
        #expect(QuickCleaner.clean("I said so. So what") == "I said so. So what.")
        #expect(QuickCleaner.clean("I know that that works") == "I know that that works.")
        #expect(QuickCleaner.clean("we had had enough") == "We had had enough.")
    }

    @Test(arguments: [
        ("yes i'll do it", "Yes I'll do it."),
        ("i'm here", "I'm here."),
        ("maybe i've got it", "Maybe I've got it."),
        ("then i'd go", "Then I'd go."),
        ("so i said no", "So I said no."),
        ("ok i’m ready", "Ok I’m ready."),
        ("it is in the bin", "It is in the bin."),
    ])
    func capitalisesTheFirstPersonPronoun(input: String, expected: String) {
        #expect(QuickCleaner.clean(input) == expected)
    }

    @Test func capitalisesFirstLetterAndCollapsesSpaces() {
        #expect(QuickCleaner.clean("  hello   there  ") == "Hello there.")
        #expect(QuickCleaner.clean("hello\nthere") == "Hello there.")
        #expect(QuickCleaner.clean("iPhone is great") == "iPhone is great.")
    }

    @Test(arguments: [
        ("Done!", "Done!"),
        ("Really?", "Really?"),
        ("Wait...", "Wait..."),
        ("Sounds good.", "Sounds good."),
        ("okay,", "Okay."),
        ("first this;", "First this."),
        ("send it now", "Send it now."),
    ])
    func endsWithPunctuation(input: String, expected: String) {
        #expect(QuickCleaner.clean(input) == expected)
    }

    @Test(arguments: [
        ("what time is it", "What time is it?"),
        ("Why not", "Why not?"),
        ("how do I fix this", "How do I fix this?"),
        ("can you send it", "Can you send it?"),
        ("does it work", "Does it work?"),
        ("Should we go", "Should we go?"),
        ("um where is the file", "Where is the file?"),
        ("what's the plan", "What's the plan?"),
        ("isn't it late", "Isn't it late?"),
        ("don't you think", "Don't you think?"),
        ("WHO is there", "WHO is there?"),
    ])
    func questionWordsEndWithAQuestionMark(input: String, expected: String) {
        #expect(QuickCleaner.clean(input) == expected)
    }

    @Test(arguments: ["", "   ", "um", "Uh, um.", "hmm...", "  er  "])
    func nothingLeftReturnsEmpty(input: String) {
        #expect(QuickCleaner.clean(input) == "")
    }
}
