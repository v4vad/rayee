import XCTest
import MLXLMCommon
@testable import Rayee

final class TransformModelTests: XCTestCase {

    func testDefaultIsStillLlama() {
        // The default changes only after the user scores the candidates (see the eval set doc).
        XCTAssertEqual(TransformModel.defaultModel, .llama3_2_1B)
    }

    func testThreeChoices() {
        XCTAssertEqual(TransformModel.allCases, [.llama3_2_1B, .qwen3_1_7B, .qwen3_4B])
    }

    func testSavedNamesStayStable() {
        // These strings are saved in UserDefaults. Renaming a case would silently reset users.
        XCTAssertEqual(TransformModel.llama3_2_1B.rawValue, "llama3_2_1B")
        XCTAssertEqual(TransformModel.qwen3_1_7B.rawValue, "qwen3_1_7B")
        XCTAssertEqual(TransformModel.qwen3_4B.rawValue, "qwen3_4B")
    }

    func testQwenTurnsThinkingOff() {
        XCTAssertEqual(TransformModel.qwen3_1_7B.additionalContext?["enable_thinking"] as? Bool, false)
        XCTAssertEqual(TransformModel.qwen3_4B.additionalContext?["enable_thinking"] as? Bool, false)
    }

    func testLlamaNeedsNoExtraContext() {
        XCTAssertNil(TransformModel.llama3_2_1B.additionalContext)
    }

    func testEachChoiceLoadsItsOwnModel() {
        XCTAssertEqual(TransformModel.llama3_2_1B.configuration.name, "mlx-community/Llama-3.2-1B-Instruct-4bit")
        XCTAssertEqual(TransformModel.qwen3_1_7B.configuration.name, "mlx-community/Qwen3-1.7B-4bit")
        XCTAssertEqual(TransformModel.qwen3_4B.configuration.name, "mlx-community/Qwen3-4B-4bit")
    }

    func testUnknownSavedValueFallsBackToDefault() {
        XCTAssertEqual(TransformModel.from(savedValue: "some-future-model"), .llama3_2_1B)
        XCTAssertEqual(TransformModel.from(savedValue: nil), .llama3_2_1B)
        XCTAssertEqual(TransformModel.from(savedValue: "qwen3_4B"), .qwen3_4B)
    }
}
