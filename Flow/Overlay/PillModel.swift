import Foundation
import Observation

@MainActor @Observable
final class PillModel {
    var state: PillState = .listening
    var isVisible = false
    var recordingStartedAt = Date.now
    /// Only changes when a new bar is added (every 120 ms), so the view isn't redrawn per audio chunk.
    private(set) var levels = WaveformHistory().levels

    @ObservationIgnored private var history = WaveformHistory()

    func push(level: Float, at time: TimeInterval) {
        if history.push(level: level, at: time) { levels = history.levels }
    }

    func resetLevels() {
        history.reset()
        levels = history.levels
    }
}
