import FoundationModels
import XCTest
@testable import Rayee

final class AppleTransformEngineTests: XCTestCase {

    func testDeltaOfGrowingSnapshots() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Needs macOS 26") }
        XCTAssertEqual(AppleTransformEngine.delta(previous: "", current: "Hel"), "Hel")
        XCTAssertEqual(AppleTransformEngine.delta(previous: "Hel", current: "Hello"), "lo")
        XCTAssertEqual(AppleTransformEngine.delta(previous: "Hello", current: "Hello"), "")
    }

    func testDeltaIgnoresSnapshotThatDoesNotExtendPrevious() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Needs macOS 26") }
        XCTAssertEqual(AppleTransformEngine.delta(previous: "Hello", current: "Help"), "")
        XCTAssertEqual(AppleTransformEngine.delta(previous: "Hello", current: "He"), "")
    }

    func testDeltasRebuildTheFinalText() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Needs macOS 26") }
        var emitted = ""
        for snapshot in ["So", "So where", "So where did we?"] {
            emitted += AppleTransformEngine.delta(previous: emitted, current: snapshot)
        }
        XCTAssertEqual(emitted, "So where did we?")
    }

    func testTranscriptHasInstructionsThenPairsPerExample() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Needs macOS 26") }
        let examples = MLXTransformManager.fewShotExamples(for: .smartDictation)
        let (transcript, prompt) = AppleTransformEngine.makeTranscript(text: "um hello there", type: .smartDictation)
        let entries = Array(transcript)
        XCTAssertEqual(entries.count, 1 + 2 * examples.count)
        guard case .instructions = entries[0] else { return XCTFail("first entry should be instructions") }
        guard case .prompt = entries[1] else { return XCTFail("second entry should be a prompt") }
        guard case .response = entries[2] else { return XCTFail("third entry should be a response") }
        XCTAssertEqual(prompt, MLXTransformManager.buildPrompt(text: "um hello there", type: .smartDictation).user)
        XCTAssertTrue(prompt.contains("<dictation>um hello there</dictation>"))
    }

    func testTranscriptWithoutExamplesIsInstructionsOnly() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Needs macOS 26") }
        let (transcript, prompt) = AppleTransformEngine.makeTranscript(text: "hi", type: .grammar)
        XCTAssertEqual(Array(transcript).count, 1)
        XCTAssertTrue(prompt.contains("grammar"))
    }
}
