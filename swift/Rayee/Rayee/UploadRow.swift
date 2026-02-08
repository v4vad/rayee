//
//  UploadRow.swift
//  Rayee
//
//  A single row in the uploads list showing one uploaded file transcription.
//  Shows file name, transcribed text, timestamp, model, copy/delete buttons.
//

import SwiftUI

struct UploadRow: View {
    let record: UploadRecord
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // File name
                    Text(record.fileName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)

                    // Transcribed text
                    Text(isExpanded ? record.text : record.textPreview)
                        .font(.body)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Metadata
                    HStack(spacing: 8) {
                        Text(record.formattedTimestamp)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("\u{2022}")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(record.modelUsed)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onToggleExpand() }

                Spacer()

                if isHovering || isExpanded {
                    HStack(spacing: 8) {
                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                }
            }
        }
        .padding(12)
        .background(isHovering ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
