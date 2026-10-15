import XCTest
@testable import Rayee

final class WhisperModelCatalogTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // A private settings store, so tests never touch the real app settings
        suiteName = "rayee-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testRecommendedIsTheTurboModel() {
        XCTAssertEqual(WhisperModelCatalog.recommended, "openai_whisper-large-v3-v20240930_turbo_632MB")
    }

    func testNewInstallGetsTheRecommendedModel() {
        WhisperModelCatalog.pinDefaultIfNeeded(in: defaults, isExistingInstall: false)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.selectedWhisperKitModel), WhisperModelCatalog.recommended)
    }

    func testExistingInstallKeepsSmall() {
        // Review focus: an existing user who never picked a model must not be moved to a 632 MB download.
        WhisperModelCatalog.pinDefaultIfNeeded(in: defaults, isExistingInstall: true)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.selectedWhisperKitModel), "openai_whisper-small")
    }

    func testAChosenModelIsNeverChanged() {
        defaults.set("openai_whisper-base", forKey: SettingsKey.selectedWhisperKitModel)
        WhisperModelCatalog.pinDefaultIfNeeded(in: defaults, isExistingInstall: false)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.selectedWhisperKitModel), "openai_whisper-base")
    }

    func testOldEngineChoiceIsLeftForTheMigration() {
        // Users of the old Python engine have "selectedModel" saved; SettingsManager migrates that name.
        defaults.set("medium", forKey: SettingsKey.selectedModel)
        WhisperModelCatalog.pinDefaultIfNeeded(in: defaults, isExistingInstall: true)
        XCTAssertNil(defaults.string(forKey: SettingsKey.selectedWhisperKitModel))
    }

    func testSizeIsReadFromTheModelName() {
        XCTAssertEqual(WhisperModelCatalog.estimatedSizeMB(for: "openai_whisper-large-v3-v20240930_turbo_632MB"), 632)
        XCTAssertEqual(WhisperModelCatalog.estimatedSizeMB(for: "distil-whisper_distil-large-v3_594MB"), 594)
    }

    func testUncompressedTurboIsNotMistakenForSmall() {
        XCTAssertEqual(WhisperModelCatalog.estimatedSizeMB(for: "openai_whisper-large-v3_turbo"), 1600)
        XCTAssertEqual(WhisperModelCatalog.estimatedSizeMB(for: "openai_whisper-small"), 244)
    }

    func testRecommendedModelIsLabelled() {
        XCTAssertTrue(WhisperModelCatalog.description(for: WhisperModelCatalog.recommended).hasPrefix("Recommended"))
        XCTAssertFalse(WhisperModelCatalog.description(for: "openai_whisper-small").hasPrefix("Recommended"))
    }

    func testTurboModelsGetTheTurboDescription() {
        XCTAssertEqual(WhisperModelCatalog.description(for: "openai_whisper-large-v3_turbo"), "Fast large model, great accuracy")
    }
}
