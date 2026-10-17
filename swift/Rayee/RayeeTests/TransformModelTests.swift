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

    func testSelectionResolvesByAvailabilityAndMemory() {
        let gb: UInt64 = 1024 * 1024 * 1024
        func resolve(_ selection: TransformModelSelection, _ memory: UInt64, _ apple: Bool) -> TransformModel? {
            TransformModel.effective(selection: selection, physicalMemory: memory, appleAvailable: apple)
        }
        // Automatic: Apple if available, else the memory rule.
        XCTAssertEqual(resolve(.automatic, 8 * gb, true), .apple)
        XCTAssertEqual(resolve(.automatic, 32 * gb, true), .apple)
        XCTAssertEqual(resolve(.automatic, 8 * gb, false), .qwen3_1_7B)
        XCTAssertEqual(resolve(.automatic, 16 * gb, false), .qwen3_4B)
        // Explicit Apple: never falls back to a download.
        XCTAssertEqual(resolve(.explicit(.apple), 8 * gb, true), .apple)
        XCTAssertNil(resolve(.explicit(.apple), 8 * gb, false))
        XCTAssertNil(resolve(.explicit(.apple), 32 * gb, false))
        // Explicit Qwen: always itself.
        for memory in [8 * gb, 32 * gb] {
            for apple in [true, false] {
                XCTAssertEqual(resolve(.explicit(.qwen3_1_7B), memory, apple), .qwen3_1_7B)
                XCTAssertEqual(resolve(.explicit(.qwen3_4B), memory, apple), .qwen3_4B)
            }
        }
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

    func testMissingOrUnknownSavedValueIsAutomatic() {
        XCTAssertEqual(TransformModelSelection(savedValue: nil), .automatic)
        XCTAssertEqual(TransformModelSelection(savedValue: "some-future-model"), .automatic)
        // Llama 3.2 1B was removed; users who had picked it move to Automatic.
        XCTAssertEqual(TransformModelSelection(savedValue: "llama3_2_1B"), .automatic)
        XCTAssertEqual(TransformModelSelection(savedValue: "qwen3_4B"), .explicit(.qwen3_4B))
        XCTAssertEqual(TransformModelSelection(savedValue: "apple"), .explicit(.apple))
    }

    func testSelectionTagsRoundTrip() {
        XCTAssertEqual(TransformModelSelection.automatic.tag, "automatic")
        XCTAssertEqual(TransformModelSelection(tag: "automatic"), .automatic)
        for model in TransformModel.allCases {
            XCTAssertEqual(TransformModelSelection(tag: model.rawValue), .explicit(model))
            XCTAssertEqual(TransformModelSelection.explicit(model).tag, model.rawValue)
        }
    }

    func testAppleUnavailableErrorSaysWhatToDo() {
        XCTAssertEqual(
            MLXTransformError.appleUnavailable.errorDescription,
            "Apple Intelligence isn't ready. Turn it on in System Settings, or choose another model.")
    }
}
