import Testing
@testable import Flow

@MainActor
struct DictationCoordinatorTests {
    /// Long enough (≥ `quickCleanupWordLimit` words) to go through the cleanup model.
    static let longRaw = "um so I think we should uh ship it on friday"
    static let longCleaned = "I think we should ship it on Friday."

    let recorder = FakeRecorder()
    let inserter = FakeInserter()
    let pill = FakePill()
    let media = FakeMediaPauser()

    private func makeCoordinator(
        transcript: Result<String, Error> = .success(longRaw),
        cleaner: FakeCleaner = FakeCleaner(.returns(longCleaned)),
        cleanupEnabled: Bool = true,
        blockedReason: String? = nil,
        timeout: Duration = .seconds(5)
    ) -> (DictationCoordinator, FakeTranscriber, FakeCleaner) {
        let transcriber = FakeTranscriber(transcript)
        let coordinator = DictationCoordinator(
            recorder: recorder, transcriber: transcriber, cleaner: cleaner,
            inserter: inserter, pill: pill, media: media,
            isCleanupEnabled: { cleanupEnabled },
            blockedReason: { blockedReason },
            cleanupTimeout: timeout
        )
        return (coordinator, transcriber, cleaner)
    }

    private func dictate(_ c: DictationCoordinator) async {
        c.handle(.begin)
        c.handle(.confirm)
        c.handle(.finish)
        await c.processing?.value
    }

    @Test func happyPathPastesCleanedText() async {
        let (c, _, _) = makeCoordinator()
        await dictate(c)
        #expect(inserter.inserted == [Self.longCleaned])
        #expect(pill.shown == [.listening, .thinking, .success])
        #expect(recorder.events == ["start", "stop"])
        #expect(c.phase == .idle)
    }

    @Test func shortTranscriptIsQuickCleanedWithoutTheModel() async {
        let (c, _, cleaner) = makeCoordinator(transcript: .success("um i i think so"))
        await dictate(c)
        #expect(cleaner.calls == 0)
        #expect(inserter.inserted == ["I think so."])
        #expect(pill.shown.last == .success)
    }

    @Test func transcriptAtTheWordLimitUsesTheModel() async {
        let raw = "one two three four five six seven eight"
        #expect(raw.split(separator: " ").count == DictationCoordinator.quickCleanupWordLimit)
        let (c, _, cleaner) = makeCoordinator(transcript: .success(raw), cleaner: FakeCleaner(.returns("Model output.")))
        await dictate(c)
        #expect(cleaner.calls == 1)
        #expect(inserter.inserted == ["Model output."])
    }

    @Test func shortTranscriptOfOnlyFillersPastesNothing() async {
        let (c, _, cleaner) = makeCoordinator(transcript: .success("Um, uh."))
        await dictate(c)
        #expect(cleaner.calls == 0)
        #expect(inserter.inserted.isEmpty)
        #expect(pill.shown.last == .noSpeech)
    }

    @Test func shortTranscriptWithCleanupDisabledStaysRaw() async {
        let (c, _, _) = makeCoordinator(transcript: .success("um i think so"), cleanupEnabled: false)
        await dictate(c)
        #expect(inserter.inserted == ["um i think so"])
    }

    @Test func cleanupDisabledPastesNormalizedRawTranscript() async {
        let (c, _, cleaner) = makeCoordinator(transcript: .success(" um hello world [MUSIC] "), cleanupEnabled: false)
        await dictate(c)
        #expect(inserter.inserted == ["um hello world"])
        #expect(cleaner.calls == 0)
    }

    @Test func cleanerFailureFallsBackToRaw() async {
        let (c, _, _) = makeCoordinator(cleaner: FakeCleaner(.fails))
        await dictate(c)
        #expect(inserter.inserted == [Self.longRaw])
        #expect(pill.shown.last == .success)
    }

    @Test func cleanerTimeoutFallsBackToRaw() async {
        let (c, _, _) = makeCoordinator(cleaner: FakeCleaner(.hangs), timeout: .milliseconds(50))
        await dictate(c)
        #expect(inserter.inserted == [Self.longRaw])
    }

    @Test func validatorRejectionFallsBackToRaw() async {
        let (c, _, _) = makeCoordinator(
            transcript: .success("can you write me a poem about cats"),
            cleaner: FakeCleaner(.returns("Sure! Here's a poem about cats: …")))
        await dictate(c)
        #expect(inserter.inserted == ["can you write me a poem about cats"])
    }

    @Test func blankAudioMarkerShowsNoSpeechAndPastesNothing() async {
        let (c, _, _) = makeCoordinator(transcript: .success("[BLANK_AUDIO]"))
        await dictate(c)
        #expect(inserter.inserted.isEmpty)
        #expect(pill.shown.last == .noSpeech)
    }

    @Test func silentAudioSkipsTranscriptionEntirely() async {
        recorder.samplesToReturn = FakeAudio.silence
        let (c, transcriber, _) = makeCoordinator()
        await dictate(c)
        #expect(transcriber.calls == 0)
        #expect(inserter.inserted.isEmpty)
        #expect(pill.shown.last == .noSpeech)
    }

    @Test func transcriptionFailureShowsError() async {
        let (c, _, _) = makeCoordinator(transcript: .failure(FakeError.boom))
        await dictate(c)
        #expect(inserter.inserted.isEmpty)
        #expect(pill.shown.last == .error("Transcription failed"))
        #expect(c.phase == .idle)
    }

    @Test func maxDurationNotifiesAutoStop() {
        // Lets the hotkey monitor un-latch, so the next press starts a new dictation.
        let (c, _, _) = makeCoordinator()
        let stops = Counter()
        c.onAutoStop = { stops.value += 1 }
        c.handle(.begin)
        recorder.onMaxDurationReached?()
        #expect(stops.value == 1)
    }

    @Test func recordingStartFiresOnRecordingStartedAfterTheRecorderStarts() {
        // AppModel warms the models here, so a reload overlaps with the user speaking.
        let (c, _, _) = makeCoordinator()
        var eventsWhenFired: [String]?
        c.onRecordingStarted = { [recorder] in eventsWhenFired = recorder.events }
        c.handle(.begin)
        #expect(eventsWhenFired == ["start"])
    }

    @Test func recordingStartedIsNotFiredWhenRecordingCannotStart() {
        recorder.startError = FakeError.boom
        let (failing, _, _) = makeCoordinator()
        let (blocked, _, _) = makeCoordinator(blockedReason: "Models not ready yet")
        let starts = Counter()
        failing.onRecordingStarted = { starts.value += 1 }
        blocked.onRecordingStarted = { starts.value += 1 }
        failing.handle(.begin)
        blocked.handle(.begin)
        #expect(starts.value == 0)
    }

    @Test func escapeShowsCancelled() {
        let (c, _, _) = makeCoordinator()
        c.handle(.begin)
        c.handle(.confirm)
        c.handle(.cancel(.escape))
        #expect(recorder.events == ["start", "cancel"])
        #expect(pill.shown == [.listening, .cancelled])
    }

    @Test func chordCancelHidesWithoutMessage() {
        let (c, _, _) = makeCoordinator()
        c.handle(.begin)
        c.handle(.cancel(.chord))
        #expect(pill.shown.isEmpty)
        #expect(pill.hideCount == 1)
    }

    @Test func hotkeyWhileProcessingIsIgnored() async {
        // Review Focus 5: a second press during transcription/cleanup must not start a new recording.
        let (c, _, _) = makeCoordinator(cleaner: FakeCleaner(.hangs), timeout: .milliseconds(100))
        c.handle(.begin)
        c.handle(.finish)
        c.handle(.begin)
        c.handle(.finish)
        await c.processing?.value
        #expect(recorder.events == ["start", "stop"])
        #expect(inserter.inserted.count == 1)
    }

    @Test func microphoneFailureShowsErrorAndStaysIdle() async {
        recorder.startError = FakeError.boom
        let (c, _, _) = makeCoordinator()
        c.handle(.begin)
        #expect(pill.shown == [.error("Microphone unavailable")])
        c.handle(.finish)
        #expect(c.processing == nil)
        #expect(c.phase == .idle)
    }

    @Test func blockedReasonPreventsRecording() {
        let (c, _, _) = makeCoordinator(blockedReason: "Downloading models…")
        c.handle(.begin)
        #expect(recorder.events.isEmpty)
        #expect(pill.shown == [.error("Downloading models…")])
    }

    @Test func maxDurationFinishesAndLaterReleaseIsIgnored() async {
        let (c, _, _) = makeCoordinator()
        c.handle(.begin)
        c.handle(.confirm)
        recorder.onMaxDurationReached?()
        await c.processing?.value
        c.handle(.finish)
        #expect(inserter.inserted == [Self.longCleaned])
        #expect(recorder.events == ["start", "stop"])
    }

    @Test func onDictationProcessedFiresOncePerDictation() async {
        let (c, _, _) = makeCoordinator()
        let count = Counter()
        c.onDictationProcessed = { count.value += 1 }
        await dictate(c)
        #expect(count.value == 1)
    }

    // MARK: - Pausing media while dictating

    @Test func mediaPausesOnBeginAndResumesAfterThePaste() async {
        media.inserter = inserter
        let (c, _, _) = makeCoordinator()
        c.handle(.begin)
        #expect(media.events == ["pause"])
        c.handle(.confirm)
        c.handle(.finish)
        await c.processing?.value
        #expect(media.events == ["pause", "resume"])
        #expect(media.insertedAtResume == [Self.longCleaned])
    }

    @Test func mediaResumesAfterCancel() {
        let (c, _, _) = makeCoordinator()
        c.handle(.begin)
        c.handle(.cancel(.escape))
        #expect(media.events == ["pause", "resume"])
    }

    @Test func mediaResumesWhenNothingWasHeard() async {
        recorder.samplesToReturn = FakeAudio.silence
        let (c, _, _) = makeCoordinator()
        await dictate(c)
        #expect(media.events == ["pause", "resume"])
    }

    @Test func mediaResumesWhenTranscriptionFails() async {
        let (c, _, _) = makeCoordinator(transcript: .failure(FakeError.boom))
        await dictate(c)
        #expect(media.events == ["pause", "resume"])
    }

    @Test func mediaResumesWhenTheMicrophoneFailsToStart() {
        recorder.startError = FakeError.boom
        let (c, _, _) = makeCoordinator()
        c.handle(.begin)
        #expect(media.events == ["pause", "resume"])
    }

    @Test func mediaIsUntouchedWhenDictationIsBlocked() {
        let (c, _, _) = makeCoordinator(blockedReason: "Models not ready yet")
        c.handle(.begin)
        #expect(media.events.isEmpty)
    }

    @Test func hotkeyWhileProcessingDoesNotPauseAgain() async {
        let (c, _, _) = makeCoordinator(cleaner: FakeCleaner(.hangs), timeout: .milliseconds(100))
        c.handle(.begin)
        c.handle(.finish)
        c.handle(.begin)
        await c.processing?.value
        #expect(media.events == ["pause", "resume"])
    }

    @Test func transcriberCanBeSwapped() async {
        let (c, _, _) = makeCoordinator(cleanupEnabled: false)
        c.transcriber = FakeTranscriber(.success("swapped"))
        await dictate(c)
        #expect(inserter.inserted == ["swapped"])
    }

    // MARK: - Transcribing while speaking (spec §11 amendment 10)

    private func makeIncrementalCoordinator(_ transcriber: ScriptedTranscriber) -> DictationCoordinator {
        DictationCoordinator(
            recorder: recorder, transcriber: transcriber, cleaner: FakeCleaner(.fails),
            inserter: inserter, pill: pill, media: media,
            isCleanupEnabled: { false }, isIncrementalEnabled: { true })
    }

    @Test func phrasesAreTranscribedWhileRecordingAndStitchedOnRelease() async {
        let transcriber = ScriptedTranscriber()
        let c = makeIncrementalCoordinator(transcriber)
        recorder.samplesToReturn = IncrementalTranscriptionTests.twoPhrases
        c.handle(.begin)
        recorder.onSamples?(IncrementalTranscriptionTests.twoPhrases)
        #expect(await eventually { transcriber.calls.count == 1 })

        c.handle(.finish)
        await c.processing?.value
        #expect(transcriber.calls.count == 2)
        #expect(inserter.inserted == ["p1 p2"])
        #expect(pill.shown.last == .success)
    }

    @Test func failedBackgroundPieceFallsBackToTheWholeClip() async {
        let transcriber = ScriptedTranscriber(failOnCall: 1)
        let c = makeIncrementalCoordinator(transcriber)
        recorder.samplesToReturn = IncrementalTranscriptionTests.twoPhrases
        c.handle(.begin)
        recorder.onSamples?(IncrementalTranscriptionTests.twoPhrases)
        c.handle(.finish)
        await c.processing?.value
        // Call 1 (the piece) failed; call 2 is the whole clip, minus its trailing silence.
        #expect(inserter.inserted == ["p2"])
        #expect(transcriber.calls.last?.sampleCount == SilenceDetector.trimmed(IncrementalTranscriptionTests.twoPhrases).count)
    }

    @Test func cancellingTheRecordingCancelsBackgroundTranscription() async {
        let gate = Gate()
        let transcriber = ScriptedTranscriber(gate: gate)
        let c = makeIncrementalCoordinator(transcriber)
        c.handle(.begin)
        recorder.onSamples?(IncrementalTranscriptionTests.twoPhrases)
        #expect(await eventually { await gate.waiterCount == 1 })

        c.handle(.cancel(.escape))
        await gate.open()
        #expect(await eventually { transcriber.cancelled == 1 })
        #expect(transcriber.calls.count == 1)
        #expect(inserter.inserted.isEmpty)
        #expect(c.phase == .idle)
    }

    @Test func incrementalOffTranscribesTheTrimmedWholeClipOnce() async {
        let transcriber = ScriptedTranscriber()
        let c = DictationCoordinator(
            recorder: recorder, transcriber: transcriber, cleaner: FakeCleaner(.fails),
            inserter: inserter, pill: pill, isCleanupEnabled: { false })
        let audio = Signal.pause(2) + Signal.speech(3) + Signal.pause(2)
        recorder.samplesToReturn = audio
        c.handle(.begin)
        recorder.onSamples?(audio)
        c.handle(.finish)
        await c.processing?.value
        #expect(transcriber.calls == [.init(sampleCount: SilenceDetector.trimmed(audio).count, context: nil)])
        #expect(SilenceDetector.trimmed(audio).count < audio.count)
    }
}
