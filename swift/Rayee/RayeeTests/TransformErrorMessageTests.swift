import XCTest
@testable import Rayee

final class TransformErrorMessageTests: XCTestCase {

    func testModelNotLoadedExplainsFirstDownload() {
        let message = TransformationPreviewView.friendlyError("The writing model is not loaded.")
        XCTAssertTrue(message.contains("internet"), "should explain the first-use download")
    }

    func testNeverMentionsTheOldServer() {
        let message = TransformationPreviewView.friendlyError("Could not connect to the server.")
        XCTAssertFalse(message.lowercased().contains("server not running"))
    }

    func testNoOutputIsExplained() {
        let message = TransformationPreviewView.friendlyError("No output produced")
        XCTAssertTrue(message.contains("didn't return any text"))
    }

    func testUnknownErrorsPassThrough() {
        XCTAssertEqual(TransformationPreviewView.friendlyError("Out of memory"), "Out of memory")
    }
}
