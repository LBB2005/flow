import Testing
@testable import Flow

struct PillStateTests {
    @Test func copyMatchesSpec() {
        #expect(PillState.listening.message == "Listening")
        #expect(PillState.thinking.message == "Thinking…")
        #expect(PillState.cancelled.message == "Cancelled")
        #expect(PillState.noSpeech.message == "Didn't catch that")
        #expect(PillState.copied.message == "Copied, press ⌘V")
        #expect(PillState.error("Microphone unavailable").message == "Microphone unavailable")
        #expect(PillState.success.message == nil)
    }

    @Test func transientStatesAutoHide() {
        #expect(PillState.listening.autoHideAfter == nil)
        #expect(PillState.thinking.autoHideAfter == nil)
        #expect(PillState.success.autoHideAfter != nil)
        #expect(PillState.copied.autoHideAfter != nil)
    }
}
