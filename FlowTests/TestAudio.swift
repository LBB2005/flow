import AVFoundation
import Foundation
@testable import Flow

enum TestAudio {
    /// Synthesizes `text` with macOS `say` and returns 16 kHz mono samples.
    static func speech(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appending(path: "flow-test-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        say.arguments = ["-o", url.path, text]
        try say.run()
        say.waitUntilExit()

        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return TapConverter(inputFormat: file.processingFormat)!.convert(buffer)
    }
}

enum ModelTests {
    /// Real-model tests only run via `make test-models`.
    static var enabled: Bool { ProcessInfo.processInfo.environment["FLOW_MODEL_TESTS"] == "1" }
}
