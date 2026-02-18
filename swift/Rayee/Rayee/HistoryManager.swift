//
//  HistoryManager.swift
//  Rayee
//
//  Manages transcription history storage using SQLite.
//  Stores all past transcriptions locally so they persist between app launches.
//

import Foundation
import SQLite3

// SQLite destructor constant - tells SQLite to copy strings immediately
// because Swift strings are temporary and may be deallocated
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// Manages reading and writing transcription history to a local database
class HistoryManager: ObservableObject {
    // Singleton instance - one shared history manager for the whole app
    static let shared = HistoryManager()

    // Published so views can react to history changes
    @Published var transcriptions: [TranscriptionRecord] = []

    // SQLite database connection
    private var db: OpaquePointer?

    // Path to the database file
    private let dbPath: URL

    private init() {
        // Set up the database path: ~/.rayee/history.db
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let rayeeDir = homeDir.appendingPathComponent(".rayee")
        self.dbPath = rayeeDir.appendingPathComponent("history.db")

        // Create the .rayee directory if it doesn't exist
        try? FileManager.default.createDirectory(at: rayeeDir, withIntermediateDirectories: true)

        // Open database connection, create table, and run migrations
        openDatabase()
        createTable()
        migrateAddTransformColumns()

        // Load existing transcriptions
        loadAllTranscriptions()
    }

    deinit {
        // Close database connection when the manager is destroyed
        sqlite3_close(db)
    }

    // MARK: - Public Methods

    /// Save a new transcription to history
    /// - Parameters:
    ///   - text: The transcribed text (final version, possibly transformed)
    ///   - model: The AI model that was used (e.g., "small", "medium")
    ///   - originalText: The original text before transformation (nil if not transformed)
    ///   - transformations: Comma-separated list of transformations applied (nil if none)
    func saveTranscription(text: String, model: String,
                           originalText: String? = nil, transformations: String? = nil) {
        let record = TranscriptionRecord(
            text: text, modelUsed: model,
            originalText: originalText, transformationsApplied: transformations
        )

        let insertSQL = """
            INSERT INTO transcriptions (id, text, timestamp, model, original_text, transformations_applied)
            VALUES (?, ?, ?, ?, ?, ?);
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, record.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, record.text, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 3, record.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 4, record.modelUsed, -1, SQLITE_TRANSIENT)

            if let original = originalText {
                sqlite3_bind_text(statement, 5, original, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 5)
            }

            if let transforms = transformations {
                sqlite3_bind_text(statement, 6, transforms, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 6)
            }

            if sqlite3_step(statement) == SQLITE_DONE {
                DispatchQueue.main.async {
                    self.transcriptions.insert(record, at: 0)
                }
            } else {
                print("Failed to save transcription: \(String(cString: sqlite3_errmsg(db)))")
            }
        }

        sqlite3_finalize(statement)
    }

    /// Get all transcriptions (already loaded in memory)
    func getAllTranscriptions() -> [TranscriptionRecord] {
        return transcriptions
    }

    /// Search transcriptions by text content
    /// - Parameter query: The search text to look for
    /// - Returns: Matching transcriptions, sorted by timestamp (newest first)
    func searchTranscriptions(query: String) -> [TranscriptionRecord] {
        if query.isEmpty {
            return transcriptions
        }

        let lowercasedQuery = query.lowercased()
        return transcriptions.filter { record in
            record.text.lowercased().contains(lowercasedQuery)
        }
    }

    /// Delete a single transcription from history
    /// - Parameter id: The unique ID of the transcription to delete
    func deleteTranscription(id: UUID) {
        let deleteSQL = "DELETE FROM transcriptions WHERE id = ?;"

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) == SQLITE_DONE {
                // Successfully deleted - remove from our in-memory list
                DispatchQueue.main.async {
                    self.transcriptions.removeAll { $0.id == id }
                }
            }
        }

        sqlite3_finalize(statement)
    }

    /// Delete all transcription history
    func clearAllHistory() {
        let deleteSQL = "DELETE FROM transcriptions;"

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_DONE {
                // Successfully cleared - empty our in-memory list
                DispatchQueue.main.async {
                    self.transcriptions.removeAll()
                }
            }
        }

        sqlite3_finalize(statement)
    }

    /// Get the count of transcriptions in history
    var count: Int {
        return transcriptions.count
    }

    // MARK: - Private Methods

    /// Open connection to the SQLite database
    private func openDatabase() {
        if sqlite3_open(dbPath.path, &db) != SQLITE_OK {
            print("Failed to open database at \(dbPath.path)")
        }
    }

    /// Create the transcriptions table if it doesn't exist
    private func createTable() {
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS transcriptions (
                id TEXT PRIMARY KEY,
                text TEXT NOT NULL,
                timestamp REAL NOT NULL,
                model TEXT NOT NULL
            );
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, createTableSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Failed to create table: \(String(cString: sqlite3_errmsg(db)))")
            }
        }

        sqlite3_finalize(statement)
    }

    /// Add original_text and transformations_applied columns if they don't exist
    private func migrateAddTransformColumns() {
        // SQLite ALTER TABLE ADD COLUMN is safe to run even if column exists would fail,
        // so we attempt and ignore errors (column already exists)
        let columns = [
            "ALTER TABLE transcriptions ADD COLUMN original_text TEXT;",
            "ALTER TABLE transcriptions ADD COLUMN transformations_applied TEXT;",
        ]

        for sql in columns {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    /// Load all transcriptions from the database into memory
    private func loadAllTranscriptions() {
        let querySQL = """
            SELECT id, text, timestamp, model, original_text, transformations_applied
            FROM transcriptions ORDER BY timestamp DESC;
            """

        var statement: OpaquePointer?
        var loadedRecords: [TranscriptionRecord] = []

        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let idString = String(cString: sqlite3_column_text(statement, 0))
                let text = String(cString: sqlite3_column_text(statement, 1))
                let timestamp = sqlite3_column_double(statement, 2)
                let model = String(cString: sqlite3_column_text(statement, 3))

                // Optional columns (may be NULL for old records)
                let originalText: String? = sqlite3_column_type(statement, 4) != SQLITE_NULL
                    ? String(cString: sqlite3_column_text(statement, 4)) : nil
                let transformations: String? = sqlite3_column_type(statement, 5) != SQLITE_NULL
                    ? String(cString: sqlite3_column_text(statement, 5)) : nil

                if let id = UUID(uuidString: idString) {
                    let record = TranscriptionRecord(
                        id: id,
                        text: text,
                        timestamp: Date(timeIntervalSince1970: timestamp),
                        modelUsed: model,
                        originalText: originalText,
                        transformationsApplied: transformations
                    )
                    loadedRecords.append(record)
                }
            }
        }

        sqlite3_finalize(statement)

        DispatchQueue.main.async {
            self.transcriptions = loadedRecords
        }
    }
}
