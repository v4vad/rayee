//
//  TranscriptionRecord.swift
//  Rayee
//
//  Data model for storing transcription history.
//  Each record represents one completed transcription with metadata.
//

import Foundation

// A single transcription entry in history
// Stores the transcribed text along with when it happened and which AI model was used
struct TranscriptionRecord: Identifiable, Codable {
    let id: UUID           // Unique identifier for this record
    let text: String       // The transcribed text (final version, may be transformed)
    let timestamp: Date    // When the transcription was created
    let modelUsed: String  // Which AI model was used (tiny, small, medium, large)
    let originalText: String?           // Original text before transformation (nil if not transformed)
    let transformationsApplied: String? // Comma-separated list of transforms applied

    // Create a new record with current timestamp
    init(text: String, modelUsed: String, originalText: String? = nil, transformationsApplied: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.modelUsed = modelUsed
        self.originalText = originalText
        self.transformationsApplied = transformationsApplied
    }

    // Create a record with all fields (used when loading from database)
    init(id: UUID, text: String, timestamp: Date, modelUsed: String,
         originalText: String? = nil, transformationsApplied: String? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.modelUsed = modelUsed
        self.originalText = originalText
        self.transformationsApplied = transformationsApplied
    }

    /// Whether this transcription was transformed
    var wasTransformed: Bool {
        originalText != nil && !originalText!.isEmpty
    }

    /// Transformation types applied as an array
    var transformationTags: [String] {
        guard let applied = transformationsApplied, !applied.isEmpty else { return [] }
        return applied.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // Formatted timestamp for display (e.g., "Today at 2:34 PM" or "Jan 15 at 9:20 AM")
    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full

        // For very recent dates, use relative time
        let timeInterval = Date().timeIntervalSince(timestamp)
        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            return formatter.localizedString(for: timestamp, relativeTo: Date())
        }

        // For older dates, use a more specific format
        let dateFormatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(timestamp) {
            dateFormatter.dateFormat = "'Today at' h:mm a"
        } else if calendar.isDateInYesterday(timestamp) {
            dateFormatter.dateFormat = "'Yesterday at' h:mm a"
        } else if calendar.isDate(timestamp, equalTo: Date(), toGranularity: .year) {
            dateFormatter.dateFormat = "MMM d 'at' h:mm a"
        } else {
            dateFormatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        }

        return dateFormatter.string(from: timestamp)
    }

    // Preview of the text (truncated if too long)
    var textPreview: String {
        let maxLength = 100
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
}
