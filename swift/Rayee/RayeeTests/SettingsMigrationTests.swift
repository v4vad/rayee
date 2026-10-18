import XCTest
@testable import Rayee

final class SettingsMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "RayeeTests.SettingsMigration"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testTransformationsOffKeepsSmartDictationOff() {
        // Review focus 5: with the master switch off, Smart Dictation never ran. It must stay that way.
        defaults.set(false, forKey: SettingsKey.transformationsEnabled)
        defaults.set(true, forKey: SettingsKey.smartDictationEnabled)
        SettingsManager.migrateRemovedSettings(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: SettingsKey.smartDictationEnabled))
    }

    func testTransformationsOnLeavesSmartDictationAlone() {
        defaults.set(true, forKey: SettingsKey.transformationsEnabled)
        defaults.set(true, forKey: SettingsKey.smartDictationEnabled)
        SettingsManager.migrateRemovedSettings(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: SettingsKey.smartDictationEnabled))
    }

    func testFreshInstallGetsNoSmartDictationValue() {
        SettingsManager.migrateRemovedSettings(in: defaults)
        XCTAssertNil(defaults.object(forKey: SettingsKey.smartDictationEnabled))
    }

    func testRemovedSettingsAreDeleted() {
        defaults.set(true, forKey: SettingsKey.transformationsEnabled)
        defaults.set(["grammar"], forKey: SettingsKey.enabledTransformations)
        defaults.set(false, forKey: SettingsKey.timeoutEnabled)
        SettingsManager.migrateRemovedSettings(in: defaults)
        XCTAssertNil(defaults.object(forKey: SettingsKey.transformationsEnabled))
        XCTAssertNil(defaults.object(forKey: SettingsKey.enabledTransformations))
        XCTAssertNil(defaults.object(forKey: SettingsKey.timeoutEnabled))
    }
}
