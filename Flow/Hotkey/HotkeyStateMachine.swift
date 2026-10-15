import Foundation

enum HotkeyInput: Equatable, Sendable {
    case hotkeyDown(at: TimeInterval)
    case hotkeyUp(at: TimeInterval)
    /// Any other key press or mouse click while the hotkey is engaged.
    case otherInput(at: TimeInterval)
    case escape(at: TimeInterval)
    /// Timer callback scheduled `holdThreshold` after `hotkeyDown`.
    case tick(at: TimeInterval)
}

enum CancelReason: Equatable, Sendable {
    case chord
    case escape
}

enum HotkeyAction: Equatable, Sendable {
    /// Key went down: start capturing audio, no UI yet.
    case begin
    /// Recording is real (held past the threshold, or tapped into hands-free mode): show the pill.
    case confirm
    /// Released after a hold, or pressed again in hands-free mode: process the audio.
    case finish
    case cancel(CancelReason)
}

/// Pure tap-to-toggle + hold-to-talk logic. Knows nothing about CGEvents or timers.
///
/// - Quick tap (< 0.3 s): latches hands-free recording; the next press stops it.
/// - Hold (≥ 0.3 s): push-to-talk; releasing stops it.
struct HotkeyStateMachine: Sendable {
    static let holdThreshold: TimeInterval = 0.3

    enum Phase: Equatable, Sendable {
        case idle
        /// Key is down; not yet known whether this is a tap or a hold.
        case pending(since: TimeInterval)
        /// Push-to-talk: key held past the threshold.
        case holding
        /// Hands-free: key was tapped; waiting for the next press.
        case latched
    }

    private(set) var phase: Phase = .idle

    var isEngaged: Bool { phase != .idle }

    /// Forgets any in-progress gesture (e.g. after the recording stopped by itself).
    mutating func reset() { phase = .idle }

    mutating func handle(_ input: HotkeyInput) -> HotkeyAction? {
        switch input {
        case .hotkeyDown(let time):
            switch phase {
            case .idle:
                phase = .pending(since: time)
                return .begin
            case .latched:
                phase = .idle
                return .finish
            case .pending, .holding:
                return nil // key auto-repeat
            }

        case .tick(let time):
            guard case .pending(let since) = phase, time - since >= Self.holdThreshold else { return nil }
            phase = .holding
            return .confirm

        case .hotkeyUp(let time):
            switch phase {
            case .idle, .latched:
                return nil
            case .pending(let since):
                if time - since >= Self.holdThreshold {
                    phase = .idle
                    return .finish
                }
                phase = .latched
                return .confirm
            case .holding:
                phase = .idle
                return .finish
            }

        case .otherInput:
            // While the key is physically down, another key or click means a shortcut (⌥E, ⌥-click).
            // In hands-free mode, clicking into a text box or typing must not stop the recording.
            switch phase {
            case .pending, .holding:
                phase = .idle
                return .cancel(.chord)
            case .idle, .latched:
                return nil
            }

        case .escape:
            guard isEngaged else { return nil }
            phase = .idle
            return .cancel(.escape)
        }
    }
}
