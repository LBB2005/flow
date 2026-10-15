@MainActor
protocol Recorder: AnyObject {
    /// Starts capturing. Throws if the microphone can't be opened.
    func start() throws
    /// Stops and returns 16 kHz mono Float32 samples captured since `start()`.
    func stop() -> [Float]
    /// Stops and throws the audio away.
    func cancel()
    /// Called once if the recording hits the maximum length.
    var onMaxDurationReached: (@MainActor () -> Void)? { get set }
}
