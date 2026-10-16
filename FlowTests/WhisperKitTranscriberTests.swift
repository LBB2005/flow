import Testing
import WhisperKit
@testable import Flow

struct WhisperKitTranscriberTests {
    @Test func englishIsForcedWithoutLanguageDetection() {
        let options = WhisperKitTranscriber.decodingOptions(language: "en")
        #expect(options.language == "en")
        #expect(options.detectLanguage == false)
        #expect(options.usePrefillPrompt)
        #expect(options.temperature == 0)
        #expect(options.withoutTimestamps)
    }

    @Test func noLanguageFallsBackToDetection() {
        let options = WhisperKitTranscriber.decodingOptions(language: nil)
        #expect(options.language == nil)
        #expect(options.detectLanguage)
        #expect(options.usePrefillPrompt)
    }
}
