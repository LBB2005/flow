import AppKit
import ApplicationServices

@MainActor
final class SystemPasteboard: Pasteboard {
    private let pasteboard = NSPasteboard.general

    var changeCount: Int { pasteboard.changeCount }

    func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type.rawValue] = data }
            }
            return entry
        })
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        let items = snapshot.items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    func setString(_ string: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        // Tells clipboard managers (Raycast, Maccy, …) not to record this temporary value.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        return pasteboard.changeCount
    }
}

@MainActor
final class SystemKeySender: KeySender {
    func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        // Explicit flags so a still-held hotkey modifier (e.g. ⌃ from ⌃Space) can't turn this into ⌃⌘V.
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

@MainActor
final class AXFocusProbe: FocusProbe {
    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    func focusState() -> FocusState {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // Chromium/Electron apps (Cursor, VS Code, Slack) only expose their
        // accessibility tree once a client asks for it.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var focused: CFTypeRef?
        switch AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) {
        case .success:
            break
        case .noValue:
            return .notEditable
        default:
            return .unknown
        }
        guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unknown }
        let element = focused as! AXUIElement

        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let role = role as? String, Self.textRoles.contains(role) {
            return .editable
        }
        for attribute in [kAXValueAttribute, kAXSelectedTextRangeAttribute] {
            var settable: DarwinBoolean = false
            if AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success, settable.boolValue {
                return .editable
            }
        }
        return .notEditable
    }
}
