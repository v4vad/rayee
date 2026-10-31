import XCTest
@testable import Rayee

final class UpdateInstallPolicyTests: XCTestCase {
    private let now = Date()

    func testNeverInstallsWhileBusy() {
        XCTAssertFalse(UpdateInstallPolicy.canInstallNow(isBusy: true, lastActivity: nil, now: now))
        XCTAssertFalse(UpdateInstallPolicy.canInstallNow(
            isBusy: true, lastActivity: now.addingTimeInterval(-3600), now: now))
    }

    func testWaitsForAQuietSpellAfterTheLastDictation() {
        XCTAssertFalse(UpdateInstallPolicy.canInstallNow(
            isBusy: false, lastActivity: now.addingTimeInterval(-30), now: now))
        XCTAssertTrue(UpdateInstallPolicy.canInstallNow(
            isBusy: false, lastActivity: now.addingTimeInterval(-UpdateInstallPolicy.quietPeriod), now: now))
    }

    func testInstallsRightAwayWhenNothingHasHappenedYet() {
        XCTAssertTrue(UpdateInstallPolicy.canInstallNow(isBusy: false, lastActivity: nil, now: now))
    }
}
