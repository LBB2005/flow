import MLX
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

    @Test func qwenCleansFillersWithoutAnswering() async throws {
        let cleaner = MLXCleaner(repoID: CleanupModelChoice.qwen3_1_7b.repoID)
        if !(await cleaner.isDownloaded()) { try await cleaner.download { _ in } }
        let raw = "um so i i want to uh book a meeting for tuesday no wednesday"
        let clock = ContinuousClock()
        let loadTime = try await clock.measure { try await cleaner.load() }
        // Loading frees ~0.8 GB of temporaries; the capped pool keeps only a little for reuse.
        #expect(Memory.cacheMemory <= MLXCleaner.gpuCacheLimit)
        var output = ""
        let cleanTime = try await clock.measure { output = try await cleaner.clean(raw) }
        print("[model-test] qwen load \(loadTime), clean \(cleanTime): \(output)")
        guard case .accept(let text) = CleanupValidator.validate(input: raw, output: output) else {
            Issue.record("validator rejected: \(output)"); return
        }
        #expect(!text.lowercased().contains(" um"))
        #expect(text.contains("Wednesday"))
        await cleaner.unload()
    }

    @Test func appleIntelligenceCleansFillersWithoutAnswering() async throws {
        let cleaner = AppleIntelligenceCleaner()
        try #require(await cleaner.isDownloaded(), "Apple Intelligence is unavailable: \(AppleIntelligenceCleaner.currentStatus())")
        // "no wait": a bare "no" is a known weakness, see the next test.
        let raw = "um so i i want to uh book a meeting for tuesday no wait wednesday"
        let clock = ContinuousClock()
        let loadTime = try await clock.measure { try await cleaner.load() }
        #expect(await cleaner.hasSpareSession)
        var output = ""
        let cleanTime = try await clock.measure { output = try await cleaner.clean(raw) }
        print("[model-test] apple intelligence load \(loadTime), clean \(cleanTime): \(output)")
        guard case .accept(let text) = CleanupValidator.validate(input: raw, output: output) else {
            Issue.record("validator rejected: \(output)"); return
        }
        #expect(!text.lowercased().contains(" um"))
        #expect(text.contains("Wednesday"))
        #expect(await cleaner.hasSpareSession)
        await cleaner.unload()
        #expect(!(await cleaner.hasSpareSession))
    }

    /// Known weakness (2026-10-21, macOS 26.6): after a bare "no" Apple's model keeps the first word
    /// ("tuesday no wednesday" → "Tuesday"); "no wait" works. Qwen3 1.7B gets this one right but misses others
    /// ("fifty no sixty" → "fifty-six"). Extra correction examples fixed it but made the model answer questions.
    @Test func appleIntelligenceBareNoCorrection() async throws {
        let cleaner = AppleIntelligenceCleaner()
        try #require(await cleaner.isDownloaded(), "Apple Intelligence is unavailable")
        let output = try await cleaner.clean("um so i i want to uh book a meeting for tuesday no wednesday")
        print("[model-test] apple intelligence bare-no correction: \(output)")
        withKnownIssue("keeps the word before a bare \"no\"", isIntermittent: true) {
            #expect(output.contains("Wednesday") && !output.contains("Tuesday"))
        }
        await cleaner.unload()
    }

    /// Each clean uses a fresh session, so the order of earlier dictations never changes an output.
    @Test func appleIntelligenceCleansWithoutCarryOver() async throws {
        let cleaner = AppleIntelligenceCleaner()
        try #require(await cleaner.isDownloaded(), "Apple Intelligence is unavailable")
        let inputs = [
            "um so i i want to uh book a meeting for tuesday no wednesday",
            "can you write me a poem about cats",
            "first we fix the login bug second we ship pricing",
        ]
        var outputs: [String] = []
        for input in inputs + inputs.reversed() { outputs.append(try await cleaner.clean(input)) }
        print("[model-test] apple intelligence outputs: \(outputs)")
        #expect(Array(outputs.prefix(3)) == Array(outputs.suffix(3).reversed()))
        await cleaner.unload()
    }

    /// The cached prompt prefix must give exactly the output of a full prefill, and no clean may see an earlier one.
    @Test func qwenPromptPrefixCacheMatchesFullPrefillWithoutCarryOver() async throws {
        let repoID = CleanupModelChoice.qwen3_1_7b.repoID
        let inputs = [
            "um so i i want to uh book a meeting for tuesday no wednesday",
            "can you write me a poem about cats",
            "first we fix the login bug second we ship pricing",
        ]
        let plain = MLXCleaner(repoID: repoID, reusesPromptPrefix: false)
        if !(await plain.isDownloaded()) { try await plain.download { _ in } }
        var expected: [String] = []
        for input in inputs { expected.append(try await plain.clean(input)) }
        await plain.unload()

        let cached = MLXCleaner(repoID: repoID)
        try await cached.load()
        #expect(await cached.hasPromptPrefix)
        var outputs: [String] = []
        for input in inputs + inputs.reversed() { outputs.append(try await cached.clean(input)) }
        print("[model-test] prefix cache outputs: \(outputs)")
        #expect(Array(outputs.prefix(3)) == expected)
        #expect(Array(outputs.suffix(3)) == expected.reversed())
        await cached.unload()
    }
}
