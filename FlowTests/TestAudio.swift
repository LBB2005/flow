import AVFoundation
import Foundation
@testable import Flow

enum TestAudio {
    /// Synthesizes `text` with macOS `say` and returns 16 kHz mono samples.
    /// `say` embedded commands work in `text`, e.g. `[[slnc 700]]` for a 0.7 s pause.
    static func speech(_ text: String, voice: String? = nil, rate: Int? = nil) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appending(path: "flow-test-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        var arguments = ["-o", url.path]
        if let voice { arguments += ["-v", voice] }
        if let rate { arguments += ["-r", String(rate)] }
        say.arguments = arguments + [text]
        try say.run()
        say.waitUntilExit()

        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return TapConverter(inputFormat: file.processingFormat)!.convert(buffer)
    }

    /// Makes synthesized speech look like a laptop mic: quieter, with room noise (≈ -55 dBFS) everywhere,
    /// and `lead`/`tail` seconds of that noise before and after (the hotkey is pressed before speaking).
    static func micLike(_ samples: [Float], gain: Float = 0.6, lead: Double = 0.4, tail: Double = 0.5) -> [Float] {
        var generator = SeededGenerator(seed: UInt64(samples.count))
        let noise = { Float.random(in: -0.003...0.003, using: &generator) }
        let pad = { (seconds: Double) in (0..<Int(seconds * 16_000)).map { _ in noise() } }
        return pad(lead) + samples.map { $0 * gain + noise() } + pad(tail)
    }
}

/// Deterministic noise, so benchmark runs are comparable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum ModelTests {
    /// Real-model tests only run via `make test-models`.
    static var enabled: Bool { ProcessInfo.processInfo.environment["FLOW_MODEL_TESTS"] == "1" }
}

/// `xcodebuild -quiet` drops test stdout, so model-test reports also go to `$TMPDIR/flow-model-tests.log`.
enum TestReport {
    static let url = FileManager.default.temporaryDirectory.appending(path: "flow-model-tests.log")

    static func log(_ line: String) {
        print(line)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
