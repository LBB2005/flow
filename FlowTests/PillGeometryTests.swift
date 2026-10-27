import CoreGraphics
import Foundation
import Testing
@testable import Flow

struct PillGeometryTests {
    // Built-in 14" display on the left, a 1440 pt external display to its right.
    let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982),
                   CGRect(x: 1512, y: 0, width: 2560, height: 1440)]

    @Test func picksTheScreenUnderTheMouse() {
        #expect(PillGeometry.screenIndex(mouse: CGPoint(x: 2000, y: 700), screenFrames: screens, fallback: 0) == 1)
        #expect(PillGeometry.screenIndex(mouse: CGPoint(x: 300, y: 300), screenFrames: screens, fallback: 1) == 0)
    }

    @Test func mouseOnTheTopRightEdgeStillCounts() {
        #expect(PillGeometry.screenIndex(mouse: CGPoint(x: 4072, y: 1440), screenFrames: screens, fallback: 0) == 1)
    }

    @Test func fallsBackWhenTheMouseIsOffEveryScreen() {
        #expect(PillGeometry.screenIndex(mouse: CGPoint(x: -50, y: -50), screenFrames: screens, fallback: 1) == 1)
        #expect(PillGeometry.screenIndex(mouse: CGPoint(x: -50, y: -50), screenFrames: screens, fallback: nil) == 0)
        #expect(PillGeometry.screenIndex(mouse: .zero, screenFrames: [], fallback: nil) == nil)
    }

    @Test func pillSits16ptAboveTheDockCentredOnTheScreen() {
        // visibleFrame of the external display with a 70 pt Dock at the bottom and a 25 pt menu bar.
        let visible = CGRect(x: 1512, y: 70, width: 2560, height: 1345)
        let frame = PillGeometry.panelFrame(visibleFrame: visible)
        #expect(frame.midX == visible.midX)
        #expect(frame.minY + Theme.Pill.panelBottomInset == visible.minY + Theme.Pill.bottomMargin)
        #expect(Theme.Pill.bottomMargin == 16)
        #expect(frame.size == Theme.Pill.panelSize)
    }

    @Test func panelLeavesRoomForTheRiseInAndTheCapsule() {
        #expect(Theme.Pill.panelBottomInset >= Theme.Motion.riseDistance)
        #expect(Theme.Pill.panelSize.height >= Theme.Pill.panelBottomInset + Theme.Pill.height)
    }

    @Test func labelsMatchTheMockup() {
        #expect(PillView.label(for: .success) == "Pasted")
        #expect(PillView.label(for: .thinking) == "Thinking…")
        #expect(PillView.label(for: .copied) == "Copied, press ⌘V")
        #expect(PillView.label(for: .error("Transcription failed")) == "Transcription failed")
    }

    @Test func elapsedIsMinutesAndSeconds() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(PillView.elapsed(from: start, to: start.addingTimeInterval(4.9)) == "0:04")
        #expect(PillView.elapsed(from: start, to: start.addingTimeInterval(125)) == "2:05")
    }
}
