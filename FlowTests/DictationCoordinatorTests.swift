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
            inserter: inserter, pill: pill,
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

    @Test func copiedOnlyShowsCopiedPill() async {
        inserter.result = .copiedOnly
        let (c, _, _) = makeCoordinator()
        await dictate(c)
        #expect(pill.shown.last == .copied)
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

    @Test func transcriberCanBeSwapped() async {
        let (c, _, _) = makeCoordinator(cleanupEnabled: false)
        c.transcriber = FakeTranscriber(.success("swapped"))
        await dictate(c)
        #expect(inserter.inserted == ["swapped"])
    }
}
