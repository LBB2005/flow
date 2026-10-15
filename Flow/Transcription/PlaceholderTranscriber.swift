/// Stand-in until Whisper is wired in (Task 18). Proves audio was captured.
struct PlaceholderTranscriber: Transcriber {
    func transcribe(_ samples: [Float]) async throws -> String {
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        return "Flow heard \(String(format: "%.1f", seconds)) seconds of audio."
    }
}
