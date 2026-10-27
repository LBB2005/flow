import SwiftUI

/// Every visual constant for Flow's UI. Tweak the look here; no magic numbers in views.
/// Values come from the "Meniscus" mockup at 85% (design/overlay-options/options/meniscus.css).
enum Theme {
    enum Pill {
        static let height: CGFloat = 36
        static let sidePadding: CGFloat = 14.5
        static let contentSpacing: CGFloat = 7.5
        /// Gap between the bottom of the pill and the top of the Dock (the screen's visible frame).
        static let bottomMargin: CGFloat = 16
        /// Room around the pill inside the (fixed-size) panel for the rise-in and the rim.
        /// The width also caps the pill: longer error messages truncate.
        static let panelSize = CGSize(width: 420, height: 84)
        static let panelBottomInset: CGFloat = 24

        static let font = Font.system(size: 11, weight: .medium)
        static let iconSize: CGFloat = 15
        /// SF Symbols draw inside the 15 pt icon box at this point size.
        static let symbolSize: CGFloat = 13
        static let iconWeight = Font.Weight.semibold
        /// Stroke of the drawn checkmark, matching the semibold symbols.
        static let checkmarkLineWidth: CGFloat = 1.45

        static let success = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
        static let warning = Color(red: 1, green: 0x9F / 255, blue: 0x0A / 255)
        static let copied = Color(red: 0x40 / 255, green: 0xC8 / 255, blue: 0xF4 / 255)
        static let error = Color(red: 1, green: 0x45 / 255, blue: 0x3A / 255)
        /// Soft wash of the outcome colour behind the icon, inside the glass.
        static let glowOpacity: Double = 0.3

        /// Bright lens rim: top-left and bottom-right edges catch the light.
        static let rimLight: (lead: Double, trail: Double) = (0.95, 0.55)
        static let rimDark: (lead: Double, trail: Double) = (0.6, 0.22)
        static let edgeOpacity: Double = 0.1
        /// The band of light that passes through the glass while thinking.
        static let sheenLight: Double = 0.7
        static let sheenDark: Double = 0.32
    }

    enum Waveform {
        static let barCount = 11
        static let barWidth: CGFloat = 2.5
        static let barSpacing: CGFloat = 2.5
        static let minBarHeight: CGFloat = 2.5
        static let maxBarHeight: CGFloat = 17
        static let boxHeight: CGFloat = 19
        /// How often a new bar is added (A1 "Calm Scroll").
        static let sampleInterval: TimeInterval = 0.12
        /// shown = prev + smoothing × (new − prev). 1 = raw, lower = calmer.
        static let smoothing: Float = 0.55
    }

    enum Motion {
        /// Rises 15 pt from below the resting place at 86% scale, with a little overshoot.
        static let riseDistance: CGFloat = 15
        static let appearScale: CGFloat = 0.86
        static let appear = Animation.spring(response: 0.5, dampingFraction: 0.68)
        static let disappearDuration: Double = 0.3
        static let disappear = Animation.timingCurve(0.5, 0, 0.75, 0, duration: disappearDuration)
        /// Width follows the content when the state changes.
        static let resize = Animation.spring(response: 0.45, dampingFraction: 0.78)
        static let contentIn = Animation.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.34)
        static let reducedFade = Animation.easeInOut(duration: 0.2)
        static let bar = Animation.timingCurve(0.3, 0.7, 0.4, 1, duration: 0.18)
        static let sheenPeriod: Double = 1.5
        static let checkmarkDraw = Animation.timingCurve(0.3, 0.8, 0.3, 1, duration: 0.42).delay(0.08)
    }
}
