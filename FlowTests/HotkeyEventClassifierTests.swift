import Testing
@testable import Flow

struct HotkeyEventClassifierTests {
    private let rightOption = Hotkey.modifierOnly(.rightOption)
    private let ctrlSpace = Hotkey.combo(modifiers: .control, keyCode: KeyNames.space)

    private func classify(_ hotkey: Hotkey, _ kind: KeyEventKind, key: UInt16 = 0, flags: UInt64 = 0,
                          repeat isAutorepeat: Bool = false, engaged: Bool = false) -> ClassifiedEvent {
        HotkeyEventClassifier.classify(hotkey: hotkey, kind: kind, keyCode: key, flags: flags,
                                       isAutorepeat: isAutorepeat, engaged: engaged)
    }

    // Modifier-only (Right ⌥)

    @Test func rightOptionDownAndUp() {
        #expect(classify(rightOption, .flagsChanged, key: 61, flags: 0x80040) == .init(signal: .down, swallow: false))
        #expect(classify(rightOption, .flagsChanged, key: 61, flags: 0, engaged: true) == .init(signal: .up, swallow: false))
    }

    @Test func leftOptionIsIgnoredWhenIdle() {
        #expect(classify(rightOption, .flagsChanged, key: 58, flags: 0x80020) == .init(signal: nil, swallow: false))
    }

    @Test func otherModifierWhileEngagedIsOther() {
        #expect(classify(rightOption, .flagsChanged, key: 56, flags: 0x80042, engaged: true) == .init(signal: .other, swallow: false))
    }

    @Test func letterWhileEngagedIsOtherAndPassesThrough() {
        // Right ⌥ + E must still type the accent.
        #expect(classify(rightOption, .keyDown, key: 14, flags: 0x80040, engaged: true) == .init(signal: .other, swallow: false))
    }

    @Test func letterWhenIdlePassesThroughUntouched() {
        #expect(classify(rightOption, .keyDown, key: 14) == .init(signal: nil, swallow: false))
    }

    @Test func escapeWhileEngagedIsSwallowed() {
        #expect(classify(rightOption, .keyDown, key: KeyNames.escape, engaged: true) == .init(signal: .escape, swallow: true))
    }

    @Test func escapeWhenIdlePassesThrough() {
        #expect(classify(rightOption, .keyDown, key: KeyNames.escape) == .init(signal: nil, swallow: false))
    }

    @Test func mouseClickWhileEngagedIsOther() {
        // Review Focus 3: ⌥-click / ⌥-drag must cancel, and the click must still reach the app.
        #expect(classify(rightOption, .mouseDown, engaged: true) == .init(signal: .other, swallow: false))
        #expect(classify(rightOption, .mouseDown) == .init(signal: nil, swallow: false))
    }

    @Test func fnKeyUsesSecondaryFnFlag() {
        let fn = Hotkey.modifierOnly(.function)
        #expect(classify(fn, .flagsChanged, key: 63, flags: 0x800000) == .init(signal: .down, swallow: false))
        #expect(classify(fn, .flagsChanged, key: 63, flags: 0, engaged: true) == .init(signal: .up, swallow: false))
    }

    // Combo (⌃Space)

    @Test func comboDownIsSwallowed() {
        #expect(classify(ctrlSpace, .keyDown, key: KeyNames.space, flags: 0x40000) == .init(signal: .down, swallow: true))
    }

    @Test func comboAutorepeatIsSwallowedWithoutSignal() {
        #expect(classify(ctrlSpace, .keyDown, key: KeyNames.space, flags: 0x40000, repeat: true, engaged: true) == .init(signal: nil, swallow: true))
    }

    @Test func comboKeyUpWhileEngagedIsSwallowedUp() {
        #expect(classify(ctrlSpace, .keyUp, key: KeyNames.space, flags: 0x40000, engaged: true) == .init(signal: .up, swallow: true))
    }

    @Test func comboWithWrongModifiersPassesThrough() {
        #expect(classify(ctrlSpace, .keyDown, key: KeyNames.space, flags: 0x100000) == .init(signal: nil, swallow: false))
        #expect(classify(ctrlSpace, .keyDown, key: KeyNames.space, flags: 0x40000 | 0x20000) == .init(signal: nil, swallow: false))
    }

    @Test func plainSpaceTypesNormally() {
        #expect(classify(ctrlSpace, .keyDown, key: KeyNames.space) == .init(signal: nil, swallow: false))
    }

    @Test func otherKeyDuringComboCancels() {
        #expect(classify(ctrlSpace, .keyDown, key: 0, flags: 0x40000, engaged: true) == .init(signal: .other, swallow: false))
    }

    @Test func escapeDuringComboIsSwallowed() {
        #expect(classify(ctrlSpace, .keyDown, key: KeyNames.escape, flags: 0x40000, engaged: true) == .init(signal: .escape, swallow: true))
    }
}
