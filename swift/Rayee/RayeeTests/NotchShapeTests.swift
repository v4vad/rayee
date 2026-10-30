import XCTest
import SwiftUI
@testable import Rayee

final class NotchShapeTests: XCTestCase {

    func testNotchShapeFillsItsRectAndIsLeftRightSymmetric() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 32 + 44)
        let shape = NotchShape(bandWidth: 185, bandHeight: 32, bottomRadius: 20, topRadius: 20)
        let path = shape.path(in: rect)

        let box = path.boundingRect
        XCTAssertEqual(box.minX, rect.minX, accuracy: 0.5)
        XCTAssertEqual(box.maxX, rect.maxX, accuracy: 0.5)
        XCTAssertEqual(box.minY, rect.minY, accuracy: 0.5)
        XCTAssertEqual(box.maxY, rect.maxY, accuracy: 0.5)

        // Mirror the path left to right: it should cover the same area
        let mirrored = path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0))
        let mirroredBox = mirrored.boundingRect
        XCTAssertEqual(mirroredBox.minX, box.minX, accuracy: 0.5)
        XCTAssertEqual(mirroredBox.maxX, box.maxX, accuracy: 0.5)

        // The left half mirrors the right half
        let left = path.intersection(Path(CGRect(x: 0, y: 0, width: 150, height: rect.height))).boundingRect
        let right = path.intersection(Path(CGRect(x: 150, y: 0, width: 150, height: rect.height))).boundingRect
        XCTAssertEqual(left.minX, 300 - right.maxX, accuracy: 0.5)
        XCTAssertEqual(left.maxX, 300 - right.minX, accuracy: 0.5)
        XCTAssertEqual(left.minY, right.minY, accuracy: 0.5)
        XCTAssertEqual(left.maxY, right.maxY, accuracy: 0.5)
    }
}
