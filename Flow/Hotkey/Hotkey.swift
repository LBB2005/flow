import CoreGraphics

/// A modifier key that can be held on its own as a push-to-talk hotkey.
enum ModifierKey: String, Codable, CaseIterable, Sendable {
    case rightOption, leftOption, rightCommand, rightControl, rightShift, function

    var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .leftOption: 58
        case .rightCommand: 54
        case .rightControl: 62
        case .rightShift: 60
        case .function: 63
        }
    }

    /// Device-dependent bit for this physical key in CGEventFlags / NSEvent.ModifierFlags raw values.
    var deviceFlagMask: UInt64 {
        switch self {
        case .rightOption: 0x40        // NX_DEVICERALTKEYMASK
        case .leftOption: 0x20         // NX_DEVICELALTKEYMASK
        case .rightCommand: 0x10       // NX_DEVICERCMDKEYMASK
        case .rightControl: 0x2000     // NX_DEVICERCTLKEYMASK
        case .rightShift: 0x04         // NX_DEVICERSHIFTKEYMASK
        case .function: 0x800000       // NX_SECONDARYFNMASK
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .leftOption: "Left ⌥"
        case .rightCommand: "Right ⌘"
        case .rightControl: "Right ⌃"
        case .rightShift: "Right ⇧"
        case .function: "🌐 Fn"
        }
    }

    init?(keyCode: UInt16) {
        guard let key = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = key
    }

    func isDown(flags: UInt64) -> Bool { flags & deviceFlagMask != 0 }
}

/// The modifiers that take part in a combo shortcut. Fn is deliberately excluded.
struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    static let control = ModifierSet(rawValue: 1 << 0)
    static let option = ModifierSet(rawValue: 1 << 1)
    static let shift = ModifierSet(rawValue: 1 << 2)
    static let command = ModifierSet(rawValue: 1 << 3)

    /// Reads the device-independent modifier bits shared by CGEventFlags and NSEvent.ModifierFlags.
    init(eventFlags: UInt64) {
        var set: ModifierSet = []
        if eventFlags & CGEventFlags.maskControl.rawValue != 0 { set.insert(.control) }
        if eventFlags & CGEventFlags.maskAlternate.rawValue != 0 { set.insert(.option) }
        if eventFlags & CGEventFlags.maskShift.rawValue != 0 { set.insert(.shift) }
        if eventFlags & CGEventFlags.maskCommand.rawValue != 0 { set.insert(.command) }
        self = set
    }

    /// Symbols in Apple's standard order: ⌃⌥⇧⌘.
    var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
            + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

enum Hotkey: Codable, Hashable, Sendable {
    /// Hold a single modifier key (e.g. Right ⌥).
    case modifierOnly(ModifierKey)
    /// Hold modifiers plus one key (e.g. ⌃Space).
    case combo(modifiers: ModifierSet, keyCode: UInt16)

    /// Option + Right Arrow (user's choice; ⌥⇧→ word selection still works because modifiers must match exactly).
    static let `default` = Hotkey.combo(modifiers: .option, keyCode: KeyNames.rightArrow)

    var displayName: String {
        switch self {
        case .modifierOnly(let key): key.displayName
        case .combo(let modifiers, let keyCode): modifiers.symbols + KeyNames.name(for: keyCode)
        }
    }
}

enum HotkeyValidation: Equatable, Sendable {
    case ok
    case warning(String)
    case invalid(String)
}

extension Hotkey {
    var validation: HotkeyValidation {
        switch self {
        case .modifierOnly(.function):
            return .warning("Set System Settings → Keyboard → “Press 🌐 key to” → “Do Nothing”, or macOS will also react to Fn.")
        case .modifierOnly:
            return .ok
        case .combo(let modifiers, let keyCode):
            if keyCode == KeyNames.escape {
                return .invalid("Esc is used to cancel a dictation.")
            }
            if modifiers.isEmpty || modifiers == .shift {
                return .invalid("Add ⌘, ⌥ or ⌃ so the shortcut doesn't type a character.")
            }
            if let clash = Self.systemShortcuts[self] {
                return .warning("\(displayName) is normally used for \(clash).")
            }
            return .ok
        }
    }

    private static let systemShortcuts: [Hotkey: String] = [
        .combo(modifiers: .command, keyCode: KeyNames.space): "Spotlight",
        .combo(modifiers: .control, keyCode: KeyNames.space): "switching input sources",
        .combo(modifiers: .command, keyCode: KeyNames.tab): "switching apps",
        .combo(modifiers: .command, keyCode: 12): "quitting apps",
        .combo(modifiers: .command, keyCode: 13): "closing windows",
        .combo(modifiers: .command, keyCode: 8): "copy",
        .combo(modifiers: .command, keyCode: 9): "paste",
        .combo(modifiers: .command, keyCode: 7): "cut",
        .combo(modifiers: .command, keyCode: 6): "undo",
        .combo(modifiers: [.command, .shift], keyCode: 20): "screenshots",
        .combo(modifiers: [.command, .shift], keyCode: 21): "screenshots",
        .combo(modifiers: [.command, .shift], keyCode: 23): "screenshots",
    ]
}
