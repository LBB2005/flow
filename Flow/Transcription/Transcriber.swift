protocol Transcriber: Sendable {
    /// 16 kHz mono Float32 samples → raw transcript.
    func transcribe(_ samples: [Float]) async throws -> String
}
