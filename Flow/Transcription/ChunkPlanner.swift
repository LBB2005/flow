/// Decides where to cut a recording that is still growing, so `IncrementalTranscription` can transcribe the pieces
/// while the user is still talking (spec §11 amendment 10). Pure: it sees only the audio, in the order it arrives,
/// so the same recording always gets the same cuts however fast transcription runs.
///
/// Cuts go in the middle of a pause, never inside a word: Whisper then gets whole phrases with a little silence
/// on both sides, like a short dictation of its own. A piece is never longer than one 30 s Whisper window.
struct ChunkPlanner: Sendable {
    struct Config: Sendable, Equatable {
        /// Speech before a pause must be at least this long to be cut off. Longer pieces give Whisper more context.
        var minChunk: Double = 6
        /// Quiet this long counts as a pause between phrases.
        var pause: Double = 0.5
        /// Past this length, a shorter pause will do…
        var shortPauseAfter: Double = 20
        var shortPause: Double = 0.25
        /// …and past this one, the piece is cut at its quietest moment so it still fits one Whisper window.
        var maxChunk: Double = 27
    }

    static let sampleRate = 16_000
    /// 50 ms of audio per loudness measurement.
    static let frameLength = 800

    let config: Config
    /// Sample index where the last cut was made (0 before any).
    private(set) var lastCut = 0
    /// RMS of each complete frame since `lastCut`'s frame.
    private var levels: [Float] = []
    private var firstFrame = 0
    private var partial: [Float] = []
    /// Consecutive quiet frames ending at the latest frame.
    private var quietRun = 0

    init(config: Config = Config()) {
        self.config = config
    }

    /// Feeds newly recorded samples; returns the sample indices of any new cuts, in order.
    mutating func append(_ samples: [Float]) -> [Int] {
        partial.append(contentsOf: samples)
        var cuts: [Int] = []
        var offset = 0
        while partial.count - offset >= Self.frameLength {
            let frame = partial[offset..<offset + Self.frameLength]
            offset += Self.frameLength
            if let cut = add(level: SilenceDetector.rms(frame)) { cuts.append(cut) }
        }
        partial.removeFirst(offset)
        return cuts
    }

    private func frames(_ seconds: Double) -> Int {
        Int((seconds * Double(Self.sampleRate) / Double(Self.frameLength)).rounded())
    }

    /// Index (absolute, in frames) of the newest frame.
    private var latestFrame: Int { firstFrame + levels.count - 1 }
    private var cutFrame: Int { lastCut / Self.frameLength }

    private mutating func add(level: Float) -> Int? {
        levels.append(level)
        quietRun = level < SilenceDetector.rmsThreshold ? quietRun + 1 : 0
        let length = latestFrame + 1 - cutFrame
        let runStart = latestFrame + 1 - quietRun
        let speech = runStart - cutFrame

        // A pause is long enough: cut inside it if there is enough speech before it (once: after the cut, the
        // pause starts before `lastCut`, so `speech` is no longer positive).
        let pause = length >= frames(config.shortPauseAfter) ? frames(config.shortPause) : frames(config.pause)
        if quietRun >= pause, speech >= frames(config.minChunk) {
            return cut(atFrame: runStart + pause / 2)
        }
        if length >= frames(config.maxChunk) {
            return cut(atFrame: quietestFrame(after: cutFrame + frames(config.maxChunk / 2)))
        }
        return nil
    }

    private func quietestFrame(after start: Int) -> Int {
        let local = (start - firstFrame)..<levels.count
        let best = local.min { levels[$0] < levels[$1] } ?? levels.count - 1
        return firstFrame + best
    }

    private mutating func cut(atFrame frame: Int) -> Int {
        lastCut = frame * Self.frameLength
        // Keep only the frames after the cut.
        levels.removeFirst(min(levels.count, frame - firstFrame))
        firstFrame = frame
        quietRun = min(quietRun, levels.count)
        return lastCut
    }
}
