import XCTest
@testable import Rayee

final class SmartDictationPolicyTests: XCTestCase {

    func testRunsWhenSwitchedOnAndThereIsText() {
        XCTAssertTrue(SmartDictationPolicy.willRun(smartDictationEnabled: true, text: "um hello"))
    }

    func testDoesNotRunWhenSwitchedOff() {
        XCTAssertFalse(SmartDictationPolicy.willRun(smartDictationEnabled: false, text: "um hello"))
    }

    func testDoesNotRunOnEmptyText() {
        XCTAssertFalse(SmartDictationPolicy.willRun(smartDictationEnabled: true, text: ""))
    }
}
