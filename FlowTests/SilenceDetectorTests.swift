import Foundation
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

    // MARK: - Trimming (spec §11 amendment 10)

    /// `before` s of silence, `speech` s of tone, `after` s of silence.
    private func clip(before: Double, speech: Double, after: Double) -> [Float] {
        let tone = (0..<Int(speech * 16_000)).map { sin(Float($0) * 0.05) * 0.3 }
        return [Float](repeating: 0, count: Int(before * 16_000)) + tone + [Float](repeating: 0, count: Int(after * 16_000))
    }

    @Test func trimsLeadingAndTrailingSilenceKeepingAMargin() {
        let samples = clip(before: 2, speech: 1, after: 3)
        let range = SilenceDetector.speechRange(samples)
        #expect(range == (32_000 - 4_800)..<(48_000 + 8_000))
        #expect(SilenceDetector.trimmed(samples).count == 4_800 + 16_000 + 8_000)
    }

    @Test func pausesInsideTheSpeechAreKept() {
        let samples = clip(before: 1, speech: 1, after: 2) + clip(before: 0, speech: 1, after: 1)
        let range = SilenceDetector.speechRange(samples)
        #expect(range == (16_000 - 4_800)..<(80_000 + 8_000))
    }

    @Test func speechAtTheEdgesKeepsTheWholeClip() {
        let samples = clip(before: 0.1, speech: 2, after: 0.1)
        #expect(SilenceDetector.speechRange(samples) == samples.indices)
        #expect(SilenceDetector.trimmed(samples) == samples)
    }

    @Test func silenceHasNoSpeechRangeAndIsLeftAlone() {
        #expect(SilenceDetector.speechRange(FakeAudio.silence) == nil)
        #expect(SilenceDetector.trimmed(FakeAudio.silence) == FakeAudio.silence)
        #expect(SilenceDetector.speechRange([]) == nil)
    }

    @Test func loudDurationCountsLoudTenthsOfASecond() {
        #expect(SilenceDetector.loudDuration(clip(before: 1, speech: 0.5, after: 1)) == 0.5)
        #expect(SilenceDetector.loudDuration(FakeAudio.silence) == 0)
    }
}
