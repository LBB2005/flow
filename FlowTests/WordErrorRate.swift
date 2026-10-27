import Foundation

/// Word error rate for the transcription accuracy checks: (substitutions + deletions + insertions) / reference words.
enum WordErrorRate {
    /// Lowercased words without punctuation, so only the words themselves are compared.
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacing(#/[^a-z0-9' ]+/#, with: " ")
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    /// Words with their case and punctuation, to also catch changed sentence breaks and capitals.
    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func rate(reference: [String], hypothesis: [String]) -> Double {
        guard !reference.isEmpty else { return hypothesis.isEmpty ? 0 : 1 }
        return Double(distance(reference, hypothesis)) / Double(reference.count)
    }

    static func rate(reference: String, hypothesis: String) -> Double {
        rate(reference: words(reference), hypothesis: words(hypothesis))
    }

    static func distance(_ a: [String], _ b: [String]) -> Int {
        var previous = Array(0...b.count)
        for (i, wordA) in a.enumerated() {
            var current = [i + 1] + [Int](repeating: 0, count: b.count)
            for (j, wordB) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (wordA == wordB ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
