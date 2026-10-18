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

    func testPreferredIsTheTurboModel() {
        XCTAssertEqual(WhisperModelCatalog.preferred, "openai_whisper-large-v3-v20240930_turbo_632MB")
    }

    func testM1FallsBackToTheDeviceDefault() {
        let m1Default = "openai_whisper-large-v3-v20240930_626MB"
        XCTAssertEqual(
            WhisperModelCatalog.recommendedModel(
                supported: ["openai_whisper-small", m1Default], deviceDefault: m1Default),
            m1Default)
    }

    func testSupportedMacGetsTurbo() {
        XCTAssertEqual(
            WhisperModelCatalog.recommendedModel(
                supported: ["openai_whisper-small", WhisperModelCatalog.preferred],
                deviceDefault: "openai_whisper-large-v3-v20240930_626MB"),
            WhisperModelCatalog.preferred)
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

    func testFeaturedModelsAreRecommendedSmallAndBase() {
        let available = ["openai_whisper-base", "openai_whisper-small", "big_turbo", "openai_whisper-tiny"]
        XCTAssertEqual(
            WhisperModelCatalog.featured(recommended: "big_turbo", selected: "big_turbo", available: available),
            ["big_turbo", "openai_whisper-small", "openai_whisper-base"])
    }

    func testTheModelInUseIsAlwaysFeatured() {
        let available = ["openai_whisper-base", "openai_whisper-small", "big_turbo", "openai_whisper-tiny"]
        XCTAssertEqual(
            WhisperModelCatalog.featured(recommended: "big_turbo", selected: "openai_whisper-tiny", available: available),
            ["big_turbo", "openai_whisper-small", "openai_whisper-base", "openai_whisper-tiny"])
    }
}
