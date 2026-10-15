import Foundation

enum AudioLevel {
    static let floorDB: Float = -50

    /// RMS of the chunk mapped to 0…1 across -50…0 dBFS, for the waveform.
    static func normalized(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
        guard meanSquare > 0 else { return 0 }
        let db = 10 * log10(meanSquare)
        return min(1, max(0, (db - floorDB) / -floorDB))
    }
}
