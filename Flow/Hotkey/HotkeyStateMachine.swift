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
    /// Held past the threshold: show the pill.
    case confirm
    /// Released after a real hold: process the audio.
    case finish
    /// Released too quickly: drop the audio silently.
    case discard
    case cancel(CancelReason)
}

/// Pure push-to-talk logic. Knows nothing about CGEvents or timers.
struct HotkeyStateMachine: Sendable {
    static let holdThreshold: TimeInterval = 0.3

    enum Phase: Equatable, Sendable {
        case idle
        case pending(since: TimeInterval)
        case active
    }

    private(set) var phase: Phase = .idle

    var isEngaged: Bool { phase != .idle }

    mutating func handle(_ input: HotkeyInput) -> HotkeyAction? {
        switch input {
        case .hotkeyDown(let time):
            guard phase == .idle else { return nil }
            phase = .pending(since: time)
            return .begin

        case .tick(let time):
            guard case .pending(let since) = phase, time - since >= Self.holdThreshold else { return nil }
            phase = .active
            return .confirm

        case .hotkeyUp(let time):
            switch phase {
            case .idle:
                return nil
            case .pending(let since):
                phase = .idle
                return time - since >= Self.holdThreshold ? .finish : .discard
            case .active:
                phase = .idle
                return .finish
            }

        case .otherInput:
            guard isEngaged else { return nil }
            phase = .idle
            return .cancel(.chord)

        case .escape:
            guard isEngaged else { return nil }
            phase = .idle
            return .cancel(.escape)
        }
    }
}
