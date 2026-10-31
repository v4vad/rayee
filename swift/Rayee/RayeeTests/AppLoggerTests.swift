import XCTest
@testable import Rayee

final class AppLoggerTests: XCTestCase {

    private func sampleLog(lines: Int) -> Data {
        let text = (0..<lines).map { "line number \($0)\n" }.joined()
        return Data(text.utf8)
    }

    func testTrimmedLogReturnsNilWhenUnderLimit() {
        let data = sampleLog(lines: 10)
        XCTAssertNil(AppLogger.trimmedLog(data, maxBytes: data.count, keepBytes: 50))
    }

    func testTrimmedLogKeepsNewestWholeLines() {
        let data = sampleLog(lines: 200)
        let result = AppLogger.trimmedLog(data, maxBytes: 1000, keepBytes: 500)
        XCTAssertNotNil(result)
        guard let result = result else { return }
        XCTAssertLessThanOrEqual(result.count, 500)
        XCTAssertFalse(result.isEmpty)
        let text = String(decoding: result, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("line number "))
        XCTAssertTrue(text.hasSuffix("line number 199\n"))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).hasSuffix(text))
    }

    func testRemoveLeftoversDeletesOnlyOldPythonFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayee-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fm = FileManager.default
        for name in ["audio_buffer.wav", "server.log", "history.db"] {
            fm.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data("x".utf8))
        }

        let removed = LegacyFiles.removeLeftovers(in: dir)

        XCTAssertEqual(Set(removed), ["audio_buffer.wav", "server.log"])
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("audio_buffer.wav").path))
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("server.log").path))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("history.db").path))
        XCTAssertEqual(LegacyFiles.removeLeftovers(in: dir), [])
    }
}
