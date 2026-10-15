import CoreGraphics
import Testing
@testable import Flow

struct NotchGeometryTests {
    @Test func readsTheRealNotchFromAuxiliaryAreas() {
        // 14" MacBook Pro: 1512 pt wide, 32 pt notch, menu-bar areas either side.
        let notch = NotchGeometry.metrics(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                          safeAreaTop: 32, auxiliaryLeftWidth: 662, auxiliaryRightWidth: 662)
        #expect(notch == NotchMetrics(centerX: 756, width: 188, height: 32, top: 982))
    }

    @Test func fallsBackToAVirtualNotchWithoutOne() {
        let notch = NotchGeometry.metrics(screenFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
                                          safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil)
        #expect(notch == NotchMetrics(centerX: 1512 + 1280, width: 190, height: 32, top: 1440))
    }

    @Test func expandedSizeMatchesTheChosenDesign() {
        let notch = CGSize(width: 190, height: 32)
        #expect(NotchGeometry.expandedSize(notchSize: notch, state: .listening) == CGSize(width: 340, height: 34))
        #expect(NotchGeometry.expandedSize(notchSize: notch, state: .success) == CGSize(width: 340, height: 34))
        // Errors carry longer messages, so the wings widen.
        #expect(NotchGeometry.expandedSize(notchSize: notch, state: .error("Microphone access needed")).width == 530)
    }

    @Test func panelHangsFromTheTopEdgeCentredOnTheNotch() {
        let notch = NotchMetrics(centerX: 756, width: 188, height: 32, top: 982)
        let frame = NotchGeometry.panelFrame(notch: notch)
        #expect(frame.maxY == 982)
        #expect(frame.midX == 756)
        #expect(frame.width >= 188 + 2 * 170)
        #expect(frame.height >= 34)
    }
}
