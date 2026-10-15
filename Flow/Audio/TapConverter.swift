import AVFoundation

/// Converts whatever the mic delivers into 16 kHz mono Float32.
/// Called on the audio thread, so it must not touch the main actor.
final class TapConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init?(inputFormat: AVAudioFormat, sampleRate: Double = 16_000) {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: output) else { return nil }
        self.converter = converter
        self.outputFormat = output
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }

        nonisolated(unsafe) let source = buffer
        let consumed = Flag()
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed.value {
                status.pointee = .noDataNow
                return nil
            }
            consumed.value = true
            status.pointee = .haveData
            return source
        }
        guard error == nil, let channel = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }

    private final class Flag: @unchecked Sendable { var value = false }
}
