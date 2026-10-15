/// Collects samples up to a hard cap (the 5-minute recording limit).
struct SampleAccumulator: Sendable {
    let maxSamples: Int
    private(set) var samples: [Float] = []

    init(maxSamples: Int) { self.maxSamples = maxSamples }

    var isFull: Bool { samples.count >= maxSamples }

    /// Appends up to the cap. Returns true only for the append that makes it full.
    mutating func append(_ newSamples: [Float]) -> Bool {
        guard !isFull else { return false }
        samples.append(contentsOf: newSamples.prefix(maxSamples - samples.count))
        return isFull
    }
}
