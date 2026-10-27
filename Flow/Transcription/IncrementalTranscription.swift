import Foundation

/// Transcribes a dictation while it is still being recorded (spec §11 amendment 10). `ChunkPlanner` cuts the audio
/// at pauses; each finished piece is transcribed in the background, one at a time, so on release only the audio
/// after the last cut (usually a few seconds) is left. Pieces are joined in order with nothing dropped or repeated:
/// every sample belongs to exactly one piece.
///
/// Whisper's cost per run is mostly fixed (~0.57 s to encode one 30 s window on an M4 Pro, then ~8 ms per token), so
/// on release the work left is kept to as few runs as possible: pieces still waiting merge into the tail, and when
/// only silence follows the piece in progress (the user stopped talking, a pause was cut, then they let go) that
/// piece already is the end of the transcript. The tail gets no previous-text prompt, since each prompt token costs a
/// decoder step; background pieces do, as there it's free. A piece in progress is never abandoned: Core ML can't
/// interrupt the encoder, so restarting it would only add work.
///
/// Any failure makes `finish` throw, and the coordinator transcribes the whole clip instead.
@MainActor
final class IncrementalTranscription {
    private let transcriber: Transcriber
    private let usesContext: Bool
    private var planner: ChunkPlanner
    private var samples: [Float] = []
    /// Cut but not yet transcribed, oldest first.
    private var queued: [Range<Int>] = []
    /// Everything before this sample index has been transcribed into `texts`.
    private(set) var committedEnd = 0
    private var texts: [String] = []
    private var worker: Task<Void, Never>?
    private var failure: Error?

    /// How many pieces were transcribed before release (for the timing log).
    private(set) var chunkCount = 0

    /// `usesContext` passes the text so far to Whisper as the previous text for each background piece.
    init(transcriber: Transcriber, config: ChunkPlanner.Config = ChunkPlanner.Config(), usesContext: Bool = true) {
        self.transcriber = transcriber
        self.planner = ChunkPlanner(config: config)
        self.usesContext = usesContext
    }

    /// Feeds samples as the recorder delivers them.
    func append(_ newSamples: [Float]) {
        guard failure == nil else { return }
        samples.append(contentsOf: newSamples)
        var pieceStart = queued.last?.upperBound ?? committedEnd
        for cut in planner.append(newSamples) where cut > pieceStart && cut <= samples.count {
            queued.append(pieceStart..<cut)
            pieceStart = cut
        }
        if worker == nil, !queued.isEmpty { worker = Task { await self.drain() } }
    }

    /// Transcribes queued pieces one after another until none are left.
    private func drain() async {
        while failure == nil, !queued.isEmpty {
            let range = queued.removeFirst()
            do {
                texts.append(try await transcribe(Array(samples[range]), withContext: usesContext))
                committedEnd = range.upperBound
                chunkCount += 1
            } catch {
                failure = error
            }
        }
        worker = nil
    }

    /// Waits until every piece cut so far is transcribed (benchmarks feed audio faster than real time).
    func waitForQueuedPieces() async {
        while let worker { await worker.value }
    }

    /// A tail with less loud audio than this is the click of the hotkey or a breath, not a word: Whisper alone on it
    /// tends to invent one ("you"). Within the whole clip it was harmless.
    static let minimumTailSpeech = 0.2

    /// True once `finish` has started (for tests).
    private(set) var isFinishing = false

    /// The transcript of `allSamples` (the recorder's final buffer): waits for the piece in progress, then
    /// transcribes everything after the last finished piece in one go, unless that's only silence.
    func finish(_ allSamples: [Float]) async throws -> String {
        isFinishing = true
        // Pieces still waiting merge into the tail: one Whisper run instead of several.
        queued.removeAll()
        await worker?.value
        if let failure { throw failure }
        guard allSamples.count >= committedEnd, allSamples.count >= samples.count else {
            throw IncrementalTranscriptionError.audioMismatch
        }
        let tail = Array(allSamples[committedEnd...])
        if SilenceDetector.loudDuration(tail) >= Self.minimumTailSpeech {
            texts.append(try await transcribe(tail, withContext: false))
        }
        return Self.stitch(texts)
    }

    /// Stops background work; the session can't be used afterwards.
    func cancel() {
        failure = CancellationError()
        queued.removeAll()
        worker?.cancel()
    }

    private func transcribe(_ piece: [Float], withContext: Bool) async throws -> String {
        // Silent pieces (a long pause, a breath) are skipped: Whisper invents words on silence.
        guard let speech = SilenceDetector.speechRange(piece) else { return "" }
        let context = withContext ? Self.stitch(texts) : ""
        return try await transcriber.transcribe(Array(piece[speech]), context: context.isEmpty ? nil : context)
    }

    /// Joins pieces with single spaces.
    static func stitch(_ texts: [String]) -> String {
        texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum IncrementalTranscriptionError: Error {
    /// The recorder returned less audio than the session saw.
    case audioMismatch
}
