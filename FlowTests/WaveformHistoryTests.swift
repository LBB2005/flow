import Testing
@testable import Flow

struct WaveformHistoryTests {
    @Test func startsWithSevenZeroes() {
        let history = WaveformHistory()
        #expect(history.levels == [Float](repeating: 0, count: 7))
    }

    @Test func appendsOncePerWindowUsingTheLoudestLevel() {
        var history = WaveformHistory(count: 7, interval: 0.12, smoothing: 0.55)
        #expect(history.push(level: 0.2, at: 0) == false)     // opens the window
        #expect(history.push(level: 0.9, at: 0.05) == false)  // louder, same window
        #expect(history.push(level: 0.1, at: 0.12) == true)   // window closes: peak 0.9
        #expect(abs(history.levels.last! - 0.495) < 0.0001)   // 0 + 0.55 × (0.9 − 0)
        #expect(history.levels.count == 7)
    }

    @Test func smoothingEasesTowardNewLevels() {
        var history = WaveformHistory(count: 7, interval: 0.12, smoothing: 0.5)
        _ = history.push(level: 1, at: 0)
        _ = history.push(level: 1, at: 0.12)                  // 0.5
        _ = history.push(level: 1, at: 0.24)                  // 0.75
        #expect(Array(history.levels.suffix(2)) == [0.5, 0.75])
    }

    @Test func quietAndLoudSpeechDrawDifferentHeights() {
        var quiet = WaveformHistory(), loud = WaveformHistory()
        for step in 0..<10 {
            _ = quiet.push(level: 0.15, at: Double(step) * 0.12)
            _ = loud.push(level: 0.95, at: Double(step) * 0.12)
        }
        #expect(loud.levels.last! > quiet.levels.last! * 3)
    }

    @Test func clampsToZeroOne() {
        var history = WaveformHistory(count: 3, interval: 0.1, smoothing: 1)
        _ = history.push(level: 7, at: 0)
        _ = history.push(level: 7, at: 0.1)
        #expect(history.levels.last == 1)
    }

    @Test func resetZeroesEverything() {
        var history = WaveformHistory(count: 3, interval: 0.1, smoothing: 1)
        _ = history.push(level: 0.8, at: 0)
        _ = history.push(level: 0.8, at: 0.1)
        history.reset()
        #expect(history.levels == [0, 0, 0])
        #expect(history.push(level: 0.5, at: 5) == false) // a fresh window starts
    }
}
