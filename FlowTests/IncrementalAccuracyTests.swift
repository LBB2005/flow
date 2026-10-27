import Foundation
import Testing
import WhisperKit
@testable import Flow

/// The accuracy gate for transcribing while the user speaks (spec §11 amendment 10): over realistic dictations with
/// pauses mid-sentence, incremental output must have no more word errors than Whisper on the whole clip.
/// Prints `[accuracy]` / `[latency]` lines to `TestReport`. `make test-models ONLY=IncrementalAccuracyTests`
@Suite(.enabled(if: ModelTests.enabled), .serialized)
@MainActor
struct IncrementalAccuracyTests {
    struct Variant {
        let name: String
        let config: ChunkPlanner.Config
        let usesContext: Bool
    }

    static let shipped = Variant(name: "incremental", config: ChunkPlanner.Config(), usesContext: true)
    static let variants: [Variant] = [
        shipped,
        Variant(name: "no-context", config: ChunkPlanner.Config(), usesContext: false),
        Variant(name: "min-3s", config: ChunkPlanner.Config(minChunk: 3), usesContext: true),
        Variant(name: "min-10s", config: ChunkPlanner.Config(minChunk: 10, pause: 0.6), usesContext: true),
    ]

    private static func audio(_ sample: DictationSamples.Sample) throws -> [Float] {
        TestAudio.micLike(try TestAudio.speech(sample.text, voice: sample.voice))
    }

    /// Feeds `audio` in 20 ms batches, as the recorder would, optionally at real-time pace.
    private static func feed(_ audio: [Float], to session: IncrementalTranscription, realTime: Bool) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        for (index, offset) in stride(from: 0, to: audio.count, by: 320).enumerated() {
            if realTime { try await clock.sleep(until: start + .milliseconds(20 * (index + 1))) }
            session.append(Array(audio[offset..<min(offset + 320, audio.count)]))
        }
    }

    /// Whisper on the whole clip as Flow did it before amendment 10: untrimmed, cut at exactly 30 s.
    private static func previousWholeClip() async throws -> (WhisperKit, DecodingOptions) {
        let folder = try #require(UserDefaults.standard.string(forKey: "whisperFolder.\(WhisperModelChoice.largeV3Turbo.variant)"))
        let pipe = try await WhisperKit(WhisperKitConfig(
            model: WhisperModelChoice.largeV3Turbo.variant, modelFolder: folder,
            verbose: false, logLevel: .error, prewarm: false, load: true, download: false))
        var options = WhisperKitTranscriber.decodingOptions(language: "en")
        options.chunkingStrategy = nil
        return (pipe, options)
    }

    @Test func incrementalIsAsAccurateAsWholeClip() async throws {
        let whisper = WhisperKitTranscriber(variant: WhisperModelChoice.largeV3Turbo.variant)
        try await whisper.load()
        let (previous, previousOptions) = try await Self.previousWholeClip()

        var errors: [String: Int] = [:]
        var punctuationErrors: [String: Int] = [:]
        var referenceWords = 0
        func record(_ name: String, _ sample: DictationSamples.Sample, _ text: String, whole: String, pieces: Int? = nil) {
            let reference = WordErrorRate.words(sample.spokenText)
            let wordErrors = WordErrorRate.distance(reference, WordErrorRate.words(text))
            let tokenDiff = WordErrorRate.distance(WordErrorRate.tokens(whole), WordErrorRate.tokens(text))
            errors[name, default: 0] += wordErrors
            punctuationErrors[name, default: 0] += tokenDiff
            let piecesNote = pieces.map { ", \($0) pieces before release" } ?? ""
            TestReport.log("[accuracy] \(sample.name) \(name): \(wordErrors) word errors / \(reference.count)\(piecesNote), \(tokenDiff) tokens differ from whole clip (case/punctuation included) → \(text)")
        }

        for sample in DictationSamples.accuracySet {
            let audio = try Self.audio(sample)
            referenceWords += WordErrorRate.words(sample.spokenText).count
            let old = TranscriptNormalizer.normalize(
                try await previous.transcribe(audioArray: audio, decodeOptions: previousOptions).map(\.text).joined(separator: " "))
            let whole = TranscriptNormalizer.normalize(try await whisper.transcribe(SilenceDetector.trimmed(audio)))
            TestReport.log("[accuracy] \(sample.name) (\(audio.count / 16_000) s) reference → \(sample.spokenText.replacing(#/\s+/#, with: " "))")
            record("previous-whole", sample, old, whole: whole)
            record("whole", sample, whole, whole: whole)
            for variant in Self.variants {
                let session = IncrementalTranscription(transcriber: whisper, config: variant.config, usesContext: variant.usesContext)
                try await Self.feed(audio, to: session, realTime: false)
                await session.waitForQueuedPieces()
                let pieces = session.chunkCount
                let text = TranscriptNormalizer.normalize(try await session.finish(audio))
                record(variant.name, sample, text, whole: whole, pieces: pieces)
            }
        }
        for name in ["previous-whole", "whole"] + Self.variants.map(\.name) {
            let wer = Double(errors[name] ?? 0) / Double(referenceWords) * 100
            TestReport.log("[accuracy] TOTAL \(name): WER \(String(format: "%.1f", wer))% (\(errors[name] ?? 0)/\(referenceWords)), \(punctuationErrors[name] ?? 0) tokens differ from whole clip")
        }
        await previous.unloadModels()
        await whisper.unload()

        // The gate: transcribing while speaking may not cost accuracy.
        #expect((errors[Self.shipped.name] ?? .max) <= (errors["whole"] ?? 0))
    }

    /// What the user waits for after releasing the key: fed at real-time pace, so pieces finish while "speaking".
    @Test func latencyAfterReleaseInRealTime() async throws {
        let whisper = WhisperKitTranscriber(variant: WhisperModelChoice.largeV3Turbo.variant)
        try await whisper.load()
        let clock = ContinuousClock()
        for sample in DictationSamples.byLength + DictationSamples.accuracySet.dropFirst(3) {
            let audio = try Self.audio(sample)
            let wholeStart = clock.now
            _ = try await whisper.transcribe(SilenceDetector.trimmed(audio))
            let whole = clock.now - wholeStart

            let session = IncrementalTranscription(transcriber: whisper, config: Self.shipped.config, usesContext: Self.shipped.usesContext)
            try await Self.feed(audio, to: session, realTime: true)
            let released = clock.now
            _ = try await session.finish(audio)
            let tail = clock.now - released
            TestReport.log("[latency] \(sample.name) (audio \(audio.count / 16) ms): whole clip \(Int(whole / .milliseconds(1))) ms, incremental after release \(Int(tail / .milliseconds(1))) ms (\(session.chunkCount) pieces before release)")
        }
        await whisper.unload()
    }
}
