import Testing
@testable import Flow

struct TranscriptNormalizerTests {
    @Test(arguments: ["[BLANK_AUDIO]", " (silence) ", "*coughs*", "♪♪", "[MUSIC] (applause)", "  ...  ", ""])
    func nonSpeechBecomesEmpty(raw: String) {
        #expect(TranscriptNormalizer.normalize(raw) == "")
    }

    @Test func stripsBracketMarkersAndCollapsesSpaces() {
        #expect(TranscriptNormalizer.normalize(" Hello  world [MUSIC] ") == "Hello world")
    }

    @Test func keepsParenthesesInsideRealSpeech() {
        #expect(TranscriptNormalizer.normalize("I said (quietly) hi") == "I said (quietly) hi")
    }

    @Test func keepsNewlines() {
        #expect(TranscriptNormalizer.normalize("first line\nsecond line") == "first line\nsecond line")
    }
}
