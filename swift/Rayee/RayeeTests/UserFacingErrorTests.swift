import XCTest
@testable import Rayee

final class UserFacingErrorTests: XCTestCase {

    func testMicrophonePermissionMessageExplainsWhereToFixIt() {
        let message = UserFacingError.message(for: AudioRecorderError.noMicrophonePermission)
        XCTAssertTrue(message.contains("System Settings"))
        XCTAssertTrue(message.contains("Microphone"))
    }

    func testMicrophoneStartFailureMessage() {
        let message = UserFacingError.message(for: AudioRecorderError.engineStartFailed("-10868"))
        XCTAssertTrue(message.contains("microphone"))
    }

    func testModelStillLoadingMessage() {
        let message = UserFacingError.message(for: WhisperKitError.modelNotLoaded)
        XCTAssertTrue(message.contains("still loading"))
    }

    func testUnknownErrorFallsBackToItsDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Boom"])
        XCTAssertEqual(UserFacingError.message(for: error), "Transcription failed: Boom")
    }

    func testMicrophonePermissionOffersToOpenSettings() {
        XCTAssertEqual(UserFacingError.action(for: AudioRecorderError.noMicrophonePermission), .openMicrophoneSettings)
    }

    func testOtherErrorsHaveNoButton() {
        XCTAssertNil(UserFacingError.action(for: AudioRecorderError.engineStartFailed("-10868")))
        XCTAssertNil(UserFacingError.action(for: WhisperKitError.modelNotLoaded))
    }
}
