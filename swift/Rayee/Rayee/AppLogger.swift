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
    /// Only touched from inside `queue`
    private static var fileHandle: FileHandle?

    /// All file work happens on this one line-up, so threads never write at the same time
    private static let queue = DispatchQueue(label: "com.rayee.applogger")

    /// Once the log passes this size, the oldest part is cut off at launch
    private static let maxLogBytes = 1_000_000
    /// How much of the newest log is kept when cutting
    private static let keepLogBytes = 512 * 1024

    /// Date formatter for timestamps (only used inside `queue`, it is not safe to share)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    // MARK: - Public Methods

    /// Initialize the logger - call this when the app starts
    static func initialize() {
        let removed: [String] = queue.sync {
            prepareFileIfNeeded()
            return removedLeftovers
        }
        log("App launched", category: "lifecycle")
        if !removed.isEmpty {
            log("Removed old files from the Python version: \(removed.joined(separator: ", "))", category: "lifecycle")
        }
    }

    /// Clean up - call this when the app terminates
    static func shutdown() {
        log("App terminating (user quit)", category: "lifecycle")
        queue.sync {
            fileHandle?.closeFile()
            fileHandle = nil
        }
    }

    /// Log a message with a category
    /// - Parameters:
    ///   - message: What happened
    ///   - category: Type of event (lifecycle, hotkey, error)
    static func log(_ message: String, category: String = "info") {
        let now = Date()
        // Written before returning, so the last lines before a crash still reach the file
        queue.sync {
            // Parts of the app start before initialize() runs; open the file for them too
            prepareFileIfNeeded()
            let timestamp = dateFormatter.string(from: now)
            let logLine = "[\(timestamp)] [\(category.uppercased())] \(message)\n"

            // Write to file
            if let data = logLine.data(using: .utf8) {
                fileHandle?.write(data)
            }

            // Also print to console for debugging
            print("[AppLogger] \(logLine)", terminator: "")
        }
    }

    /// Log an error with details
    static func logError(_ message: String, error: Error? = nil) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - \(error.localizedDescription)"
        }
        log(fullMessage, category: "error")
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

    /// Decide how to shorten a log that has grown too big.
    /// Returns nil when the log is small enough. Otherwise returns roughly the
    /// last `keepBytes`, starting at the beginning of a full line.
    static func trimmedLog(_ data: Data, maxBytes: Int, keepBytes: Int) -> Data? {
        guard data.count > maxBytes else { return nil }

        let start = max(0, data.count - keepBytes)
        let newline = UInt8(ascii: "\n")
        let kept = Data(data[start...])

        // If the byte just before the cut is a line break, we already start on a fresh line
        if start == 0 || data[start - 1] == newline {
            return kept
        }
        // Otherwise skip the partial line at the front
        guard let firstBreak = kept.firstIndex(of: newline) else { return Data() }
        return Data(kept[(firstBreak + 1)...])
    }

    /// Whether the log file has been opened this launch (only touched inside `queue`)
    private static var isPrepared = false
    /// Old Python files removed this launch, reported by initialize() (only touched inside `queue`)
    private static var removedLeftovers: [String] = []

    /// Trims, opens and tidies up once per launch, whichever comes first: initialize() or a log line (call inside `queue`)
    private static func prepareFileIfNeeded() {
        guard !isPrepared else { return }
        isPrepared = true
        ensureLogDirectory()
        trimLogIfNeeded()
        openLogFile()
        removedLeftovers = LegacyFiles.removeLeftovers(in: logFileURL.deletingLastPathComponent())
    }

    /// Shorten the log file at launch if it has grown too big (call inside `queue`)
    private static func trimLogIfNeeded() {
        guard let data = try? Data(contentsOf: logFileURL),
              let trimmed = trimmedLog(data, maxBytes: maxLogBytes, keepBytes: keepLogBytes) else { return }
        try? trimmed.write(to: logFileURL, options: .atomic)
    }

    /// Open or create the log file (call inside `queue`)
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

/// Files the old Python version left in ~/.rayee. Nothing in the app uses them now.
enum LegacyFiles {
    static let names = ["audio_buffer.wav", "server.log", "server.sock"]

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
