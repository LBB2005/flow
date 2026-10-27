import CoreGraphics

/// Where the floating pill goes, in global screen coordinates (origin bottom-left).
enum PillGeometry {
    /// The screen the user is working on: the one under the mouse, else the fallback (key window's screen).
    static func screenIndex(mouse: CGPoint, screenFrames: [CGRect], fallback: Int?) -> Int? {
        // `contains` excludes the max edges, so a mouse on the very top/right pixel still counts.
        if let index = screenFrames.firstIndex(where: { $0.insetBy(dx: -0.5, dy: -0.5).contains(mouse) }) {
            return index
        }
        return fallback ?? (screenFrames.isEmpty ? nil : 0)
    }

    /// A fixed panel big enough for the widest state, centred above the Dock, so state changes never resize
    /// the window. `visibleFrame` already excludes the Dock and menu bar; the pill's bottom edge sits
    /// `Theme.Pill.bottomMargin` above it.
    static func panelFrame(visibleFrame: CGRect) -> CGRect {
        let size = Theme.Pill.panelSize
        let pillBottom = visibleFrame.minY + Theme.Pill.bottomMargin
        return CGRect(x: (visibleFrame.midX - size.width / 2).rounded(),
                      y: pillBottom - Theme.Pill.panelBottomInset,
                      width: size.width, height: size.height)
    }
}
