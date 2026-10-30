import XCTest
@testable import Rayee

final class LiveTranscriptTests: XCTestCase {

    // MARK: - Merging results

    func testDraftReplacesTheLastDraft() {
        var t = LiveTranscript()
        t.apply("Hello", isFinal: false)
        t.apply("Hello there", isFinal: false)
        XCTAssertEqual(t.settled, "")
        XCTAssertEqual(t.draft, "Hello there")
    }

    func testFinalSettlesAndClearsTheDraft() {
        var t = LiveTranscript()
        t.apply("Hello ther", isFinal: false)
        t.apply("Hello there.", isFinal: true)
        t.apply(" How", isFinal: false)
        XCTAssertEqual(t.settled, "Hello there.")
        XCTAssertEqual(t.draft, " How")
        XCTAssertEqual(t.text, "Hello there. How")
    }

    func testEmptyUntilWordsArrive() {
        var t = LiveTranscript()
        XCTAssertTrue(t.isEmpty)
        t.apply("  ", isFinal: false)
        XCTAssertTrue(t.isEmpty)   // whitespace alone shows nothing
    }

    // MARK: - Visible tail

    func testShortTextIsShownWhole() {
        var t = LiveTranscript()
        t.apply("Hi.", isFinal: true)
        t.apply(" there", isFinal: false)
        let tail = t.visibleTail(maxCharacters: 108)
        XCTAssertEqual(tail.settled, "Hi.")
        XCTAssertEqual(tail.draft, " there")
    }

    func testVisibleTailKeepsTheEndAtAWordBoundary() {
        var t = LiveTranscript()
        t.apply("alpha bravo charlie delta", isFinal: false)
        let tail = t.visibleTail(maxCharacters: 15)
        XCTAssertEqual(tail.settled, "")
        XCTAssertEqual(tail.draft, "charlie delta")   // never a cut-off "o charlie delta"
    }

    func testVisibleTailSplitsAcrossSettledAndDraft() {
        var t = LiveTranscript()
        t.apply("one two three four.", isFinal: true)
        t.apply(" five six", isFinal: false)
        let tail = t.visibleTail(maxCharacters: 17)
        XCTAssertEqual(tail.settled, "four.")
        XCTAssertEqual(tail.draft, " five six")
    }

    // MARK: - Layout

    func testListeningGrowsByOneLineAtATimeUpToThree() {
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .listening, liveLines: 0), 44)
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .listening, liveLines: 1), 74)   // 44 + 18 + 12
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .listening, liveLines: 3), 110)
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .listening, liveLines: 9), 110)
        XCTAssertLessThanOrEqual(RecorderLayout.bodyHeight(for: .listening, liveLines: 3), RecorderLayout.maxBodyHeight)
    }

    func testLiveLinesOnlyAffectListening() {
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .transcribing, liveLines: 3), 44)
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .pasted, liveLines: 3), 44)
    }

    func testLiveLinesNeverShrink() {
        var t = LiveTranscript()
        t.apply(String(repeating: "word ", count: 20), isFinal: false)   // 100 chars → 3 lines
        XCTAssertEqual(RecorderLayout.liveLines(previous: 0, transcript: t), 3)
        t.apply("short", isFinal: false)                                  // draft rewritten shorter
        XCTAssertEqual(RecorderLayout.liveLines(previous: 3, transcript: t), 3)
        XCTAssertEqual(RecorderLayout.liveLines(previous: 0, transcript: LiveTranscript()), 0)
    }

    func testUpdatesOutsideListeningAreIgnored() {
        XCTAssertTrue(RecorderRules.acceptsLiveTranscript(in: .listening))
        for phase: RecorderPhase in [.hidden, .transcribing, .cleaningUp, .pasted,
                                     .result(text: "x"), .error(message: "x", action: nil)] {
            XCTAssertFalse(RecorderRules.acceptsLiveTranscript(in: phase), "\(phase)")
        }
    }
}
