//
//  AppLogger.swift
//  Rayee
//
//  Simple file-based logger to track app lifecycle events.
//  Writes to ~/.rayee/app.log so you can check what happened
//  if the app quits unexpectedly.
//

import Foundation

/// Logs important app events to a file for debugging
/// Check ~/.rayee/app.log to see what happened before a crash
enum AppLogger {

    /// Path to the log file
    private static let logFileURL: URL = {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".rayee").appendingPathComponent("app.log")
    }()

    /// File handle for writing (reused for efficiency)
    private static var fileHandle: FileHandle?

    /// Date formatter for timestamps
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    // MARK: - Public Methods

    /// Initialize the logger - call this when the app starts
    static func initialize() {
        ensureLogDirectory()
        openLogFile()
        log("App launched", category: "lifecycle")
    }

    /// Clean up - call this when the app terminates
    static func shutdown() {
        log("App terminating (user quit)", category: "lifecycle")
        fileHandle?.closeFile()
        fileHandle = nil
    }

    /// Log a message with a category
    /// - Parameters:
    ///   - message: What happened
    ///   - category: Type of event (lifecycle, server, error)
    static func log(_ message: String, category: String = "info") {
        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] [\(category.uppercased())] \(message)\n"

        // Write to file
        if let data = logLine.data(using: .utf8) {
            fileHandle?.write(data)
        }

        // Also print to console for debugging
        print("[AppLogger] \(logLine)", terminator: "")
    }

    /// Log an error with details
    static func logError(_ message: String, error: Error? = nil) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - \(error.localizedDescription)"
        }
        log(fullMessage, category: "error")
    }

    /// Log server-related events
    static func logServer(_ message: String) {
        log(message, category: "server")
    }

    // MARK: - Private Methods

    /// Create the ~/.rayee directory if it doesn't exist
    private static func ensureLogDirectory() {
        let fileManager = FileManager.default
        let rayeeDir = logFileURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: rayeeDir.path) {
            do {
                try fileManager.createDirectory(at: rayeeDir, withIntermediateDirectories: true)
            } catch {
                print("[AppLogger] Could not create log directory: \(error)")
            }
        }
    }

    /// Open or create the log file
    private static func openLogFile() {
        let fileManager = FileManager.default

        // Create file if it doesn't exist
        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: nil)
        }

        // Open for appending
        do {
            fileHandle = try FileHandle(forWritingTo: logFileURL)
            fileHandle?.seekToEndOfFile()

            // Add a separator for this session
            let separator = "\n=== New Session ===\n"
            if let data = separator.data(using: .utf8) {
                fileHandle?.write(data)
            }
        } catch {
            print("[AppLogger] Could not open log file: \(error)")
        }
    }
}
