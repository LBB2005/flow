/// Decides whether a recording contains anything worth transcribing, and where the speech in it is.
/// Whisper hallucinates text on silence, so silent clips never reach it.
enum SilenceDetector {
    /// ≈ -40 dBFS. Laptop-mic room noise sits well below this; speech sits well above it.
    static let rmsThreshold: Float = 0.01
    /// Silence kept before the first and after the last loud window, so soft word edges ("h", "f", a trailing "s")
    /// that sit below the threshold aren't clipped.
    static let leadMargin = 0.3
    static let tailMargin = 0.5

    static func isSilent(_ samples: [Float], sampleRate: Int = 16_000) -> Bool {
        guard samples.count >= sampleRate / 4 else { return true }
        return firstLoudWindow(samples, sampleRate: sampleRate) == nil
    }

    /// How much of `samples` is loud, in seconds (100 ms resolution).
    static func loudDuration(_ samples: [Float], sampleRate: Int = 16_000) -> Double {
        let window = sampleRate / 10
        let loud = stride(from: 0, to: samples.count, by: window)
            .filter { isLoud(samples[$0..<min($0 + window, samples.count)]) }.count
        return Double(loud) / 10
    }

    /// From just before the first loud window to just after the last one (spec §11 amendment 10), or nil if nothing
    /// is loud. Leading and trailing silence only costs decode time and invites hallucinated words.
    static func speechRange(_ samples: [Float], sampleRate: Int = 16_000) -> Range<Int>? {
        guard let first = firstLoudWindow(samples, sampleRate: sampleRate),
              let last = lastLoudWindow(samples, sampleRate: sampleRate) else { return nil }
        let start = max(0, first.lowerBound - Int(leadMargin * Double(sampleRate)))
        let end = min(samples.count, last.upperBound + Int(tailMargin * Double(sampleRate)))
        return start..<end
    }

    /// `samples` without leading and trailing silence; unchanged if it's all silence.
    static func trimmed(_ samples: [Float], sampleRate: Int = 16_000) -> [Float] {
        guard let range = speechRange(samples, sampleRate: sampleRate) else { return samples }
        return range == samples.indices ? samples : Array(samples[range])
    }

    // MARK: - 100 ms windows

    private static func firstLoudWindow(_ samples: [Float], sampleRate: Int) -> Range<Int>? {
        let window = sampleRate / 10
        var start = 0
        while start < samples.count {
            let end = min(start + window, samples.count)
            if isLoud(samples[start..<end]) { return start..<end }
            start = end
        }
        return nil
    }

    private static func lastLoudWindow(_ samples: [Float], sampleRate: Int) -> Range<Int>? {
        let window = sampleRate / 10
        // Same window grid as `firstLoudWindow`, walked backwards.
        var start = (samples.count - 1) / window * window
        while start >= 0, !samples.isEmpty {
            let end = min(start + window, samples.count)
            if isLoud(samples[start..<end]) { return start..<end }
            start -= window
        }
        return nil
    }

    static func isLoud(_ window: ArraySlice<Float>) -> Bool {
        rms(window) >= rmsThreshold
    }

    static func rms(_ window: ArraySlice<Float>) -> Float {
        guard !window.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in window { sum += sample * sample }
        return (sum / Float(window.count)).squareRoot()
    }
}
