import XCTest
import AVFoundation
@testable import Rayee

final class AudioConversionTests: XCTestCase {

    private let micFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    private let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    /// A slowly rising ramp, split into 100ms microphone-sized buffers.
    private func rampBuffers(count: Int, framesPerBuffer: Int = 4_800) -> [AVAudioPCMBuffer] {
        (0..<count).map { bufferIndex in
            let buffer = AVAudioPCMBuffer(
                pcmFormat: micFormat, frameCapacity: AVAudioFrameCount(framesPerBuffer))!
            buffer.frameLength = AVAudioFrameCount(framesPerBuffer)
            let data = buffer.floatChannelData![0]
            for i in 0..<framesPerBuffer {
                data[i] = Float(bufferIndex * framesPerBuffer + i) / 240_000
            }
            return buffer
        }
    }

    private func convertAll(_ buffers: [AVAudioPCMBuffer]) -> [Float] {
        let converter = AVAudioConverter(from: micFormat, to: whisperFormat)!
        var samples: [Float] = []
        for buffer in buffers {
            guard let converted = AudioRecorder.convert(buffer, using: converter, to: whisperFormat) else {
                continue
            }
            samples.append(contentsOf: UnsafeBufferPointer(
                start: converted.floatChannelData![0], count: Int(converted.frameLength)))
        }
        return samples
    }

    func testOutputIsOneThirdOfInputLength() {
        let samples = convertAll(rampBuffers(count: 5))  // 24,000 frames at 48kHz
        // The resampler holds back ~15 ms (≈240 frames) until more audio arrives, so output runs slightly short.
        // Repeated input would overshoot by thousands of frames, so this still catches the F10 bug.
        XCTAssertEqual(Double(samples.count), 8_000, accuracy: 300)
    }

    func testAudioIsNeverRepeated() {
        // A rising ramp must keep rising. If the converter re-reads a buffer, it jumps back down.
        let samples = convertAll(rampBuffers(count: 5))
        let warmUp = 64  // skip the resampler's start-up ripple
        guard samples.count > warmUp + 1 else { return XCTFail("no output") }
        for i in (warmUp + 1)..<samples.count where samples[i] < samples[i - 1] - 0.005 {
            return XCTFail("audio jumped backwards at sample \(i): \(samples[i - 1]) → \(samples[i])")
        }
    }
}
