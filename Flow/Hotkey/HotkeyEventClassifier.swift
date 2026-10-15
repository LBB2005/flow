enum KeyEventKind: Sendable { case keyDown, keyUp, flagsChanged, mouseDown }

enum HotkeySignal: Equatable, Sendable { case down, up, other, escape }

struct ClassifiedEvent: Equatable, Sendable {
    var signal: HotkeySignal?
    /// True = drop the event so the frontmost app never sees it.
    var swallow: Bool

    static let pass = ClassifiedEvent(signal: nil, swallow: false)
}

/// Pure mapping from a raw keyboard/mouse event to a hotkey signal.
/// Kept separate from the CGEventTap so every case is unit-testable.
enum HotkeyEventClassifier {
    static func classify(
        hotkey: Hotkey, kind: KeyEventKind, keyCode: UInt16, flags: UInt64,
        isAutorepeat: Bool, engaged: Bool
    ) -> ClassifiedEvent {
        if kind == .mouseDown {
            return engaged ? .init(signal: .other, swallow: false) : .pass
        }
        switch hotkey {
        case .modifierOnly(let key):
            switch kind {
            case .flagsChanged:
                if keyCode == key.keyCode {
                    return .init(signal: key.isDown(flags: flags) ? .down : .up, swallow: false)
                }
                return engaged ? .init(signal: .other, swallow: false) : .pass
            case .keyDown:
                guard engaged else { return .pass }
                if keyCode == KeyNames.escape { return .init(signal: .escape, swallow: true) }
                return .init(signal: .other, swallow: false)
            case .keyUp, .mouseDown:
                return .pass
            }

        case .combo(let modifiers, let comboKey):
            switch kind {
            case .keyDown:
                if keyCode == comboKey && ModifierSet(eventFlags: flags) == modifiers {
                    return .init(signal: isAutorepeat ? nil : .down, swallow: true)
                }
                guard engaged else { return .pass }
                if keyCode == comboKey { return .init(signal: nil, swallow: true) }
                if keyCode == KeyNames.escape { return .init(signal: .escape, swallow: true) }
                return .init(signal: .other, swallow: false)
            case .keyUp:
                return engaged && keyCode == comboKey ? .init(signal: .up, swallow: true) : .pass
            case .flagsChanged, .mouseDown:
                return .pass
            }
        }
    }
}
