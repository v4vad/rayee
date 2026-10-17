import FoundationModels
import XCTest
@testable import Rayee

final class AppleTransformEngineTests: XCTestCase {

    func testDeltaOfGrowingSnapshots() throws {
        XCTAssertEqual(AppleTransformEngine.delta(previous: "", current: "Hel"), "Hel")
        XCTAssertEqual(AppleTransformEngine.delta(previous: "Hel", current: "Hello"), "lo")
        XCTAssertEqual(AppleTransformEngine.delta(previous: "Hello", current: "Hello"), "")
    }

    func testDeltaIgnoresSnapshotThatDoesNotExtendPrevious() throws {
        XCTAssertEqual(AppleTransformEngine.delta(previous: "Hello", current: "Help"), "")
        XCTAssertEqual(AppleTransformEngine.delta(previous: "Hello", current: "He"), "")
        // A rewritten snapshot (not an extension) gives nothing; the final text is what gets used.
        XCTAssertEqual(AppleTransformEngine.delta(previous: "so um hello", current: "So hello there"), "")
    }

    func testDeltaHandlesSnapshotsThatSplitACharacter() throws {
        // Devanagari: "नमस" then "नमस्" (the virama joins the last letter)
        XCTAssertEqual(AppleTransformEngine.delta(previous: "नमस", current: "नमस्"), "\u{094D}")
        XCTAssertEqual(AppleTransformEngine.delta(previous: "नमस्", current: "नमस्ते"), "ते")
        // Emoji skin-tone modifier arrives after the base emoji
        XCTAssertEqual(AppleTransformEngine.delta(previous: "\u{1F44B}", current: "\u{1F44B}\u{1F3FD}"), "\u{1F3FD}")
        // Rebuilding from split snapshots gives the full text
        var emitted = ""
        for snapshot in ["नमस", "नमस्", "नमस्ते", "नमस्ते \u{1F44B}", "नमस्ते \u{1F44B}\u{1F3FD}"] {
            emitted += AppleTransformEngine.delta(previous: emitted, current: snapshot)
        }
        XCTAssertEqual(emitted, "नमस्ते \u{1F44B}\u{1F3FD}")
    }

    func testDeltasRebuildTheFinalText() throws {
        var emitted = ""
        for snapshot in ["So", "So where", "So where did we?"] {
            emitted += AppleTransformEngine.delta(previous: emitted, current: snapshot)
        }
        XCTAssertEqual(emitted, "So where did we?")
    }

    func testTranscriptHasInstructionsThenPairsPerExample() throws {
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
        let (transcript, prompt) = AppleTransformEngine.makeTranscript(text: "hi", type: .grammar)
        XCTAssertEqual(Array(transcript).count, 1)
        XCTAssertTrue(prompt.contains("grammar"))
    }
}
