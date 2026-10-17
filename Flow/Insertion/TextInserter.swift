import Foundation

@MainActor
protocol TextInserter: AnyObject {
    func insert(_ text: String) async
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
    /// Accessibility couldn't tell.
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

    func insert(_ text: String) async {
        let focusState = focus.focusState()
        let saved = pasteboard.snapshot()
        let ourChange = pasteboard.setString(text)

        // Always paste: Chrome web inputs and Electron apps (Claude, Slack) often
        // report no focused text field even when one is focused. The focus check
        // only decides whether it's safe to restore the previous clipboard.
        keys.sendPaste()
        guard focusState == .editable else {
            Log.insert.info("focus not confirmed editable; pasted and kept text on clipboard")
            return
        }
        await sleep(Self.restoreDelay)
        if pasteboard.changeCount == ourChange {
            pasteboard.restore(saved)
        } else {
            Log.insert.info("clipboard changed during paste; not restoring")
        }
    }
}
