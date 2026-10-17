import XCTest
import MLXLMCommon
@testable import Rayee

final class TransformModelTests: XCTestCase {

    func testDefaultModelFollowsMemory() {
        let gb: UInt64 = 1024 * 1024 * 1024
        XCTAssertEqual(TransformModel.defaultModel(physicalMemory: 8 * gb), .qwen3_1_7B)
        XCTAssertEqual(TransformModel.defaultModel(physicalMemory: 16 * gb), .qwen3_4B)
        XCTAssertEqual(TransformModel.defaultModel(physicalMemory: 48 * gb), .qwen3_4B)
    }

    func testTwoChoices() {
        XCTAssertEqual(TransformModel.allCases, [.qwen3_1_7B, .qwen3_4B])
    }

    func testSavedNamesStayStable() {
        // These strings are saved in UserDefaults. Renaming a case would silently reset users.
        XCTAssertEqual(TransformModel.qwen3_1_7B.rawValue, "qwen3_1_7B")
        XCTAssertEqual(TransformModel.qwen3_4B.rawValue, "qwen3_4B")
    }

    func testQwenTurnsThinkingOff() {
        XCTAssertEqual(TransformModel.qwen3_1_7B.additionalContext?["enable_thinking"] as? Bool, false)
        XCTAssertEqual(TransformModel.qwen3_4B.additionalContext?["enable_thinking"] as? Bool, false)
    }

    func testEachChoiceLoadsItsOwnModel() {
        XCTAssertEqual(TransformModel.qwen3_1_7B.configuration.name, "mlx-community/Qwen3-1.7B-4bit")
        XCTAssertEqual(TransformModel.qwen3_4B.configuration.name, "mlx-community/Qwen3-4B-4bit")
    }

    func testUnknownSavedValueFallsBackToDefault() {
        XCTAssertEqual(TransformModel.from(savedValue: "some-future-model"), TransformModel.defaultModel)
        XCTAssertEqual(TransformModel.from(savedValue: nil), TransformModel.defaultModel)
        // Llama 3.2 1B was removed; users who had picked it move to the default.
        XCTAssertEqual(TransformModel.from(savedValue: "llama3_2_1B"), TransformModel.defaultModel)
        XCTAssertEqual(TransformModel.from(savedValue: "qwen3_4B"), .qwen3_4B)
    }
}
