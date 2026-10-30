import XCTest
import AVFoundation
@testable import Rayee

final class LiveTranscriberTests: XCTestCase {

    private let rayeeFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let analyzerFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!

    func testFloatAudioBecomesInt16AtTheSameRate() {
        let input = AVAudioPCMBuffer(pcmFormat: rayeeFormat, frameCapacity: 1_600)!
        input.frameLength = 1_600
        for i in 0..<1_600 { input.floatChannelData![0][i] = 0.5 }
        let converter = AVAudioConverter(from: rayeeFormat, to: analyzerFormat)!

        let output = LiveTranscriber.convertForAnalyzer(input, using: converter, to: analyzerFormat)

        XCTAssertEqual(output?.format.commonFormat, .pcmFormatInt16)
        XCTAssertEqual(output?.format.sampleRate, 16_000)
        XCTAssertEqual(output?.frameLength, 1_600)
        XCTAssertEqual(Int(output!.int16ChannelData![0][800]), 16_384, accuracy: 2)
    }

    func testUnsupportedOrMissingLanguageSkipsThePreview() {
        let en = Locale(identifier: "en-IN")
        XCTAssertTrue(LivePreviewGate.shouldRun(isAvailable: true, supportedLocale: en, installed: true))
        XCTAssertFalse(LivePreviewGate.shouldRun(isAvailable: false, supportedLocale: en, installed: true))
        XCTAssertFalse(LivePreviewGate.shouldRun(isAvailable: true, supportedLocale: nil, installed: true))
        XCTAssertFalse(LivePreviewGate.shouldRun(isAvailable: true, supportedLocale: en, installed: false))
    }

    func testStopBeforeStartIsSafe() {
        let expectation = XCTestExpectation(description: "no transcript")
        expectation.isInverted = true
        let transcriber = LiveTranscriber(languageIdentifier: "en-IN")
        transcriber.onTranscript = { _ in expectation.fulfill() }
        transcriber.stop()
        transcriber.append(AVAudioPCMBuffer(pcmFormat: rayeeFormat, frameCapacity: 160)!)
        transcriber.start()   // after stop: must do nothing and never call onTranscript
        wait(for: [expectation], timeout: 0.5)
    }

    func testStopTwiceIsSafe() {
        let expectation = XCTestExpectation(description: "no transcript")
        expectation.isInverted = true
        let transcriber = LiveTranscriber(languageIdentifier: "en-IN")
        transcriber.onTranscript = { _ in expectation.fulfill() }
        transcriber.start()
        transcriber.stop()
        transcriber.stop()
        wait(for: [expectation], timeout: 0.5)
    }

    func testLanguageOptionsAreNamedAndSorted() {
        let options = LivePreviewLanguages.sortedOptions(
            ["te-IN", "en-US", "en-IN"], displayLocale: Locale(identifier: "en-US"))
        XCTAssertEqual(options.map(\.id), ["en-IN", "en-US", "te-IN"])
        XCTAssertEqual(options.first?.name, "English (India)")
    }
}
