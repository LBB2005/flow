import Testing
@testable import Flow

@MainActor
struct IncrementalTranscriptionTests {
    /// 7 s of speech, a 1 s pause (cut at 7.25 s), then 3 s of speech and a short silence before release.
    static let twoPhrases = Signal.speech(7) + Signal.pause(1) + Signal.speech(3) + Signal.pause(0.3)

    private func feed(_ samples: [Float], to session: IncrementalTranscription) {
        for offset in stride(from: 0, to: samples.count, by: 320) {
            session.append(Array(samples[offset..<min(offset + 320, samples.count)]))
        }
    }

    @Test func transcribesFinishedPhrasesWhileRecordingAndOnlyTheTailOnRelease() async throws {
        let transcriber = ScriptedTranscriber()
        let session = IncrementalTranscription(transcriber: transcriber)
        feed(Self.twoPhrases, to: session)
        await session.waitForQueuedPieces()
        #expect(transcriber.calls.count == 1)
        #expect(session.chunkCount == 1)

        let text = try await session.finish(Self.twoPhrases)
        #expect(text == "p1 p2")
        #expect(transcriber.calls.count == 2)
    }

    @Test func eachPieceIsTrimmedToItsSpeech() async throws {
        let transcriber = ScriptedTranscriber()
        let session = IncrementalTranscription(transcriber: transcriber)
        feed(Self.twoPhrases, to: session)
        await session.waitForQueuedPieces()
        _ = try await session.finish(Self.twoPhrases)

        let calls = transcriber.calls
        // Piece 1: the 7 s of speech plus the 0.25 s of pause before the cut (inside the trailing margin).
        #expect(calls[0].sampleCount == Int(7.25 * 16_000))
        // Tail: the lead margin (on the 100 ms grid) + 3 s of speech + the 0.3 s of silence before release.
        #expect(abs(calls[1].sampleCount - Int(3.6 * 16_000)) <= 1_600)
    }

    /// Three phrases: two pieces while recording, then the tail.
    static let threePhrases = Signal.speech(7) + Signal.pause(1) + Signal.speech(7) + Signal.pause(1) + Signal.speech(2)

    @Test func backgroundPiecesGetTheTextSoFarAsContextButTheTailDoesNot() async throws {
        // Context costs a decoder step per token: free in the background, but not after release.
        let transcriber = ScriptedTranscriber()
        let session = IncrementalTranscription(transcriber: transcriber)
        feed(Self.threePhrases, to: session)
        await session.waitForQueuedPieces()
        #expect(try await session.finish(Self.threePhrases) == "p1 p2 p3")
        #expect(transcriber.calls.map(\.context) == [nil, "p1", nil])
    }

    @Test func noContextWhenTurnedOff() async throws {
        let transcriber = ScriptedTranscriber()
        let session = IncrementalTranscription(transcriber: transcriber, usesContext: false)
        feed(Self.threePhrases, to: session)
        await session.waitForQueuedPieces()
        _ = try await session.finish(Self.threePhrases)
        #expect(transcriber.calls.map(\.context) == [nil, nil, nil])
    }

    @Test func silentTailIsNotTranscribed() async throws {
        let transcriber = ScriptedTranscriber()
        let session = IncrementalTranscription(transcriber: transcriber)
        let samples = Signal.speech(7) + Signal.pause(2)
        feed(samples, to: session)
        await session.waitForQueuedPieces()
        #expect(try await session.finish(samples) == "p1")
        #expect(transcriber.calls.count == 1)
    }

    @Test func aClickAfterTheLastPieceIsNotTranscribed() async throws {
        // 50 ms of noise at the end, like the hotkey's click on release.
        let transcriber = ScriptedTranscriber()
        let session = IncrementalTranscription(transcriber: transcriber)
        let samples = Signal.speech(7) + Signal.pause(1.5) + Signal.speech(0.05) + Signal.pause(0.2)
        feed(samples, to: session)
        await session.waitForQueuedPieces()
        #expect(try await session.finish(samples) == "p1")
        #expect(transcriber.calls.count == 1)
    }

    @Test func shortDictationIsOneWholeClipOnRelease() async throws {
        let transcriber = ScriptedTranscriber()
        let session = IncrementalTranscription(transcriber: transcriber)
        let samples = Signal.pause(0.2) + Signal.speech(3) + Signal.pause(0.4)
        feed(samples, to: session)
        #expect(try await session.finish(samples) == "p1")
        #expect(transcriber.calls == [.init(sampleCount: samples.count, context: nil)])
    }

    @Test func piecesWaitingOnReleaseMergeIntoTheTail() async throws {
        // Piece 1 is being transcribed and piece 2 is waiting when the key is released: piece 2 and the tail
        // go to Whisper together, so the user waits for two runs, not three.
        let gate = Gate()
        let transcriber = ScriptedTranscriber(gate: gate)
        let session = IncrementalTranscription(transcriber: transcriber)
        feed(Self.threePhrases, to: session)
        #expect(await eventually { await gate.waiterCount == 1 })

        let finishing = Task { try await session.finish(Self.threePhrases) }
        #expect(await eventually { session.isFinishing })
        await gate.open()
        #expect(await eventually { await gate.waiterCount == 1 })
        await gate.open()
        #expect(try await finishing.value == "p1 p2")
        #expect(transcriber.calls.count == 2)
        #expect(transcriber.cancelled == 0)
    }

    @Test func releasingDuringTheFinalPieceNeedsNoTail() async throws {
        // The user stopped talking, the pause was cut and its piece started, then they let go: only silence is
        // left after that piece, so its result ends the transcript and Whisper doesn't run again.
        let gate = Gate()
        let transcriber = ScriptedTranscriber(gate: gate)
        let session = IncrementalTranscription(transcriber: transcriber)
        let samples = Signal.speech(7) + Signal.pause(0.7)
        feed(samples, to: session)
        #expect(await eventually { await gate.waiterCount == 1 })

        let finishing = Task { try await session.finish(samples) }
        #expect(await eventually { session.isFinishing })
        await gate.open()
        #expect(try await finishing.value == "p1")
        #expect(transcriber.calls.count == 1)
    }

    @Test func aFailedPieceMakesFinishThrow() async {
        let session = IncrementalTranscription(transcriber: ScriptedTranscriber(failOnCall: 1))
        feed(Self.twoPhrases, to: session)
        await session.waitForQueuedPieces()
        await #expect(throws: FakeError.self) { try await session.finish(Self.twoPhrases) }
    }

    @Test func cancelStopsThePieceInProgress() async {
        let gate = Gate()
        let transcriber = ScriptedTranscriber(gate: gate)
        let session = IncrementalTranscription(transcriber: transcriber)
        feed(Self.twoPhrases, to: session)
        #expect(await eventually { await gate.waiterCount == 1 })
        session.cancel()
        await gate.open()
        await session.waitForQueuedPieces()
        #expect(transcriber.cancelled == 1)
        await #expect(throws: CancellationError.self) { try await session.finish(Self.twoPhrases) }
    }

    @Test func stitchJoinsWithSingleSpacesAndSkipsEmptyPieces() {
        #expect(IncrementalTranscription.stitch([" Hello there. ", "", "How are you?"]) == "Hello there. How are you?")
    }
}
