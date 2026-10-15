import Foundation

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

struct PasteboardSnapshot: Equatable, Sendable {
    /// One dictionary per pasteboard item: type identifier → data.
    var items: [[String: Data]]
}

@MainActor
protocol Pasteboard: AnyObject {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    func restore(_ snapshot: PasteboardSnapshot)
    /// Replaces the contents with plain text and returns the new change count.
    func setString(_ string: String) -> Int
}

@MainActor
protocol KeySender: AnyObject {
    /// Posts ⌘V to the frontmost app.
    func sendPaste()
}

enum FocusState: Sendable {
    case editable
    case notEditable
    /// Accessibility couldn't tell (e.g. some Electron apps).
    case unknown
}

@MainActor
protocol FocusProbe: AnyObject {
    func focusState() -> FocusState
}

@MainActor
final class PasteboardInserter: TextInserter {
    static let restoreDelay: Duration = .milliseconds(400)

    private let pasteboard: Pasteboard
    private let keys: KeySender
    private let focus: FocusProbe
    private let sleep: @Sendable (Duration) async -> Void

    init(
        pasteboard: Pasteboard,
        keys: KeySender,
        focus: FocusProbe,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.pasteboard = pasteboard
        self.keys = keys
        self.focus = focus
        self.sleep = sleep
    }

    func insert(_ text: String) async -> InsertResult {
        let focusState = focus.focusState()
        let saved = pasteboard.snapshot()
        let ourChange = pasteboard.setString(text)

        guard focusState != .notEditable else {
            Log.insert.info("no editable field focused; left text on clipboard")
            return .copiedOnly
        }
        keys.sendPaste()
        guard focusState == .editable else {
            Log.insert.info("focus unknown; pasted and kept text on clipboard")
            return .pasted
        }
        await sleep(Self.restoreDelay)
        if pasteboard.changeCount == ourChange {
            pasteboard.restore(saved)
        } else {
            Log.insert.info("clipboard changed during paste; not restoring")
        }
        return .pasted
    }
}
