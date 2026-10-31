import XCTest
@testable import Rayee

final class AppLoggerTests: XCTestCase {

    func testRemoveLeftoversDeletesOnlyOldFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayee-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fm = FileManager.default
        for name in ["app.log", "audio_buffer.wav", "server.log", "history.db"] {
            fm.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data("x".utf8))
        }

        let removed = LegacyFiles.removeLeftovers(in: dir)

        XCTAssertEqual(Set(removed), ["app.log", "audio_buffer.wav", "server.log"])
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("app.log").path))
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("audio_buffer.wav").path))
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("server.log").path))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("history.db").path))
        XCTAssertEqual(LegacyFiles.removeLeftovers(in: dir), [])
    }
}
