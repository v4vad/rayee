import XCTest
@testable import Rayee

@MainActor
final class DictationDeliveryTests: XCTestCase {

    // MARK: - Delivery line

    private func makeLine() -> (DeliveryLine, () -> [String]) {
        var pasted: [String] = []
        let line = DeliveryLine(paste: { text in
            pasted.append(text)
            await Task.yield()
        })
        return (line, { pasted })
    }

    func testLaterTextWaitsForEarlierOne() async {
        let (line, pasted) = makeLine()
        let first = line.reserve()
        let second = line.reserve()

        line.fill(second, "two")
        await line.idle()
        XCTAssertEqual(pasted(), [], "slot 1 isn't ready, so nothing is pasted")

        line.fill(first, "one")
        await line.idle()
        XCTAssertEqual(pasted(), ["one", "two"])
    }

    func testDroppedSlotLetsTheNextOneThrough() async {
        let (line, pasted) = makeLine()
        let first = line.reserve()
        let second = line.reserve()

        line.fill(second, "two")
        line.drop(first)
        await line.idle()
        XCTAssertEqual(pasted(), ["two"])
    }

    func testMixedRawAndCleanedFinishingOutOfOrderPasteInSpokenOrder() async {
        let (line, pasted) = makeLine()
        let first = line.reserve()   // cleaned
        let second = line.reserve()  // raw, no clean-up
        let third = line.reserve()   // cleaned

        line.fill(second, "two raw")
        line.fill(third, "Three cleaned")
        await line.idle()
        XCTAssertEqual(pasted(), [])

        line.fill(first, "One cleaned")
        await line.idle()
        XCTAssertEqual(pasted(), ["One cleaned", "two raw", "Three cleaned"])
    }

    func testAPasteWaitsForThePreviousPasteToFinish() async {
        var log: [String] = []
        let line = DeliveryLine(paste: { text in
            log.append("start \(text)")
            for _ in 0..<5 { await Task.yield() }
            log.append("end \(text)")
        })
        let a = line.reserve()
        let b = line.reserve()
        line.fill(a, "a")
        line.fill(b, "b")
        await line.idle()
        XCTAssertEqual(log, ["start a", "end a", "start b", "end b"])
    }

    func testSlotsReservedWhilePastingStillGoInOrder() async {
        let (line, pasted) = makeLine()
        let first = line.reserve()
        line.fill(first, "one")
        let second = line.reserve()
        line.fill(second, "two")
        await line.idle()
        XCTAssertEqual(pasted(), ["one", "two"])
    }

    // MARK: - Clean-ups run one at a time

    func testSecondCleanupStartsOnlyAfterTheFirstEnds() async {
        let queue = CleanupQueue()
        var log: [String] = []
        let first = queue.enqueue {
            log.append("1 start")
            for _ in 0..<5 { await Task.yield() }
            log.append("1 end")
        }
        let second = queue.enqueue { log.append("2 start") }
        await first.value
        await second.value
        XCTAssertEqual(log, ["1 start", "1 end", "2 start"])
    }

    // MARK: - Skipping

    func testSkippingACleanupAlsoSkipsEveryEarlierOne() {
        XCTAssertEqual(CleanupSkip.ids(upTo: 2, among: [3, 1, 2, 0]), [0, 1, 2])
        XCTAssertEqual(CleanupSkip.ids(upTo: 1, among: [1]), [1])
        XCTAssertEqual(CleanupSkip.ids(upTo: 0, among: [1, 2]), [])
    }

    func testSkippingTheSecondWhileTheFirstIsStuckPastesBothRawTextsInOrder() async {
        var pasted: [String] = []
        let line = DeliveryLine(paste: { pasted.append($0) })
        let queue = CleanupQueue()
        let firstSlot = line.reserve()
        let secondSlot = line.reserve()
        // The first clean-up never finishes (model still downloading)
        let stuck = queue.enqueue { while !Task.isCancelled { await Task.yield() } }
        let waiting = queue.enqueue { }

        // Skip the shown (second) clean-up: everything up to it is skipped, earliest first
        let skipped = CleanupSkip.ids(upTo: 1, among: [0, 1])
        let raw = ["one raw", "two raw"]
        let slots = [firstSlot, secondSlot]
        for id in skipped { line.fill(slots[id], raw[id]) }
        await line.idle()
        XCTAssertEqual(pasted, ["one raw", "two raw"])

        stuck.cancel()
        waiting.cancel()
        await stuck.value
        await waiting.value
    }

    // MARK: - Waiting for modifier keys

    func testPasteWaitsUntilModifiersAreReleased() async {
        var checks = 0
        var sleeps = 0
        await ModifierWait.untilReleased(
            isHeld: { checks += 1; return checks <= 3 },
            sleep: { _ in sleeps += 1 })
        XCTAssertEqual(checks, 4)
        XCTAssertEqual(sleeps, 3)
    }

    func testNoWaitWhenNothingIsHeld() async {
        var sleeps = 0
        await ModifierWait.untilReleased(isHeld: { false }, sleep: { _ in sleeps += 1 })
        XCTAssertEqual(sleeps, 0)
    }

    func testPasteGoesAheadAfterOneSecondIfModifierNeverReleases() async {
        var waited: Duration = .zero
        await ModifierWait.untilReleased(isHeld: { true }, sleep: { waited += $0 })
        XCTAssertEqual(waited, .milliseconds(1000))
    }
}
