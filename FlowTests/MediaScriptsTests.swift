import Testing
@testable import Flow

struct MediaScriptsTests {
    @Test func pageScriptsCanSitInsideAnAppleScriptString() {
        for js in [MediaScripts.pageJSPause, MediaScripts.pageJSResume] {
            #expect(!js.contains("\""))
            #expect(!js.contains("\\"))
            #expect(!js.contains("\n"))
        }
    }

    @Test func chromeScriptsRunTheirPageScript() {
        #expect(MediaScripts.chromePause.contains(MediaScripts.pageJSPause))
        #expect(MediaScripts.chromeResume.contains(MediaScripts.pageJSResume))
    }

    @Test func parsesPausedCount() {
        #expect(MediaScripts.parseChromePause("2\t").count == 2)
        #expect(MediaScripts.parseChromePause("2\t").error == nil)
    }

    @Test func parsesFirstTabError() {
        let parsed = MediaScripts.parseChromePause("0\tExecuting JavaScript through AppleScript is turned off.")
        #expect(parsed.count == 0)
        #expect(parsed.error == "Executing JavaScript through AppleScript is turned off.")
    }

    @Test func unreadableOutputMeansNothingPaused() {
        #expect(MediaScripts.parseChromePause("").count == 0)
        #expect(MediaScripts.parseChromePause("garbage").count == 0)
    }
}
