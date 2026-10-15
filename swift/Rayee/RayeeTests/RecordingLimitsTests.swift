import XCTest
@testable import Rayee

final class RecordingLimitsTests: XCTestCase {

    func testRecordingLimitIsFiveMinutes() {
        XCTAssertEqual(Config.maxRecordingDuration, 300)
    }

    func testSilenceAutoStopStaysAtThirtySeconds() {
        // User decision (v0.8): keep the 30 s default and the 5–60 s slider.
        XCTAssertEqual(Config.defaultSilenceDuration, 30.0)
        XCTAssertEqual(Config.minSilenceDuration, 5.0)
        XCTAssertEqual(Config.maxSilenceDuration, 60.0)
    }
}
