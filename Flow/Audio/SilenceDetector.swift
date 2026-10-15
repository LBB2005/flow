/// Decides whether a recording contains anything worth transcribing.
/// Whisper hallucinates text on silence, so silent clips never reach it.
enum SilenceDetector {
    /// ≈ -40 dBFS. Laptop-mic room noise sits well below this; speech sits well above it.
    static let rmsThreshold: Float = 0.01

    static func isSilent(_ samples: [Float], sampleRate: Int = 16_000) -> Bool {
        guard samples.count >= sampleRate / 4 else { return true }
        let window = sampleRate / 10
        var start = 0
        while start < samples.count {
            let end = min(start + window, samples.count)
            var sum: Float = 0
            for index in start..<end { sum += samples[index] * samples[index] }
            if (sum / Float(end - start)).squareRoot() >= rmsThreshold { return false }
            start = end
        }
        return true
    }
}
