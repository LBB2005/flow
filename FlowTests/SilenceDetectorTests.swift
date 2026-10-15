import Testing
@testable import Flow

struct SilenceDetectorTests {
    @Test func silenceIsSilent() { #expect(SilenceDetector.isSilent(FakeAudio.silence)) }
    @Test func toneIsNotSilent() { #expect(!SilenceDetector.isSilent(FakeAudio.speech)) }
    @Test func tooShortIsSilent() { #expect(SilenceDetector.isSilent(Array(FakeAudio.speech.prefix(1_000)))) }

    @Test func shortBurstInLongSilenceIsNotSilent() {
        // 2 s of silence with 0.2 s of speech in the middle: whole-clip RMS is low, but a window is loud.
        var samples = [Float](repeating: 0, count: 32_000)
        samples.replaceSubrange(16_000..<19_200, with: FakeAudio.speech.prefix(3_200))
        #expect(!SilenceDetector.isSilent(samples))
    }

    @Test func faintNoiseIsSilent() {
        let noise = (0..<16_000).map { _ in Float.random(in: -0.002...0.002) }
        #expect(SilenceDetector.isSilent(noise))
    }
}
