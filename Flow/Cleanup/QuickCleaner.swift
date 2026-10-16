import Foundation

/// Rule-based cleanup for short dictations, used instead of the model below
/// `DictationCoordinator.quickCleanupWordLimit` words (spec §11 amendment 6). Pure and instant.
///
/// Drops standalone fillers, collapses immediate stutters, capitalises "I", the first word
/// and makes sure the text ends with `.`, `?` or `!`. Whisper already punctuates and
/// capitalises most output, so this mostly removes what the model would.
enum QuickCleaner {
    /// A first word that makes the phrase a question when Whisper left it unpunctuated.
    static let questionWords: Set<String> = [
        "what", "why", "how", "when", "where", "who", "which",
        "can", "could", "would", "should", "will", "is", "are", "do", "does", "did", "have", "has",
        // Contracted forms of the same words.
        "what's", "how's", "when's", "where's", "who's",
        "can't", "couldn't", "wouldn't", "shouldn't", "won't", "isn't", "aren't",
        "don't", "doesn't", "didn't", "haven't", "hasn't",
    ]

    static let firstPerson: Set<String> = ["i", "i'm", "i'll", "i've", "i'd"]

    /// Doubles that are real English ("I know that that works", "we had had enough"), so not stutters.
    static let grammaticalRepeats: Set<String> = ["that", "had"]

    static func clean(_ transcript: String) -> String {
        var words: [String] = []
        for token in transcript.split(whereSeparator: \.isWhitespace).map(String.init) {
            let key = key(of: token)
            if isFiller(key) {
                // "Is it ready, uh?" keeps its question mark.
                if let mark = token.last, ".?!".contains(mark), let previous = words.last, !endsSentence(previous) {
                    words[words.count - 1] = trimmingSoftPunctuation(previous) + String(mark)
                }
                continue
            }
            if let previous = words.last, !key.isEmpty, key == self.key(of: previous),
               !endsSentence(previous), !grammaticalRepeats.contains(key) {
                // Keep the last repeat (it carries the punctuation that follows) with the first one's capital.
                words[words.count - 1] = previous.first?.isUppercase == true ? capitalisingFirstLetter(token) : token
                continue
            }
            words.append(firstPerson.contains(key) ? capitalisingFirstLetter(token) : token)
        }

        guard words.contains(where: { $0.contains { $0.isLetter || $0.isNumber } }) else { return "" }
        if words[0] == words[0].lowercased() { words[0] = capitalisingFirstLetter(words[0]) }

        let text = trimmingSoftPunctuation(words.joined(separator: " "))
        if let last = text.last, ".?!…".contains(last) { return text }
        return text + (questionWords.contains(key(of: words[0])) ? "?" : ".")
    }

    /// Whole-word fillers: um, uh, er, erm, hmm, mm (plus drawn-out "umm", "uhh", "hmmm", "mmm").
    static func isFiller(_ key: String) -> Bool {
        key.wholeMatch(of: /um+|uh+|er|erm|hm+|mm+/) != nil
    }

    /// Lowercased, apostrophes straightened, surrounding punctuation removed ("I," → "i", "I’m" → "i'm").
    private static func key(of token: String) -> String {
        token.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private static func endsSentence(_ token: String) -> Bool {
        guard let last = token.last else { return false }
        return ".?!…".contains(last)
    }

    /// Strips a trailing comma, semicolon, colon or dash ("okay," → "okay", "I-" → "I").
    private static func trimmingSoftPunctuation(_ text: String) -> String {
        var text = text
        while let last = text.last, ",;:-–—".contains(last) { text.removeLast() }
        return text
    }

    private static func capitalisingFirstLetter(_ token: String) -> String {
        guard let index = token.firstIndex(where: \.isLetter) else { return token }
        return token.replacingCharacters(in: index...index, with: token[index].uppercased())
    }
}
