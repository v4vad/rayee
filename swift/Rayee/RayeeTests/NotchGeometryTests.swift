import XCTest
@testable import Rayee

final class NotchGeometryTests: XCTestCase {

    // A 14" MacBook Pro: 1512 × 982 pt, a 202 pt notch, a 32 pt menu bar.
    private let laptop = ScreenInfo(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaTop: 32, leftAreaWidth: 655, rightAreaWidth: 655)

    // An external 1920 × 1080 monitor to the right of the laptop, 25 pt menu bar, no notch.
    private let monitor = ScreenInfo(
        frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1055),
        safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil)

    func testNotchSizeComesFromTheMenuBarAreasBesideIt() {
        XCTAssertEqual(NotchGeometry.notchSize(laptop), CGSize(width: 202, height: 32))
    }

    func testScreenWithoutMenuBarAreasHasNoNotch() {
        XCTAssertNil(NotchGeometry.notchSize(monitor))
    }

    func testScreenWithNoTopInsetHasNoNotch() {
        var flat = laptop
        flat.safeAreaTop = 0
        XCTAssertNil(NotchGeometry.notchSize(flat))
    }

    func testMenuBarHeight() {
        XCTAssertEqual(NotchGeometry.menuBarHeight(laptop), 32)
        XCTAssertEqual(NotchGeometry.menuBarHeight(monitor), 25)
    }

    func testHiddenMenuBarFallsBackToAStandardHeight() {
        var hidden = monitor
        hidden.visibleFrame = hidden.frame
        XCTAssertEqual(NotchGeometry.menuBarHeight(hidden), 24)
    }

    func testAutomaticUsesTheNotchWhenThereIsOne() {
        XCTAssertEqual(NotchGeometry.mode(for: laptop, style: .automatic), .notch(width: 202, height: 32))
    }

    func testFloatingStyleIgnoresTheNotch() {
        XCTAssertEqual(NotchGeometry.mode(for: laptop, style: .floating), .capsule(gap: 38))
    }

    func testNoNotchFloatsBelowTheMenuBar() {
        XCTAssertEqual(NotchGeometry.mode(for: monitor, style: .automatic), .capsule(gap: 31))
    }

    func testShapeIsAtLeastAsWideAsTheNotch() {
        XCTAssertEqual(NotchGeometry.shapeWidth(.notch(width: 202, height: 32)), 300)
        XCTAssertEqual(NotchGeometry.shapeWidth(.notch(width: 320, height: 32)), 320)
        XCTAssertEqual(NotchGeometry.shapeWidth(.capsule(gap: 31)), 300)
    }

    func testNotchShapeHangsFromTheTopOfTheScreen() {
        let frame = NotchGeometry.shapeFrame(
            screen: laptop.frame, mode: .notch(width: 202, height: 32), bodyHeight: 44)
        XCTAssertEqual(frame, CGRect(x: 606, y: 906, width: 300, height: 76))
    }

    func testCapsuleSitsBelowTheMenuBarOnItsOwnScreen() {
        let frame = NotchGeometry.shapeFrame(screen: monitor.frame, mode: .capsule(gap: 31), bodyHeight: 44)
        XCTAssertEqual(frame, CGRect(x: 2322, y: 1005, width: 300, height: 44))
    }

    func testMenuBarBesideTheNotchIsNotClickable() {
        // Review focus 1: only the notch itself and the body below the menu bar take clicks.
        let rects = NotchGeometry.hitRects(
            screen: laptop.frame, mode: .notch(width: 202, height: 32), bodyHeight: 44)
        let hit = { (p: CGPoint) in rects.contains { NotchGeometry.contains($0, p) } }
        XCTAssertFalse(hit(CGPoint(x: 640, y: 970)), "menu bar just left of the notch")
        XCTAssertFalse(hit(CGPoint(x: 870, y: 970)), "menu bar just right of the notch")
        XCTAssertTrue(hit(CGPoint(x: 700, y: 970)), "the notch")
        XCTAssertTrue(hit(CGPoint(x: 620, y: 920)), "the body")
    }

    func testHiddenRecorderTakesNoClicks() {
        XCTAssertTrue(NotchGeometry.hitRects(
            screen: laptop.frame, mode: .notch(width: 202, height: 32), bodyHeight: 0).isEmpty)
    }

    func testWindowFitsTheTallestStatePlusShadowRoom() {
        let frame = NotchGeometry.windowFrame(
            screen: laptop.frame, mode: .notch(width: 202, height: 32), maxBodyHeight: 140)
        XCTAssertEqual(frame, CGRect(x: 586, y: 790, width: 340, height: 192))
    }

    func testPointerOnTheTopEdgeCountsAsOnThatScreen() {
        // Review focus 2: NSEvent.mouseLocation can sit exactly on maxY, which CGRect.contains excludes.
        let frames = [laptop.frame, monitor.frame]
        XCTAssertEqual(NotchGeometry.screenIndex(mouse: CGPoint(x: 2000, y: 1080), frames: frames, mainIndex: 0), 1)
    }

    func testScreenChoiceFallsBackToMainThenFirst() {
        let frames = [laptop.frame, monitor.frame]
        XCTAssertEqual(NotchGeometry.screenIndex(mouse: CGPoint(x: 100, y: 100), frames: frames, mainIndex: 1), 0)
        XCTAssertEqual(NotchGeometry.screenIndex(mouse: CGPoint(x: -50, y: -50), frames: frames, mainIndex: 1), 1)
        XCTAssertEqual(NotchGeometry.screenIndex(mouse: CGPoint(x: -50, y: -50), frames: frames, mainIndex: nil), 0)
        XCTAssertNil(NotchGeometry.screenIndex(mouse: .zero, frames: [], mainIndex: nil))
    }
}
