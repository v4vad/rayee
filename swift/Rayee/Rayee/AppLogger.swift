//
//  AppLogger.swift
//  Rayee
//
//  Developer messages. They print to Xcode's console only: Rayee keeps no log file,
//  and never records what the user said.
//

import Foundation

enum AppLogger {

    /// Rayee's folder, ~/.rayee
    private static let rayeeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".rayee")

    // MARK: - Public Methods

    /// Call when the app starts: removes the log file older versions kept, and other leftovers
    static func initialize() {
        let removed = LegacyFiles.removeLeftovers(in: rayeeDirectory)
        if !removed.isEmpty {
            log("Removed old files: \(removed.joined(separator: ", "))", category: "lifecycle")
        }
        log("App launched", category: "lifecycle")
    }

    /// Call when the app terminates
    static func shutdown() {
        log("App terminating (user quit)", category: "lifecycle")
    }

    /// Prints a message to Xcode's console. Nothing is written to disk.
    /// - Parameters:
    ///   - message: What happened (never the user's dictated words)
    ///   - category: Type of event (lifecycle, hotkey, error)
    static func log(_ message: String, category: String = "info") {
        print("[\(category.uppercased())] \(message)")
    }

    /// Log an error with details
    static func logError(_ message: String, error: Error? = nil) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - \(error.localizedDescription)"
        }
        log(fullMessage, category: "error")
    }
}

/// Files older versions left in ~/.rayee. Nothing in the app uses them now.
/// app.log was Rayee's own log file until v0.10.1; it could hold pieces of dictated text.
/// vocabulary.json was the Python version's word list; the dictionary now lives in Settings.
enum LegacyFiles {
    static let names = ["app.log", "audio_buffer.wav", "server.log", "server.sock", "vocabulary.json"]

    /// Delete the leftovers that exist in `directory`; returns the names removed
    static func removeLeftovers(in directory: URL) -> [String] {
        var removed: [String] = []
        for name in names {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.removeItem(at: url)
                    removed.append(name)
                } catch {
                    // Ignore: we will try again next launch
                }
            }
        }
        return removed
    }
}
