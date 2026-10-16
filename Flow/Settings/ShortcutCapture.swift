/// Pure logic for the "Record shortcut" field. Feed it key events; it decides when a shortcut is complete.
struct ShortcutCapture {
    enum Result: Equatable {
        case captured(Hotkey)
        case cancelled
        case rejected(String)
    }

    static let loneModifierRejection = "That key can’t be used on its own. Try Right ⌥, Right ⌘ or a combo like ⌥→."

    /// Physical modifier key codes and their device-specific flag bits.
    private static let modifierMasks: [UInt16: UInt64] = [
        54: 0x10, 55: 0x08, 56: 0x02, 58: 0x20, 59: 0x01, 60: 0x04, 61: 0x40, 62: 0x2000, 63: 0x800000,
    ]
    private static let allModifierBits: UInt64 = modifierMasks.values.reduce(0, |)

    /// The one modifier pressed on its own so far, if any.
    private var candidate: UInt16?
    /// Set once anything else happens, so the lone-modifier gesture no longer counts.
    private var spoiled = false

    mutating func handleFlagsChanged(keyCode: UInt16, flags: UInt64) -> Result? {
        guard let mask = Self.modifierMasks[keyCode] else { return nil }
        let isDown = flags & mask != 0
        defer {
            if flags & Self.allModifierBits == 0 {
                candidate = nil
                spoiled = false
            }
        }
        if isDown {
            if candidate == nil && !spoiled { candidate = keyCode } else { spoiled = true }
            return nil
        }
        guard candidate == keyCode, !spoiled else { return nil }
        guard let key = ModifierKey(keyCode: keyCode) else {
            return .rejected(Self.loneModifierRejection)
        }
        return .captured(.modifierOnly(key))
    }

    mutating func handleKeyDown(keyCode: UInt16, flags: UInt64) -> Result {
        spoiled = true
        let modifiers = ModifierSet(eventFlags: flags)
        if keyCode == KeyNames.escape && modifiers.isEmpty { return .cancelled }
        let hotkey = Hotkey.combo(modifiers: modifiers, keyCode: keyCode)
        if case .invalid(let message) = hotkey.validation { return .rejected(message) }
        return .captured(hotkey)
    }
}
