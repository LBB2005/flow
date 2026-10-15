import Foundation

/// Cleans Whisper's raw output before anything else sees it.
enum TranscriptNormalizer {
    static func normalize(_ raw: String) -> String {
        // [BLANK_AUDIO], [MUSIC] etc. are never speech: remove them everywhere.
        var text = raw.replacing(#/\[[^\]]*\]/#, with: "")
        text = text.replacing(#/[ \t]{2,}/#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // (silence), *coughs* and ♪ are only noise when nothing else was said.
        let speech = text.replacing(#/\([^)]*\)|\*[^*]*\*|♪/#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return speech.isEmpty ? "" : text
    }
}
