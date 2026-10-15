import XCTest
@testable import Rayee

final class SpeechGateTests: XCTestCase {

    func testKeepsShortPreRollBeforeSpeech() {
        var gate = SpeechGate(fixedThreshold: 0.01, adaptive: false, preRollSampleLimit: 3)
        XCTAssertFalse(gate.feed([0.1, 0.2], rms: 0.001))
        XCTAssertFalse(gate.feed([0.3, 0.4], rms: 0.001))
        XCTAssertTrue(gate.feed([0.9], rms: 0.5))
        XCTAssertEqual(gate.kept, [0.2, 0.3, 0.4, 0.9])
    }

    func testKeepsNothingWhenNoSpeech() {
        var gate = SpeechGate(fixedThreshold: 0.01, adaptive: false, preRollSampleLimit: 3)
        _ = gate.feed([0.1, 0.2, 0.3, 0.4], rms: 0.001)
        XCTAssertFalse(gate.speechDetected)
        XCTAssertTrue(gate.kept.isEmpty)
    }

    func testKeepsQuietGapsOnceSpeechHasStarted() {
        var gate = SpeechGate(fixedThreshold: 0.01, adaptive: false, preRollSampleLimit: 0)
        XCTAssertTrue(gate.feed([0.9], rms: 0.5))
        XCTAssertFalse(gate.feed([0.0], rms: 0.001))
        XCTAssertEqual(gate.kept, [0.9, 0.0])
    }

    func testQuietRoomUsesTheMinimumThreshold() {
        XCTAssertEqual(SpeechGate.adaptedThreshold(from: [0.001, 0.001]), Config.minSilenceThreshold)
    }

    func testThresholdIsCappedWhenUserTalksDuringCalibration() {
        XCTAssertEqual(SpeechGate.adaptedThreshold(from: [0.2, 0.25]), Config.maxAdaptiveSilenceThreshold)
    }

    func testSpeakingImmediatelyKeepsTheFirstWord() {
        // Review focus: the user talks the instant the hotkey is pressed, with adaptive mode on.
        var gate = SpeechGate(fixedThreshold: 0.01, adaptive: true, preRollSampleLimit: 4_800)
        XCTAssertFalse(gate.feed([0.5, 0.5], rms: 0.2))  // calibration chunk 1 (already speech)
        XCTAssertFalse(gate.feed([0.6, 0.6], rms: 0.2))  // calibration chunk 2
        XCTAssertTrue(gate.feed([0.7], rms: 0.2))        // still recognised as speech
        XCTAssertEqual(gate.kept, [0.5, 0.5, 0.6, 0.6, 0.7])
    }
}
