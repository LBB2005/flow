import Testing
@testable import Flow

struct ShortcutCaptureTests {
    // Raw flag values: generic modifier bit | device-specific bit.
    let rightOptionDown: UInt64 = 0x80000 | 0x40
    let leftCommandDown: UInt64 = 0x100000 | 0x08
    let ctrl: UInt64 = 0x40000 | 0x01

    @Test func pressAndReleaseRightOptionCapturesModifierOnly() {
        var capture = ShortcutCapture()
        #expect(capture.handleFlagsChanged(keyCode: 61, flags: rightOptionDown) == nil)
        #expect(capture.handleFlagsChanged(keyCode: 61, flags: 0) == .captured(.modifierOnly(.rightOption)))
    }

    @Test func fnKeyCanBeCaptured() {
        var capture = ShortcutCapture()
        _ = capture.handleFlagsChanged(keyCode: 63, flags: 0x800000)
        #expect(capture.handleFlagsChanged(keyCode: 63, flags: 0) == .captured(.modifierOnly(.function)))
    }

    @Test func unsupportedLoneModifierIsRejected() {
        var capture = ShortcutCapture()
        _ = capture.handleFlagsChanged(keyCode: 55, flags: leftCommandDown)
        #expect(capture.handleFlagsChanged(keyCode: 55, flags: 0)
                == .rejected("That key can’t be used on its own. Try Right ⌥, Right ⌘ or a combo like ⌥→."))
    }

    @Test func twoModifiersTogetherCaptureNothing() {
        var capture = ShortcutCapture()
        #expect(capture.handleFlagsChanged(keyCode: 61, flags: rightOptionDown) == nil)
        #expect(capture.handleFlagsChanged(keyCode: 55, flags: rightOptionDown | leftCommandDown) == nil)
        #expect(capture.handleFlagsChanged(keyCode: 55, flags: rightOptionDown) == nil)
        #expect(capture.handleFlagsChanged(keyCode: 61, flags: 0) == nil)
    }

    @Test func modifierPlusKeyCapturesCombo() {
        var capture = ShortcutCapture()
        _ = capture.handleFlagsChanged(keyCode: 59, flags: ctrl)
        #expect(capture.handleKeyDown(keyCode: KeyNames.space, flags: ctrl)
                == .captured(.combo(modifiers: .control, keyCode: KeyNames.space)))
    }

    @Test func optionRightArrowCapturesTheDefault() {
        var capture = ShortcutCapture()
        _ = capture.handleFlagsChanged(keyCode: 58, flags: 0x80000 | 0x20)
        #expect(capture.handleKeyDown(keyCode: KeyNames.rightArrow, flags: 0x80000 | 0x20) == .captured(.default))
    }

    @Test func comboWithWarningIsStillCaptured() {
        var capture = ShortcutCapture()
        #expect(capture.handleKeyDown(keyCode: KeyNames.space, flags: 0x100000)
                == .captured(.combo(modifiers: .command, keyCode: KeyNames.space)))
    }

    @Test func bareKeyIsRejected() {
        var capture = ShortcutCapture()
        guard case .rejected = capture.handleKeyDown(keyCode: 0, flags: 0) else {
            Issue.record("bare A should be rejected"); return
        }
    }

    @Test func plainEscapeCancelsRecording() {
        var capture = ShortcutCapture()
        #expect(capture.handleKeyDown(keyCode: KeyNames.escape, flags: 0) == .cancelled)
    }
}
