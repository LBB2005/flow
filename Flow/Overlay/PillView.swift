import SwiftUI

/// "Meniscus": a small Liquid Glass capsule floating above the Dock. Monochrome content,
/// one system colour for the outcome icon, a band of light passing through while thinking.
struct PillView: View {
    let model: PillModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.isVisible {
                PillCapsule(model: model)
                    .transition(reduceMotion ? .opacity : Self.rise)
            }
        }
        .animation(visibilityAnimation, value: model.isVisible)
        .padding(.bottom, Theme.Pill.panelBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Rises from 15 pt below at 86% scale; sinks back the same way.
    private static let rise = AnyTransition.offset(y: Theme.Motion.riseDistance)
        .combined(with: .scale(scale: Theme.Motion.appearScale))
        .combined(with: .opacity)

    private var visibilityAnimation: Animation {
        if reduceMotion { return Theme.Motion.reducedFade }
        return model.isVisible ? Theme.Motion.appear : Theme.Motion.disappear
    }

    nonisolated static func label(for state: PillState) -> String {
        if case .success = state { return "Pasted" }
        return state.message ?? ""
    }

    nonisolated static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    static func glowColor(for state: PillState) -> Color {
        switch state {
        case .success: Theme.Pill.success
        case .noSpeech: Theme.Pill.warning
        case .copied: Theme.Pill.copied
        case .error: Theme.Pill.error
        case .listening, .thinking, .cancelled: .clear
        }
    }
}

/// The glass capsule. Its width follows the content, animating between states.
private struct PillCapsule: View {
    let model: PillModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PillContent(model: model)
            .keyframeAnimator(initialValue: ContentIn(), trigger: model.state) { content, value in
                content
                    .opacity(value.opacity)
                    .scaleEffect(value.scale)
                    .offset(y: value.offset)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    CubicKeyframe(1, duration: 0.34)
                }
                KeyframeTrack(\.scale) {
                    MoveKeyframe(reduceMotion ? 1 : 0.96)
                    CubicKeyframe(1, duration: 0.34)
                }
                KeyframeTrack(\.offset) {
                    MoveKeyframe(reduceMotion ? 0 : 3)
                    CubicKeyframe(0, duration: 0.34)
                }
            }
            .padding(.horizontal, Theme.Pill.sidePadding)
            .frame(height: Theme.Pill.height)
            .background { glow }
            .overlay {
                if model.state == .thinking { ThinkingSheen(opacity: sheenOpacity) }
            }
            .clipShape(Capsule())
            .glassEffect(.regular, in: .capsule)
            .overlay { rim }
            .animation(reduceMotion ? Theme.Motion.reducedFade : Theme.Motion.resize, value: model.state)
    }

    private var glow: some View {
        EllipticalGradient(colors: [PillView.glowColor(for: model.state).opacity(Theme.Pill.glowOpacity), .clear],
                           center: UnitPoint(x: 0.14, y: 0.5), startRadiusFraction: 0, endRadiusFraction: 0.63)
    }

    private var rim: some View {
        let strength = colorScheme == .dark ? Theme.Pill.rimDark : Theme.Pill.rimLight
        return ZStack {
            Capsule().strokeBorder(Color.primary.opacity(Theme.Pill.edgeOpacity), lineWidth: 0.5)
            // CSS `linear-gradient(150deg, …)` mapped onto a wide capsule.
            Capsule().strokeBorder(
                LinearGradient(stops: [
                    .init(color: .white.opacity(strength.lead), location: 0),
                    .init(color: .white.opacity(0), location: 0.32),
                    .init(color: .white.opacity(0), location: 0.68),
                    .init(color: .white.opacity(strength.trail), location: 1),
                ], startPoint: UnitPoint(x: 0.31, y: -0.56), endPoint: UnitPoint(x: 0.69, y: 1.56)),
                lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private var sheenOpacity: Double {
        colorScheme == .dark ? Theme.Pill.sheenDark : Theme.Pill.sheenLight
    }
}

private struct ContentIn {
    var opacity: Double = 1
    var scale: CGFloat = 1
    var offset: CGFloat = 0
}

private struct PillContent: View {
    let model: PillModel

    var body: some View {
        HStack(spacing: Theme.Pill.contentSpacing) {
            switch model.state {
            case .listening:
                WaveformBars(levels: model.levels)
                TimelineView(.periodic(from: model.recordingStartedAt, by: 1)) { context in
                    Text(PillView.elapsed(from: model.recordingStartedAt, to: context.date))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            case .thinking:
                ShimmerLabel(text: PillView.label(for: .thinking))
            default:
                OutcomeIcon(state: model.state).id(PillView.label(for: model.state))
                Text(PillView.label(for: model.state))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(Theme.Pill.font)
        .foregroundStyle(.primary)
    }
}

private struct OutcomeIcon: View {
    let state: PillState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    var body: some View {
        Group {
            switch state {
            case .success:
                CheckmarkShape()
                    .trim(from: 0, to: drawn)
                    .stroke(Theme.Pill.success,
                            style: StrokeStyle(lineWidth: Theme.Pill.checkmarkLineWidth, lineCap: .round, lineJoin: .round))
                    .onAppear {
                        if reduceMotion { drawn = 1 } else { withAnimation(Theme.Motion.checkmarkDraw) { drawn = 1 } }
                    }
            case .cancelled: symbol("xmark", .secondary)
            case .noSpeech: symbol("mic.slash", Theme.Pill.warning)
            case .copied: symbol("doc.on.clipboard", Theme.Pill.copied)
            case .error: symbol("exclamationmark.triangle", Theme.Pill.error)
            case .listening, .thinking: EmptyView()
            }
        }
        .frame(width: Theme.Pill.iconSize, height: Theme.Pill.iconSize)
    }

    private func symbol(_ name: String, _ style: some ShapeStyle) -> some View {
        Image(systemName: name)
            .font(.system(size: Theme.Pill.symbolSize, weight: Theme.Pill.iconWeight))
            .foregroundStyle(style)
    }
}

/// The mockup's tick: M5.5 12.5 l4.2 4.2 L18.5 7.5 in a 24 × 24 box.
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
        var path = Path()
        path.move(to: point(5.5, 12.5))
        path.addLine(to: point(9.7, 16.7))
        path.addLine(to: point(18.5, 7.5))
        return path
    }
}

/// A band of light that sweeps left to right through the glass. Static under Reduce Motion.
private struct ThinkingSheen: View {
    let opacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            GeometryReader { proxy in
                let width = proxy.size.width
                let band = width * 0.9
                // Band centre travels from -0.9 to 1.9 widths, eased like the mockup's sweep.
                let center = reduceMotion ? width / 2 : width * (-0.9 + 2.8 * SweepPhase.value(at: context.date))
                LinearGradient(colors: [.white.opacity(0), .white.opacity(reduceMotion ? opacity * 0.4 : opacity), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: band)
                    .offset(x: center - band / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// "Thinking…" in the dim ink with a brighter highlight sweeping through it.
private struct ShimmerLabel: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .overlay {
                if !reduceMotion {
                    TimelineView(.animation) { context in
                        let phase = -0.3 + 1.6 * SweepPhase.value(at: context.date)
                        Text(text)
                            .foregroundStyle(.primary)
                            .mask {
                                LinearGradient(stops: [
                                    .init(color: .clear, location: phase - 0.15),
                                    .init(color: .black, location: phase),
                                    .init(color: .clear, location: phase + 0.15),
                                ], startPoint: .leading, endPoint: .trailing)
                            }
                    }
                }
            }
    }
}

/// Shared clock for the sheen and the shimmer: 0…1 every `sheenPeriod`, eased with cubic-bezier(.45, 0, .3, 1).
private enum SweepPhase {
    static let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.45, y: 0), endControlPoint: UnitPoint(x: 0.3, y: 1))

    static func value(at date: Date) -> Double {
        let period = Theme.Motion.sheenPeriod
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return curve.value(at: t)
    }
}

struct WaveformBars: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: Theme.Waveform.barSpacing) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(.primary)
                    .frame(width: Theme.Waveform.barWidth, height: height(at: index))
            }
        }
        .frame(height: Theme.Waveform.boxHeight)
        .animation(Theme.Motion.bar, value: levels)
    }

    /// Slight per-bar variation so equal levels don't look like a flat block.
    private func height(at index: Int) -> CGFloat {
        let shaped = min(1, levels[index] * (0.85 + 0.15 * abs(sin(Float(index) * 1.9))))
        return Theme.Waveform.minBarHeight + CGFloat(shaped) * (Theme.Waveform.maxBarHeight - Theme.Waveform.minBarHeight)
    }
}

#if DEBUG
extension PillModel {
    static func preview(_ state: PillState) -> PillModel {
        let model = PillModel()
        model.state = state
        model.isVisible = true
        model.recordingStartedAt = .now.addingTimeInterval(-4)
        for step in 0..<20 { model.push(level: Float(abs(sin(Double(step) * 0.6))), at: Double(step) * 0.12) }
        return model
    }
}

private struct PillPreview: View {
    let state: PillState
    var body: some View {
        PillView(model: .preview(state))
            .frame(width: Theme.Pill.panelSize.width, height: Theme.Pill.panelSize.height)
            .background(LinearGradient(colors: [.pink.opacity(0.4), .indigo.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
    }
}

#Preview("Listening") { PillPreview(state: .listening) }
#Preview("Thinking") { PillPreview(state: .thinking) }
#Preview("Pasted") { PillPreview(state: .success) }
#Preview("Cancelled") { PillPreview(state: .cancelled) }
#Preview("No speech") { PillPreview(state: .noSpeech) }
#Preview("Copied") { PillPreview(state: .copied) }
#Preview("Error") { PillPreview(state: .error("Microphone access needed")) }
#endif
