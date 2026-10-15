import Foundation

/// Turns the mic's ~50 level readings per second into a calm, scrolling bar history:
/// one new bar per window, using the loudest reading in that window, eased toward the previous bar.
struct WaveformHistory: Sendable, Equatable {
    let interval: TimeInterval
    let smoothing: Float
    private(set) var levels: [Float]

    private var windowStart: TimeInterval?
    private var peak: Float = 0

    init(count: Int = Theme.Waveform.barCount,
         interval: TimeInterval = Theme.Waveform.sampleInterval,
         smoothing: Float = Theme.Waveform.smoothing) {
        self.interval = interval
        self.smoothing = smoothing
        self.levels = [Float](repeating: 0, count: count)
    }

    /// Returns true when a new bar was appended.
    @discardableResult
    mutating func push(level: Float, at time: TimeInterval) -> Bool {
        peak = max(peak, min(1, max(0, level)))
        guard let start = windowStart else {
            windowStart = time
            return false
        }
        guard time - start >= interval else { return false }
        let previous = levels.last ?? 0
        levels.removeFirst()
        levels.append(previous + smoothing * (peak - previous))
        peak = 0
        windowStart = time
        return true
    }

    mutating func reset() {
        levels = [Float](repeating: 0, count: levels.count)
        windowStart = nil
        peak = 0
    }
}
