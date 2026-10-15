import CoreGraphics

/// Where the notch is on a screen, in global screen coordinates (origin bottom-left).
struct NotchMetrics: Equatable, Sendable {
    var centerX: CGFloat
    var width: CGFloat
    var height: CGFloat
    /// The screen's top edge (the notch hangs down from here).
    var top: CGFloat
}

enum NotchGeometry {
    /// Reads the real notch from the menu-bar areas either side of it; falls back to a virtual one.
    static func metrics(screenFrame: CGRect, safeAreaTop: CGFloat,
                        auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?) -> NotchMetrics {
        if safeAreaTop > 0, let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
            let width = screenFrame.width - left - right
            if width > 0 {
                return NotchMetrics(centerX: screenFrame.minX + left + width / 2, width: width,
                                    height: safeAreaTop, top: screenFrame.maxY)
            }
        }
        let size = Theme.Notch.fallbackSize
        return NotchMetrics(centerX: screenFrame.midX, width: size.width, height: size.height, top: screenFrame.maxY)
    }

    static func wingWidth(for state: PillState) -> CGFloat {
        if case .error = state { return Theme.Notch.wideWingWidth }
        return Theme.Notch.wingWidth
    }

    static func expandedSize(notchSize: CGSize, state: PillState) -> CGSize {
        CGSize(width: notchSize.width + 2 * wingWidth(for: state),
               height: notchSize.height + Theme.Notch.extraHeight)
    }

    /// A fixed panel big enough for the widest state, so state changes never resize the window.
    static func panelFrame(notch: NotchMetrics) -> CGRect {
        let width = notch.width + 2 * Theme.Notch.wideWingWidth + 2 * Theme.Notch.panelPadding
        let height = notch.height + Theme.Notch.extraHeight + Theme.Notch.panelPadding
        return CGRect(x: notch.centerX - width / 2, y: notch.top - height, width: width, height: height)
    }
}
