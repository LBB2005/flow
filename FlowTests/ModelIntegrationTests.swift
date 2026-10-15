import Testing
@testable import Flow

@Suite(.enabled(if: ModelTests.enabled), .serialized)
struct ModelIntegrationTests {
    @Test func whisperTranscribesSynthesizedSpeech() async throws {
        let whisper = WhisperKitTranscriber(variant: WhisperModelChoice.largeV3Turbo.variant)
        if !(await whisper.isDownloaded()) { try await whisper.download { _ in } }
        let samples = try TestAudio.speech("The quick brown fox jumps over the lazy dog.")
        let clock = ContinuousClock()
        let loadTime = try await clock.measure { try await whisper.load() }
        var transcript = ""
        let transcribeTime = try await clock.measure { transcript = try await whisper.transcribe(samples) }
        print("[model-test] whisper load \(loadTime), transcribe \(transcribeTime): \(transcript)")
        let text = transcript.lowercased()
        #expect(text.contains("quick brown fox"))
        await whisper.unload()
    }
}
