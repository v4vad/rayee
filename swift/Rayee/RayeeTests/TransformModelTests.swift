import XCTest
import MLXLMCommon
@testable import Rayee

final class TransformModelTests: XCTestCase {

    func testDefaultModelFollowsMemoryAndAppleAvailability() {
        let gb: UInt64 = 1024 * 1024 * 1024
        // Apple's model wins whenever it is available, whatever the memory.
        XCTAssertEqual(TransformModel.defaultModel(physicalMemory: 8 * gb, appleAvailable: true), .apple)
        XCTAssertEqual(TransformModel.defaultModel(physicalMemory: 32 * gb, appleAvailable: true), .apple)
        // Otherwise the memory rule.
        XCTAssertEqual(TransformModel.defaultModel(physicalMemory: 8 * gb, appleAvailable: false), .qwen3_1_7B)
        XCTAssertEqual(TransformModel.defaultModel(physicalMemory: 16 * gb, appleAvailable: false), .qwen3_4B)
    }

    func testChosenAppleFallsBackToQwenWhenUnavailable() {
        let gb: UInt64 = 1024 * 1024 * 1024
        XCTAssertEqual(TransformModel.effective(selected: .apple, physicalMemory: 8 * gb, appleAvailable: false), .qwen3_1_7B)
        XCTAssertEqual(TransformModel.effective(selected: .apple, physicalMemory: 16 * gb, appleAvailable: false), .qwen3_4B)
        XCTAssertEqual(TransformModel.effective(selected: .apple, physicalMemory: 8 * gb, appleAvailable: true), .apple)
        XCTAssertEqual(TransformModel.effective(selected: .qwen3_1_7B, physicalMemory: 32 * gb, appleAvailable: true), .qwen3_1_7B)
    }

    func testThreeChoices() {
        XCTAssertEqual(TransformModel.allCases, [.qwen3_1_7B, .qwen3_4B, .apple])
    }

    func testSavedNamesStayStable() {
        // These strings are saved in UserDefaults. Renaming a case would silently reset users.
        XCTAssertEqual(TransformModel.qwen3_1_7B.rawValue, "qwen3_1_7B")
        XCTAssertEqual(TransformModel.qwen3_4B.rawValue, "qwen3_4B")
        XCTAssertEqual(TransformModel.apple.rawValue, "apple")
    }

    func testAppleHasNoDownload() {
        XCTAssertEqual(TransformModel.apple.displayName, "Apple Intelligence (built-in)")
        XCTAssertEqual(TransformModel.apple.approximateDownload, "built into macOS")
        XCTAssertNil(TransformModel.apple.configuration)
        XCTAssertNil(TransformModel.apple.additionalContext)
    }

    func testQwenTurnsThinkingOff() {
        XCTAssertEqual(TransformModel.qwen3_1_7B.additionalContext?["enable_thinking"] as? Bool, false)
        XCTAssertEqual(TransformModel.qwen3_4B.additionalContext?["enable_thinking"] as? Bool, false)
    }

    func testEachChoiceLoadsItsOwnModel() {
        XCTAssertEqual(TransformModel.qwen3_1_7B.configuration?.name, "mlx-community/Qwen3-1.7B-4bit")
        XCTAssertEqual(TransformModel.qwen3_4B.configuration?.name, "mlx-community/Qwen3-4B-4bit")
    }

    func testUnknownSavedValueFallsBackToDefault() {
        XCTAssertEqual(TransformModel.from(savedValue: "some-future-model"), TransformModel.defaultModel)
        XCTAssertEqual(TransformModel.from(savedValue: nil), TransformModel.defaultModel)
        // Llama 3.2 1B was removed; users who had picked it move to the default.
        XCTAssertEqual(TransformModel.from(savedValue: "llama3_2_1B"), TransformModel.defaultModel)
        XCTAssertEqual(TransformModel.from(savedValue: "qwen3_4B"), .qwen3_4B)
        XCTAssertEqual(TransformModel.from(savedValue: "apple"), .apple)
    }
}
