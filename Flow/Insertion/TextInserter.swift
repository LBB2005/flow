enum InsertResult: Equatable, Sendable {
    /// Pasted into the focused app.
    case pasted
    /// No text field was focused; the text was left on the clipboard.
    case copiedOnly
}

@MainActor
protocol TextInserter: AnyObject {
    func insert(_ text: String) async -> InsertResult
}
