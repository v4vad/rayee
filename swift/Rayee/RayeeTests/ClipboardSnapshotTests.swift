import XCTest
import AppKit
@testable import Rayee

final class ClipboardSnapshotTests: XCTestCase {

    private var board: NSPasteboard!

    override func setUp() {
        super.setUp()
        // A private pasteboard, so tests never touch the real clipboard
        board = NSPasteboard(name: NSPasteboard.Name("rayee-tests-\(UUID().uuidString)"))
        board.clearContents()
    }

    override func tearDown() {
        board.releaseGlobally()
        board = nil
        super.tearDown()
    }

    func testRestoresPlainText() {
        board.setString("my copied text", forType: .string)
        let snapshot = ClipboardSnapshot(of: board)

        board.clearContents()
        board.setString("dictated text", forType: .string)
        snapshot.restore(to: board)

        XCTAssertEqual(board.string(forType: .string), "my copied text")
    }

    func testRestoresNonTextData() {
        // Review focus: the user had an image on the clipboard.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        board.setData(png, forType: .png)
        let snapshot = ClipboardSnapshot(of: board)

        board.clearContents()
        board.setString("dictated text", forType: .string)
        snapshot.restore(to: board)

        XCTAssertEqual(board.data(forType: .png), png)
        XCTAssertNil(board.string(forType: .string))
    }

    func testEmptyClipboardStaysEmpty() {
        let snapshot = ClipboardSnapshot(of: board)

        board.setString("dictated text", forType: .string)
        snapshot.restore(to: board)

        XCTAssertNil(board.string(forType: .string))
        XCTAssertEqual(board.pasteboardItems?.count ?? 0, 0)
    }
}
