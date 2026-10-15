import SwiftUI

/// The Midnight Capsule growing out of the notch: [left wing | camera | right wing].
struct NotchView: View {
    let model: PillModel

    var body: some View {
        let size = model.isExpanded
            ? NotchGeometry.expandedSize(notchSize: model.notchSize, state: model.state)
            : model.notchSize
        let radius = model.isExpanded ? Theme.Notch.cornerRadius : Theme.Notch.collapsedCornerRadius

        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                .fill(Theme.Notch.background)
                .frame(width: size.width, height: size.height)
            if model.isExpanded {
                wings(wingWidth: NotchGeometry.wingWidth(for: model.state), height: size.height)
                    .transition(.opacity.animation(Theme.Motion.contentFade))
            }
        }
        .animation(Theme.Motion.expand, value: model.isExpanded)
        .animation(Theme.Motion.expand, value: model.state)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func wings(wingWidth: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            leftWing
                .padding(.leading, Theme.Notch.wingPadding)
                .frame(width: wingWidth, alignment: .leading)
            Color.clear.frame(width: model.notchSize.width)
            rightWing
                .padding(.trailing, Theme.Notch.wingPadding)
                .frame(width: wingWidth, alignment: .trailing)
        }
        .frame(height: height)
        .font(Theme.Notch.font)
        .foregroundStyle(Theme.Notch.foreground)
    }

    @ViewBuilder
    private var leftWing: some View {
        switch model.state {
        case .listening: WaveformBars(levels: model.levels)
        case .thinking: ProgressView().controlSize(.mini).tint(Theme.Notch.accent)
        case .success: icon("checkmark.circle.fill", Theme.Notch.success)
        case .cancelled: icon("xmark.circle.fill", Theme.Notch.cancelled)
        case .noSpeech: icon("mic.slash.fill", Theme.Notch.warning)
        case .copied: icon("doc.on.clipboard.fill", Theme.Notch.accent)
        case .error: icon("exclamationmark.triangle.fill", Theme.Notch.error)
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        switch model.state {
        case .listening:
            HStack(spacing: Theme.Notch.contentSpacing) {
                Circle()
                    .fill(Theme.Notch.recording)
                    .frame(width: Theme.Notch.recordingDotSize, height: Theme.Notch.recordingDotSize)
                    .phaseAnimator([1.0, 0.3]) { dot, opacity in dot.opacity(opacity) } animation: { _ in Theme.Motion.recordingBlink }
                TimelineView(.periodic(from: model.recordingStartedAt, by: 1)) { context in
                    Text(Self.elapsed(from: model.recordingStartedAt, to: context.date))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Notch.timer)
                }
            }
        default:
            Text(Self.wingLabel(for: model.state)).lineLimit(1)
        }
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: Theme.Notch.iconSize, weight: .semibold))
            .foregroundStyle(color)
    }

    /// Short labels that fit a 75 pt wing (full sentences live in PillState.message).
    static func wingLabel(for state: PillState) -> String {
        switch state {
        case .listening: ""
        case .thinking: "Thinking"
        case .success: "Pasted"
        case .cancelled: "Esc"
        case .noSpeech: "No speech"
        case .copied: "⌘V"
        case .error(let message): message
        }
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

struct WaveformBars: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: Theme.Waveform.barSpacing) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.Notch.accent)
                    .frame(width: Theme.Waveform.barWidth, height: height(at: index))
            }
        }
        .frame(height: Theme.Waveform.maxBarHeight)
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
        model.isExpanded = true
        model.recordingStartedAt = .now.addingTimeInterval(-4)
        for step in 0..<20 { model.push(level: Float(abs(sin(Double(step) * 0.6))), at: Double(step) * 0.12) }
        return model
    }
}

private struct NotchPreview: View {
    let state: PillState
    var body: some View {
        NotchView(model: .preview(state))
            .frame(width: 560, height: 40)
            .background(Color(white: 0.85))
    }
}

#Preview("Listening") { NotchPreview(state: .listening) }
#Preview("Thinking") { NotchPreview(state: .thinking) }
#Preview("Pasted") { NotchPreview(state: .success) }
#Preview("Cancelled") { NotchPreview(state: .cancelled) }
#Preview("No speech") { NotchPreview(state: .noSpeech) }
#Preview("Copied") { NotchPreview(state: .copied) }
#Preview("Error") { NotchPreview(state: .error("Microphone access needed")) }
#endif
