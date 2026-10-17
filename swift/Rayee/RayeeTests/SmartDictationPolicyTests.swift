import XCTest
@testable import Rayee

final class SmartDictationPolicyTests: XCTestCase {

    func testRunsWhenBothSwitchesAreOnAndThereIsText() {
        XCTAssertTrue(SmartDictationPolicy.willRun(
            smartDictationEnabled: true, transformationsEnabled: true, text: "um hello"))
    }

    func testDoesNotRunWhenSmartDictationIsOff() {
        XCTAssertFalse(SmartDictationPolicy.willRun(
            smartDictationEnabled: false, transformationsEnabled: true, text: "um hello"))
    }

    func testDoesNotRunWhenTransformationsAreOff() {
        XCTAssertFalse(SmartDictationPolicy.willRun(
            smartDictationEnabled: true, transformationsEnabled: false, text: "um hello"))
    }

    func testDoesNotRunOnEmptyText() {
        XCTAssertFalse(SmartDictationPolicy.willRun(
            smartDictationEnabled: true, transformationsEnabled: true, text: ""))
    }

    func testPreloadNeedsBothSwitches() {
        XCTAssertTrue(SmartDictationPolicy.isActive(smartDictationEnabled: true, transformationsEnabled: true))
        XCTAssertFalse(SmartDictationPolicy.isActive(smartDictationEnabled: true, transformationsEnabled: false))
        XCTAssertFalse(SmartDictationPolicy.isActive(smartDictationEnabled: false, transformationsEnabled: true))
    }
}
