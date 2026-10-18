import AVFoundation
import Testing
@testable import Flow

struct AudioPipelineTests {
    @Test func accumulatorCapsAndReportsFullOnce() {
        var acc = SampleAccumulator(maxSamples: 5)
        #expect(acc.append([1, 2, 3]) == false)
        #expect(acc.append([4, 5, 6]) == true)
        #expect(acc.samples == [1, 2, 3, 4, 5])
        #expect(acc.append([7]) == false)
        #expect(acc.samples.count == 5)
    }

    @Test func levelMapping() {
        #expect(AudioLevel.normalized([]) == 0)
        #expect(AudioLevel.normalized([Float](repeating: 0, count: 100)) == 0)
        #expect(AudioLevel.normalized([Float](repeating: 1, count: 100)) == 1)
        // -25 dBFS sits halfway between -50 and 0.
        let half = AudioLevel.normalized([Float](repeating: pow(10, -25 / 20), count: 100))
        #expect(abs(half - 0.5) < 0.01)
    }

    @Test func converterResamples48kStereoTo16kMono() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        for channel in 0..<2 {
            for frame in 0..<4_800 { buffer.floatChannelData![channel][frame] = sin(Float(frame) * 0.05) * 0.5 }
        }
        let converter = try #require(TapConverter(inputFormat: input))
        let samples = converter.convert(buffer)
        // AVAudioConverter holds back ~240 output frames (~15 ms) on the first chunk and
        // releases them on later calls, so a single call yields ≈1360, not exactly 1600.
        #expect(abs(samples.count - 1_600) <= 300)
        #expect(samples.contains { abs($0) > 0.1 })
    }

    @Test func deviceOverrideSkipsTheSystemDefault() {
        // Forcing the default device bypasses the engine's default route, which is the one
        // that copes with AirPods switching to their 24 kHz headset profile.
        #expect(AudioDevices.overrideUID(preferred: nil, systemDefault: "airpods") == nil)
        #expect(AudioDevices.overrideUID(preferred: "airpods", systemDefault: "airpods") == nil)
        #expect(AudioDevices.overrideUID(preferred: "builtin", systemDefault: "airpods") == "builtin")
        #expect(AudioDevices.overrideUID(preferred: "builtin", systemDefault: nil) == "builtin")
    }
}
