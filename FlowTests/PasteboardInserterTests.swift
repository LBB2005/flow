import Foundation
import Testing
@testable import Flow

@MainActor
final class FakePasteboard: Pasteboard {
    static let textType = "public.utf8-plain-text"
    var changeCount = 0
    var items: [[String: Data]] = []

    func snapshot() -> PasteboardSnapshot { PasteboardSnapshot(items: items) }
    func restore(_ snapshot: PasteboardSnapshot) { items = snapshot.items; changeCount += 1 }
    func setString(_ string: String) -> Int {
        items = [[Self.textType: Data(string.utf8)]]
        changeCount += 1
        return changeCount
    }
    var text: String? { items.first?[Self.textType].flatMap { String(data: $0, encoding: .utf8) } }
}

@MainActor final class FakeKeySender: KeySender {
    private(set) var pastes = 0
    func sendPaste() { pastes += 1 }
}

@MainActor final class FakeFocusProbe: FocusProbe {
    var state: FocusState
    init(_ state: FocusState) { self.state = state }
    func focusState() -> FocusState { state }
}

@MainActor
struct PasteboardInserterTests {
    let pasteboard = FakePasteboard()
    let keys = FakeKeySender()

    private func inserter(_ focus: FocusState, sleep: @escaping @Sendable (Duration) async -> Void = { _ in }) -> PasteboardInserter {
        PasteboardInserter(pasteboard: pasteboard, keys: keys, focus: FakeFocusProbe(focus), sleep: sleep)
    }

    @Test func editableFieldPastesAndRestoresNonTextClipboard() async {
        // Review Focus 2: an image on the clipboard must survive the dictation.
        let image: [[String: Data]] = [["public.png": Data([0x89, 0x50, 0x4E, 0x47]), "public.tiff": Data([1, 2])]]
        pasteboard.items = image
        let result = await inserter(.editable).insert("Hello world.")
        #expect(result == .pasted)
        #expect(keys.pastes == 1)
        #expect(pasteboard.items == image)
    }

    @Test func emptyClipboardIsRestoredToEmpty() async {
        _ = await inserter(.editable).insert("Hello")
        #expect(pasteboard.items.isEmpty)
    }

    @Test func noTextFieldLeavesTextOnClipboard() async {
        pasteboard.items = [["public.png": Data([1])]]
        let result = await inserter(.notEditable).insert("Hello world.")
        #expect(result == .copiedOnly)
        #expect(keys.pastes == 0)
        #expect(pasteboard.text == "Hello world.")
    }

    @Test func unknownFocusPastesButKeepsTextOnClipboard() async {
        pasteboard.items = [["public.png": Data([1])]]
        let result = await inserter(.unknown).insert("Hello world.")
        #expect(result == .pasted)
        #expect(keys.pastes == 1)
        #expect(pasteboard.text == "Hello world.")
    }

    @Test func doesNotClobberSomethingCopiedDuringTheDelay() async {
        pasteboard.items = [["public.png": Data([1])]]
        let pb = pasteboard
        let result = await inserter(.editable, sleep: { _ in
            await MainActor.run { _ = pb.setString("user copied this") }
        }).insert("Hello world.")
        #expect(result == .pasted)
        #expect(pasteboard.text == "user copied this")
    }
}
