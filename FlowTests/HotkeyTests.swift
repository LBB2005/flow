import Foundation
import Testing
@testable import Flow

struct HotkeyTests {
    @Test func defaultIsOptionRightArrow() {
        // Option + Right Arrow, chosen by the user (accepting that ⌥→ no longer jumps a word).
        #expect(Hotkey.default == .combo(modifiers: .option, keyCode: KeyNames.rightArrow))
        #expect(Hotkey.default.displayName == "⌥→")
        #expect(Hotkey.default.validation == .ok)
    }

    @Test func comboDisplayUsesStandardModifierOrder() {
        #expect(Hotkey.combo(modifiers: .control, keyCode: KeyNames.space).displayName == "⌃Space")
        #expect(Hotkey.combo(modifiers: [.command, .option], keyCode: 2).displayName == "⌥⌘D")
        #expect(Hotkey.combo(modifiers: [.command, .shift, .control, .option], keyCode: 0).displayName == "⌃⌥⇧⌘A")
    }

    @Test func unknownKeyCodeHasFallbackName() {
        #expect(KeyNames.name(for: 200) == "Key 200")
    }

    @Test(arguments: [
        Hotkey.modifierOnly(.rightOption),
        Hotkey.modifierOnly(.function),
        Hotkey.combo(modifiers: [.control, .shift], keyCode: KeyNames.space),
    ])
    func codableRoundTrip(hotkey: Hotkey) throws {
        let data = try JSONEncoder().encode(hotkey)
        #expect(try JSONDecoder().decode(Hotkey.self, from: data) == hotkey)
    }

    @Test func validation() {
        #expect(Hotkey.modifierOnly(.rightOption).validation == .ok)
        #expect(Hotkey.combo(modifiers: [.option, .command], keyCode: 2).validation == .ok)

        // Bare keys and shift-only combos would type characters.
        guard case .invalid = Hotkey.combo(modifiers: [], keyCode: 0).validation else { Issue.record("bare key accepted"); return }
        guard case .invalid = Hotkey.combo(modifiers: .shift, keyCode: 0).validation else { Issue.record("shift-only accepted"); return }
        // Esc is reserved for cancelling.
        guard case .invalid = Hotkey.combo(modifiers: .control, keyCode: KeyNames.escape).validation else { Issue.record("esc accepted"); return }

        guard case .warning(let spotlight) = Hotkey.combo(modifiers: .command, keyCode: KeyNames.space).validation else {
            Issue.record("⌘Space should warn"); return
        }
        #expect(spotlight.contains("Spotlight"))
        guard case .warning(let fn) = Hotkey.modifierOnly(.function).validation else { Issue.record("Fn should warn"); return }
        #expect(fn.contains("Do Nothing"))
    }

    @Test func modifierKeyFromKeyCode() {
        #expect(ModifierKey(keyCode: 61) == .rightOption)
        #expect(ModifierKey(keyCode: 63) == .function)
        #expect(ModifierKey(keyCode: 55) == nil) // left ⌘ is not supported on its own
    }

    @Test func modifierKeyIsDownUsesDeviceSpecificBit() {
        // 0x80000 = generic Option flag; 0x40 = right-Option device bit; 0x20 = left-Option device bit.
        #expect(ModifierKey.rightOption.isDown(flags: 0x80040))
        #expect(!ModifierKey.rightOption.isDown(flags: 0x80020))
        #expect(ModifierKey.function.isDown(flags: 0x800000))
    }

    @Test func modifierSetFromEventFlags() {
        #expect(ModifierSet(eventFlags: 0x40000 | 0x100000) == [.control, .command])
        #expect(ModifierSet(eventFlags: 0x80000 | 0x20000) == [.option, .shift])
        #expect(ModifierSet(eventFlags: 0x800000) == []) // Fn is not part of combos
    }
}
