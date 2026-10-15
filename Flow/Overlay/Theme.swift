import SwiftUI

/// Every visual constant for Flow's UI. Tweak the look here; no magic numbers in views.
/// Values come from docs/mockups/pill-decision.md (Midnight Capsule, notch "Slim Wings", A1 Calm Scroll).
enum Theme {
    enum Notch {
        /// Used on screens without a notch (lid closed, built-in display off).
        static let fallbackSize = CGSize(width: 190, height: 32)
        static let wingWidth: CGFloat = 75
        /// Error messages are longer, so the wings widen.
        static let wideWingWidth: CGFloat = 170
        static let extraHeight: CGFloat = 2
        static let cornerRadius: CGFloat = 16
        static let collapsedCornerRadius: CGFloat = 10
        static let wingPadding: CGFloat = 14
        static let contentSpacing: CGFloat = 6
        /// Room around the shape inside the (fixed-size) panel.
        static let panelPadding: CGFloat = 4

        static let background = Color.black
        static let foreground = Color.white
        static let timer = Color.white.opacity(0.7)
        static let accent = Color(red: 0x5B / 255, green: 0xD3 / 255, blue: 1)
        static let recording = Color(red: 1, green: 0x45 / 255, blue: 0x3A / 255)
        static let success = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
        static let cancelled = Color(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xA6 / 255)
        static let warning = Color(red: 1, green: 0x9F / 255, blue: 0x0A / 255)
        static let error = Color(red: 1, green: 0x45 / 255, blue: 0x3A / 255)

        static let font = Font.system(size: 12, weight: .medium)
        static let iconSize: CGFloat = 13
        static let recordingDotSize: CGFloat = 6
    }

    enum Waveform {
        static let barCount = 7
        static let barWidth: CGFloat = 3
        static let barSpacing: CGFloat = 3
        static let minBarHeight: CGFloat = 3
        static let maxBarHeight: CGFloat = 16
        /// How often a new bar is added (A1 "Calm Scroll").
        static let sampleInterval: TimeInterval = 0.12
        /// shown = prev + smoothing × (new − prev). 1 = raw, lower = calmer.
        static let smoothing: Float = 0.55
    }

    enum Motion {
        static let expand = Animation.spring(response: 0.46, dampingFraction: 0.72)
        static let collapseDuration: Double = 0.46
        static let contentFade = Animation.easeOut(duration: 0.26).delay(0.16)
        static let bar = Animation.timingCurve(0.3, 0.7, 0.4, 1, duration: 0.18)
        static let recordingBlink = Animation.easeInOut(duration: 0.6)
    }
}
