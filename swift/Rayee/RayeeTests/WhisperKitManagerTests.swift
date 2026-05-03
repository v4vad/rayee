import XCTest
@testable import Rayee

final class WhisperKitManagerTests: XCTestCase {

    func testBuildVocabularyPrompt() {
        let words = ["Karthik", "Rayee", "MLX"]
        let prompt = WhisperKitManager.buildVocabularyPrompt(from: words)
        XCTAssertEqual(prompt, "Karthik, Rayee, MLX")
    }

    func testBuildVocabularyPromptEmptyList() {
        let prompt = WhisperKitManager.buildVocabularyPrompt(from: [])
        XCTAssertNil(prompt)
    }
}
