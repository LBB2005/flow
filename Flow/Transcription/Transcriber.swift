protocol Transcriber: Sendable {
    /// 16 kHz mono Float32 samples → raw transcript.
    func transcribe(_ samples: [Float]) async throws -> String
    /// A piece of a longer dictation (`IncrementalTranscription`); `context` is the transcript of the audio before it.
    func transcribe(_ samples: [Float], context: String?) async throws -> String
}

extension Transcriber {
    func transcribe(_ samples: [Float], context: String?) async throws -> String {
        try await transcribe(samples)
    }
}
