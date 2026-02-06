//
//  UploadHistoryManager.swift
//  Rayee
//
//  Saves and loads upload transcription records to a JSON file.
//  Stored at ~/.rayee/upload_history.json, separate from the recording history database.
//

import Foundation

class UploadHistoryManager: ObservableObject {
    static let shared = UploadHistoryManager()

    @Published var uploads: [UploadRecord] = []

    private let filePath: URL

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let rayeeDir = homeDir.appendingPathComponent(".rayee")
        self.filePath = rayeeDir.appendingPathComponent("upload_history.json")

        // Create the .rayee directory if it doesn't exist
        try? FileManager.default.createDirectory(at: rayeeDir, withIntermediateDirectories: true)

        loadFromDisk()
    }

    // MARK: - Public Methods

    /// Add a new upload record and save to disk
    func addUpload(_ record: UploadRecord) {
        DispatchQueue.main.async {
            self.uploads.insert(record, at: 0)
            self.saveToDisk()
        }
    }

    /// Delete a single upload by ID
    func deleteUpload(id: UUID) {
        DispatchQueue.main.async {
            self.uploads.removeAll { $0.id == id }
            self.saveToDisk()
        }
    }

    /// Delete all upload history
    func clearAll() {
        DispatchQueue.main.async {
            self.uploads.removeAll()
            self.saveToDisk()
        }
    }

    /// Search uploads by text content
    func searchUploads(query: String) -> [UploadRecord] {
        if query.isEmpty { return uploads }
        let lowered = query.lowercased()
        return uploads.filter {
            $0.text.lowercased().contains(lowered) ||
            $0.fileName.lowercased().contains(lowered)
        }
    }

    var count: Int { uploads.count }

    // MARK: - Private Methods

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(uploads)
            try data.write(to: filePath, options: .atomic)
        } catch {
            print("[UploadHistoryManager] Failed to save: \(error)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return }

        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let loaded = try decoder.decode([UploadRecord].self, from: data)
            DispatchQueue.main.async {
                self.uploads = loaded
            }
        } catch {
            print("[UploadHistoryManager] Failed to load: \(error)")
        }
    }
}
