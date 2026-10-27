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
    /// How long the target app gets to read the clipboard after ⌘V before the previous contents come back.
    static let restoreDelay: Duration = .milliseconds(400)

    private let pasteboard: Pasteboard
    private let keys: KeySender
    private let focus: FocusProbe
    private let sleep: @Sendable (Duration) async -> Void

    /// The clipboard restore still waiting out `restoreDelay`, with the user's contents it will put back.
    private var pending: (saved: PasteboardSnapshot, ourChange: Int, task: Task<Void, Never>)?

    /// The pending clipboard restore, so tests can await it.
    var restoring: Task<Void, Never>? { pending?.task }

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

    /// Returns as soon as ⌘V is sent, so the pill can say "Pasted" right away. The previous clipboard comes back
    /// `restoreDelay` later in the background, once the target app has read the pasted text.
    func insert(_ text: String) async {
        let focusState = focus.focusState()
        // A restore still pending from the previous dictation holds the user's real clipboard: take it over,
        // or this paste would save (and later "restore") the previous dictation's text.
        let saved: PasteboardSnapshot
        if let pending, pasteboard.changeCount == pending.ourChange {
            saved = pending.saved
        } else {
            saved = pasteboard.snapshot()
        }
        pending?.task.cancel()
        pending = nil
        let ourChange = pasteboard.setString(text)

        // Always paste: Chrome web inputs and Electron apps (Claude, Slack) often
        // report no focused text field even when one is focused. The focus check
        // only decides whether it's safe to restore the previous clipboard.
        keys.sendPaste()
        guard focusState == .editable else {
            Log.insert.info("focus not confirmed editable; pasted and kept text on clipboard")
            return
        }
        let task = Task { [weak self, sleep] in
            await sleep(Self.restoreDelay)
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            if self.pasteboard.changeCount == ourChange {
                self.pasteboard.restore(saved)
            } else {
                Log.insert.info("clipboard changed during paste; not restoring")
            }
        }
        pending = (saved, ourChange, task)
    }
}
