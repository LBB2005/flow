/// Pauses whatever is playing while the user dictates.
@MainActor
protocol MediaPauser: AnyObject {
    /// Pauses media that is playing right now and remembers it. Already-paused media is left alone.
    func pause()
    /// Resumes only what `pause()` paused, unless the user already resumed it.
    func resume()
}

/// Leaves media alone.
final class NoMediaPauser: MediaPauser {
    func pause() {}
    func resume() {}
}
