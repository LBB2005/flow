enum PillState: Equatable, Sendable {
    case listening
    case thinking
    case success
    case cancelled
    case noSpeech
    case copied
    case error(String)

    var message: String? {
        switch self {
        case .listening: "Listening"
        case .thinking: "Thinking…"
        case .success: nil
        case .cancelled: "Cancelled"
        case .noSpeech: "Didn't catch that"
        case .copied: "Copied, press ⌘V"
        case .error(let message): message
        }
    }

    /// How long the pill stays up before hiding itself. `nil` = until told otherwise.
    var autoHideAfter: Duration? {
        switch self {
        case .listening, .thinking: nil
        case .success: .milliseconds(600)
        case .cancelled, .noSpeech, .copied, .error: .seconds(2)
        }
    }
}

@MainActor
protocol PillPresenter: AnyObject {
    func show(_ state: PillState)
    func hide()
}
