import XCTest
@testable import Rayee

final class RecorderStateTests: XCTestCase {

    // MARK: - Heights

    func testCompactStatesShareOneHeight() {
        for phase: RecorderPhase in [.listening, .transcribing, .cleaningUp, .pasted] {
            XCTAssertEqual(RecorderLayout.bodyHeight(for: phase), 44, "\(phase)")
        }
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .hidden), 0)
    }

    func testResultGrowsWithItsTextUpToFourLines() {
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .result(text: "Hi")), 86)
        let long = String(repeating: "word ", count: 100)
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .result(text: long)), 140)
    }

    func testErrorLeavesRoomForItsButtonOnlyWhenThereIsOne() {
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .error(message: "Boom", action: nil)), 50)
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .error(message: "Boom", action: .openMicrophoneSettings)), 86)
    }

    func testNoStateIsTallerThanTheWindowAllows() {
        let long = String(repeating: "word ", count: 100)
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .result(text: long)), RecorderLayout.maxBodyHeight)
        XCTAssertEqual(
            RecorderLayout.bodyHeight(for: .error(message: long, action: .openMicrophoneSettings)),
            RecorderLayout.maxBodyHeight)
    }

    func testLineEstimate() {
        XCTAssertEqual(RecorderLayout.estimatedLines("", max: 4), 1)
        XCTAssertEqual(RecorderLayout.estimatedLines(String(repeating: "a", count: 36), max: 4), 1)
        XCTAssertEqual(RecorderLayout.estimatedLines(String(repeating: "a", count: 37), max: 4), 2)
        XCTAssertEqual(RecorderLayout.estimatedLines("one\ntwo", max: 4), 2)
        XCTAssertEqual(RecorderLayout.estimatedLines(String(repeating: "a", count: 1000), max: 4), 4)
    }

    // MARK: - Timing and focus

    func testAutoDismissDelays() {
        XCTAssertEqual(RecorderPhase.pasted.autoDismissDelay, 0.8)
        XCTAssertEqual(RecorderPhase.result(text: "x").autoDismissDelay, 20)
        XCTAssertEqual(RecorderPhase.error(message: "x", action: nil).autoDismissDelay, 8)
        XCTAssertNil(RecorderPhase.listening.autoDismissDelay)
        XCTAssertNil(RecorderPhase.cleaningUp.autoDismissDelay)
    }

    func testHoverPausesOnlyStatesWithSomethingToRead() {
        XCTAssertTrue(RecorderPhase.result(text: "x").hoverPausesDismiss)
        XCTAssertTrue(RecorderPhase.error(message: "x", action: nil).hoverPausesDismiss)
        XCTAssertFalse(RecorderPhase.pasted.hoverPausesDismiss)
    }

    func testOnlyTheResultTakesKeyboardFocus() {
        XCTAssertTrue(RecorderPhase.result(text: "x").takesKeyboardFocus)
        for phase: RecorderPhase in [.hidden, .listening, .transcribing, .cleaningUp, .pasted,
                                     .error(message: "x", action: nil)] {
            XCTAssertFalse(phase.takesKeyboardFocus, "\(phase)")
        }
    }

    // MARK: - Esc and clicks

    func testEscape() {
        XCTAssertEqual(RecorderRules.escape(in: .listening), .cancelRecording)
        XCTAssertEqual(RecorderRules.escape(in: .cleaningUp), .skipCleanup)
        XCTAssertEqual(RecorderRules.escape(in: .result(text: "x")), .dismiss)
        XCTAssertEqual(RecorderRules.escape(in: .error(message: "x", action: nil)), .dismiss)
        // Esc right after a paste belongs to the user's app
        XCTAssertEqual(RecorderRules.escape(in: .pasted), RecorderCommand.none)
        XCTAssertEqual(RecorderRules.escape(in: .transcribing), RecorderCommand.none)
        XCTAssertEqual(RecorderRules.escape(in: .hidden), RecorderCommand.none)
    }

    func testClick() {
        XCTAssertEqual(RecorderRules.click(in: .listening), .stopRecording)
        XCTAssertEqual(RecorderRules.click(in: .cleaningUp), .skipCleanup)
        XCTAssertEqual(RecorderRules.click(in: .result(text: "x")), RecorderCommand.none)
        XCTAssertEqual(RecorderRules.click(in: .pasted), RecorderCommand.none)
    }

    // MARK: - After transcription and clean-up

    func testAfterTranscription() {
        XCTAssertEqual(RecorderRules.afterTranscription(text: "", didPaste: false, smartDictationWillRun: false), .hidden)
        XCTAssertEqual(RecorderRules.afterTranscription(text: "hi", didPaste: false, smartDictationWillRun: true), .cleaningUp)
        XCTAssertEqual(RecorderRules.afterTranscription(text: "hi", didPaste: true, smartDictationWillRun: false), .pasted)
        XCTAssertEqual(RecorderRules.afterTranscription(text: "hi", didPaste: false, smartDictationWillRun: false),
                       .result(text: "hi"))
    }

    func testFinishedCleanupPastesTheCleanedText() {
        let outcome = RecorderRules.afterCleanup(raw: "um hi", cleaned: "Hi.", canPaste: true)
        XCTAssertEqual(outcome.phase, .pasted)
        XCTAssertEqual(outcome.pasteText, "Hi.")
    }

    func testSkippedCleanupDeliversRawTextOnce() {
        // Review focus 4: a skip (or failure) gives the raw text, once.
        let outcome = RecorderRules.afterCleanup(raw: "um hi", cleaned: nil, canPaste: true)
        XCTAssertEqual(outcome.phase, .pasted)
        XCTAssertEqual(outcome.pasteText, "um hi")
    }

    func testCleanupWithNowhereToPasteShowsTheText() {
        XCTAssertEqual(RecorderRules.afterCleanup(raw: "um hi", cleaned: "Hi.", canPaste: false).phase,
                       .result(text: "Hi."))
        XCTAssertNil(RecorderRules.afterCleanup(raw: "um hi", cleaned: "Hi.", canPaste: false).pasteText)
        XCTAssertEqual(RecorderRules.afterCleanup(raw: "um hi", cleaned: nil, canPaste: false).phase,
                       .result(text: "um hi"))
    }

    // MARK: - Paste decision

    func testPastesWhenEverythingAllowsIt() {
        XCTAssertTrue(RecorderRules.canPaste(requested: true, enabled: true, text: "hi", hasTarget: true, hasAccessibility: true))
    }

    func testNoAccessibilityMeansNoPaste() {
        // Review focus 3: without Accessibility the ⌘V never arrives, so "Pasted" would be a lie.
        XCTAssertFalse(RecorderRules.canPaste(requested: true, enabled: true, text: "hi", hasTarget: true, hasAccessibility: false))
    }

    func testOtherReasonsNotToPaste() {
        XCTAssertFalse(RecorderRules.canPaste(requested: false, enabled: true, text: "hi", hasTarget: true, hasAccessibility: true))
        XCTAssertFalse(RecorderRules.canPaste(requested: true, enabled: false, text: "hi", hasTarget: true, hasAccessibility: true))
        XCTAssertFalse(RecorderRules.canPaste(requested: true, enabled: true, text: "", hasTarget: true, hasAccessibility: true))
        XCTAssertFalse(RecorderRules.canPaste(requested: true, enabled: true, text: "hi", hasTarget: false, hasAccessibility: true))
    }
}
