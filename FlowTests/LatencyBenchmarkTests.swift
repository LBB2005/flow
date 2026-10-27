import Foundation
import Testing
@testable import Flow

/// Where dictation time goes on this Mac, with the real models. Prints `[bench]` lines; asserts nothing about speed.
/// `make test-models ONLY=LatencyBenchmarkTests`
@Suite(.enabled(if: ModelTests.enabled), .serialized)
struct LatencyBenchmarkTests {
    private static let clock = ContinuousClock()

    private static func ms(_ duration: Duration) -> Int { Int(duration / .milliseconds(1)) }

    private static func measure<T>(_ work: () async throws -> T) async rethrows -> (T, Int) {
        let start = clock.now
        let value = try await work()
        return (value, ms(clock.now - start))
    }

    private static func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }

    @Test func whisperAndCleanupLatency() async throws {
        let whisper = WhisperKitTranscriber(variant: WhisperModelChoice.largeV3Turbo.variant)
        if !(await whisper.isDownloaded()) { try await whisper.download { _ in } }
        let clips = try DictationSamples.byLength.map { sample in
            (sample, TestAudio.micLike(try TestAudio.speech(sample.text, voice: sample.voice)))
        }

        // `warm()` is what launch, wake and every recording start call: load, plus a warm-up run when cold.
        let (_, coldLoad) = try await Self.measure { try await whisper.warm() }
        let (_, firstTranscribe) = try await Self.measure { try await whisper.transcribe(clips[0].1) }
        await whisper.unload()
        let (_, reload) = try await Self.measure { try await whisper.warm() }
        let (_, firstAfterReload) = try await Self.measure { try await whisper.transcribe(clips[0].1) }
        TestReport.log("[bench] whisper cold load + warm-up \(coldLoad) ms, first transcribe (3s) \(firstTranscribe) ms")
        TestReport.log("[bench] whisper reload + warm-up after unload \(reload) ms, first transcribe after reload \(firstAfterReload) ms")

        var transcripts: [String] = []
        for (sample, samples) in clips {
            var times: [Int] = []
            var text = ""
            for _ in 0..<3 {
                let (result, time) = try await Self.measure { try await whisper.transcribe(SilenceDetector.trimmed(samples)) }
                times.append(time)
                text = result
            }
            transcripts.append(TranscriptNormalizer.normalize(text))
            TestReport.log("[bench] whisper \(sample.name) (audio \(samples.count / 16) ms): median \(Self.median(times)) ms \(times) → \(text)")
        }

        try await Task.sleep(for: .seconds(90))
        // A recording start warms Whisper while the user speaks (here: 3 s of "speaking").
        let warming = Task { try await whisper.warm() }
        try await Task.sleep(for: .seconds(3))
        try await warming.value
        let (_, afterIdle) = try await Self.measure { try await whisper.transcribe(clips[0].1) }
        TestReport.log("[bench] whisper 3s after 90 s idle, warmed at recording start: \(afterIdle) ms")

        let cleaner = AppleIntelligenceCleaner()
        try #require(await cleaner.isDownloaded(), "Apple Intelligence is unavailable")
        let (_, cleanerLoad) = try await Self.measure { try await cleaner.load() }
        TestReport.log("[bench] apple load (prewarm) \(cleanerLoad) ms")
        for (index, transcript) in transcripts.enumerated() {
            var times: [Int] = []
            for _ in 0..<3 {
                // As in the app: the spare session is re-prewarmed when recording starts, a few seconds before.
                try await cleaner.warm()
                try await Task.sleep(for: .seconds(2))
                let (_, time) = try await Self.measure { try await cleaner.clean(transcript) }
                times.append(time)
            }
            TestReport.log("[bench] apple clean \(DictationSamples.byLength[index].name) (\(transcript.split(separator: " ").count) words): median \(Self.median(times)) ms \(times)")
        }
        await cleaner.unload()
        await whisper.unload()
    }
}
