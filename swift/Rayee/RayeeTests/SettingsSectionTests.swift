import XCTest
@testable import Rayee

final class SettingsSectionTests: XCTestCase {

    func testOldDeepLinksStillLand() {
        XCTAssertEqual(SettingsSection(deepLink: "models"), .speechModel)
        XCTAssertEqual(SettingsSection(deepLink: "transformations"), .smartDictation)
        XCTAssertEqual(SettingsSection(deepLink: "vocabulary"), .dictionary)
        XCTAssertEqual(SettingsSection(deepLink: "history"), .history)
    }

    func testNewDeepLinksUseTheSectionName() {
        for section in SettingsSection.allCases {
            XCTAssertEqual(SettingsSection(deepLink: section.rawValue), section)
        }
    }

    func testUnknownDeepLinkIsIgnored() {
        XCTAssertNil(SettingsSection(deepLink: "nope"))
    }

    func testSidebarOrder() {
        XCTAssertEqual(SettingsSection.allCases.map(\.title),
                       ["General", "Recording", "Smart Dictation", "Speech Model", "Dictionary", "History", "About"])
    }
}
