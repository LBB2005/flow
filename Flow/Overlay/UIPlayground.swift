#if DEBUG
import Foundation

/// Drives the real overlay through every state without recording or loading models.
@MainActor
final class UIPlayground {
    private let overlay: OverlayController
    private var task: Task<Void, Never>?

    init(overlay: OverlayController) { self.overlay = overlay }

    func playAll() {
        task?.cancel()
        task = Task { [overlay] in
            await Self.animateListening(overlay, seconds: 4)
            let sequence: [PillState] = [.thinking, .success, .cancelled, .noSpeech, .copied, .error("Microphone access needed")]
            for state in sequence {
                guard !Task.isCancelled else { return }
                overlay.show(state)
                try? await Task.sleep(for: .seconds(2))
            }
            overlay.hide()
        }
    }

    func show(_ state: PillState) {
        task?.cancel()
        if state == .listening {
            task = Task { [overlay] in await Self.animateListening(overlay, seconds: 6) }
        } else {
            overlay.show(state)
        }
    }

    func hide() {
        task?.cancel()
        overlay.hide()
    }

    /// Fake speech: syllable rhythm that gets quiet, normal, then loud.
    private static func animateListening(_ overlay: OverlayController, seconds: Double) async {
        overlay.show(.listening)
        let step = 0.03
        for index in 0..<Int(seconds / step) {
            guard !Task.isCancelled else { return }
            let t = Double(index) * step
            let volume = t < seconds / 3 ? 0.25 : (t < 2 * seconds / 3 ? 0.6 : 1.0)
            let syllables = abs(sin(t * 8.3) * sin(t * 3.1 + 1))
            let pause = sin(t * 1.3) > 0.82 ? 0.1 : 1
            overlay.push(level: Float(volume * (0.2 + 0.8 * syllables) * pause))
            try? await Task.sleep(for: .seconds(step))
        }
    }
}
#endif
