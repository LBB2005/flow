import Foundation

enum CleanupRejection: Equatable, Sendable {
    case empty
    case tooLong
    case assistantPreamble
    case thinkingTags
}

enum CleanupVerdict: Equatable, Sendable {
    case accept(String)
    case reject(CleanupRejection)
}

/// Decides whether the cleanup model's output is safe to paste (spec §6).
enum CleanupValidator {
    static let preambles = [
        "sure", "certainly", "of course", "absolutely", "here is", "here's",
        "okay, here", "i'd be happy", "i'm sorry", "as an ai",
    ]

    static func validate(input: String, output: String) -> CleanupVerdict {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return .reject(.empty) }
        if cleaned.contains("<think>") || cleaned.contains("</think>") { return .reject(.thinkingTags) }
        if Double(cleaned.count) > 1.5 * Double(input.count) + 50 { return .reject(.tooLong) }

        let outLower = normalizeApostrophes(cleaned.lowercased())
        let inLower = normalizeApostrophes(input.lowercased())
        for preamble in preambles where outLower.hasPrefix(preamble) && !inLower.contains(preamble) {
            return .reject(.assistantPreamble)
        }
        return .accept(cleaned)
    }

    private static func normalizeApostrophes(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
    }
}
