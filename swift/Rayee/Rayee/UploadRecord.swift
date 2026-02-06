//
//  UploadRecord.swift
//  Rayee
//
//  Data model for an uploaded audio file transcription.
//  Each record represents one file that was uploaded and transcribed.
//

import Foundation

struct UploadRecord: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let text: String
    let timestamp: Date
    let modelUsed: String

    /// Create a new upload record with current timestamp
    init(fileName: String, text: String, modelUsed: String) {
        self.id = UUID()
        self.fileName = fileName
        self.text = text
        self.timestamp = Date()
        self.modelUsed = modelUsed
    }

    /// Formatted timestamp for display
    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full

        let timeInterval = Date().timeIntervalSince(timestamp)
        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            return formatter.localizedString(for: timestamp, relativeTo: Date())
        }

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

    /// Preview of the text (truncated if too long)
    var textPreview: String {
        let maxLength = 100
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
}
