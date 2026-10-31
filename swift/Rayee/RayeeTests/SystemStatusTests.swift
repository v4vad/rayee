import XCTest
@testable import Rayee

final class SystemStatusTests: XCTestCase {
    private let allGood = SystemStatusInput(
        microphoneAllowed: true, accessibilityAllowed: true, speechModelReady: true, speechModelLoading: false)

    func testNothingWrong() {
        XCTAssertEqual(SystemStatus.problems(allGood), [])
    }

    func testProblemsComeInTheOrderToFixThem() {
        let input = SystemStatusInput(
            microphoneAllowed: false, accessibilityAllowed: false, speechModelReady: false, speechModelLoading: false)
        XCTAssertEqual(SystemStatus.problems(input), [.microphoneOff, .speechModelNotLoaded, .accessibilityOff])
    }

    func testLoadingIsShownButIsNotAProblemToFix() {
        var input = allGood
        input.speechModelReady = false
        input.speechModelLoading = true
        XCTAssertEqual(SystemStatus.problems(input), [.speechModelLoading])
        XCTAssertFalse(SystemProblem.speechModelLoading.isBlocking)
        XCTAssertNil(SystemProblem.speechModelLoading.fixLabel)
    }

    func testAccessibilityUsesTheNameSystemSettingsShows() {
        XCTAssertEqual(SystemSettingsLink.accessibilityName(macOSMajor: 26), "Accessibility")
        XCTAssertEqual(SystemSettingsLink.accessibilityName(macOSMajor: 27), "Device Control and Data Access")
        XCTAssertEqual(SystemSettingsLink.accessibilityName(macOSMajor: 28), "Device Control and Data Access")
    }

    func testEveryBlockingProblemOffersAFix() {
        for problem in [SystemProblem.microphoneOff, .speechModelNotLoaded, .accessibilityOff] {
            XCTAssertTrue(problem.isBlocking)
            XCTAssertNotNil(problem.fixLabel, "\(problem)")
        }
    }
}
