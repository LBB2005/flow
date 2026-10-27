import Foundation
import Testing
@testable import Flow

/// Test signals: a loud tone stands in for speech, zeros for a pause.
enum Signal {
    static func speech(_ seconds: Double, level: Float = 0.3) -> [Float] {
        (0..<Int(seconds * 16_000)).map { sin(Float($0) * 0.05) * level }
    }
    static func pause(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * 16_000)) }
}

struct ChunkPlannerTests {
    private func cuts(_ samples: [Float], config: ChunkPlanner.Config = ChunkPlanner.Config(), batch: Int = 320) -> [Int] {
        var planner = ChunkPlanner(config: config)
        var cuts: [Int] = []
        for offset in stride(from: 0, to: samples.count, by: batch) {
            cuts += planner.append(Array(samples[offset..<min(offset + batch, samples.count)]))
        }
        return cuts
    }

    @Test func cutsInsideAPauseAfterEnoughSpeech() {
        // 7 s of speech, then a pause: once it's 0.5 s long, cut 0.25 s into it.
        let cuts = cuts(Signal.speech(7) + Signal.pause(1) + Signal.speech(2))
        #expect(cuts == [Int(7.25 * 16_000)])
    }

    @Test func noCutBeforeTheMinimumLength() {
        // 2 s + 1 s pause + 2 s: 5 s before the second pause, under the 6 s minimum.
        #expect(cuts(Signal.speech(2) + Signal.pause(1) + Signal.speech(2) + Signal.pause(1)).isEmpty)
    }

    @Test func shortGapsBetweenWordsAreNotPauses() {
        var samples: [Float] = []
        for _ in 0..<12 { samples += Signal.speech(0.8) + Signal.pause(0.3) }
        #expect(cuts(samples).isEmpty)
    }

    @Test func eachPauseAfterEnoughSpeechCutsOnce() {
        let samples = Signal.speech(7) + Signal.pause(2) + Signal.speech(8) + Signal.pause(0.6) + Signal.speech(1)
        #expect(cuts(samples) == [Int(7.25 * 16_000), Int((9 + 8 + 0.25) * 16_000)])
    }

    @Test func afterTwentySecondsAShortPauseIsEnough() {
        let samples = Signal.speech(21) + Signal.pause(0.3) + Signal.speech(2)
        #expect(cuts(samples) == [Int((21 + 0.1) * 16_000)])
    }

    @Test func nonStopSpeechIsCutAtItsQuietestMomentBeforeOneWhisperWindow() {
        // No pause at all: the cut lands on the dip at 18 s, so the piece fits one 30 s window.
        let samples = Signal.speech(18) + Signal.speech(0.2, level: 0.05) + Signal.speech(15)
        let cuts = cuts(samples)
        #expect(cuts.count == 1)
        let cut = cuts[0]
        #expect(cut >= 18 * 16_000 && cut < Int(18.2 * 16_000))
    }

    @Test func batchSizeDoesNotChangeTheCuts() {
        let samples = Signal.speech(7) + Signal.pause(0.7) + Signal.speech(9) + Signal.pause(1.2) + Signal.speech(3)
        let expected = cuts(samples, batch: samples.count)
        #expect(expected.count == 2)
        #expect(cuts(samples, batch: 341) == expected)
        #expect(cuts(samples, batch: 1) == expected)
    }

    @Test func piecesNeverExceedOneWhisperWindow() {
        var samples: [Float] = []
        for index in 0..<40 { samples += Signal.speech(Double(index % 7) + 0.5) + Signal.pause(index % 3 == 0 ? 0.6 : 0.2) }
        let cuts = [0] + cuts(samples) + [samples.count]
        for (start, end) in zip(cuts, cuts.dropFirst()) {
            #expect(end > start)
            #expect(end - start <= 27 * 16_000 + ChunkPlanner.frameLength)
        }
    }
}
