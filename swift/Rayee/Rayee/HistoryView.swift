//
//  HistoryView.swift
//  Rayee
//
//  History tab showing all past transcriptions.
//  Users can search, copy, and delete transcriptions from this view.
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyManager = HistoryManager.shared

    // Search text entered by the user
    @State private var searchText = ""

    // Track which transcription is expanded (to show full text)
    @State private var expandedId: UUID?

    // Confirmation dialog for clearing all history
    @State private var showingClearConfirmation = false

    // Filter transcriptions based on search text
    private var filteredTranscriptions: [TranscriptionRecord] {
        historyManager.searchTranscriptions(query: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar at top
            searchBar
                .padding()

            // Divider between search and list
            Divider()

            // Main content: list of transcriptions or empty state
            if filteredTranscriptions.isEmpty {
                emptyStateView
            } else {
                transcriptionList
            }

            // Footer with clear all button (only show if there's history)
            if !historyManager.transcriptions.isEmpty {
                Divider()
                footerView
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search transcriptions...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()

            if searchText.isEmpty {
                // No history at all
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No transcription history")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Your transcriptions will appear here")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // No search results
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No results found")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Try a different search term")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Transcription List

    private var transcriptionList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredTranscriptions) { record in
                    TranscriptionRow(
                        record: record,
                        isExpanded: expandedId == record.id,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedId == record.id {
                                    expandedId = nil
                                } else {
                                    expandedId = record.id
                                }
                            }
                        },
                        onCopy: {
                            copyToClipboard(record.text)
                        },
                        onDelete: {
                            historyManager.deleteTranscription(id: record.id)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("\(historyManager.count) transcription\(historyManager.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button("Clear All History") {
                showingClearConfirmation = true
            }
            .font(.caption)
            .foregroundColor(.red)
        }
        .padding()
        .alert("Clear All History?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                historyManager.clearAllHistory()
            }
        } message: {
            Text("This will permanently delete all your transcription history. This action cannot be undone.")
        }
    }

    // MARK: - Helper Methods

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Transcription Row

/// A single row in the history list showing one transcription
struct TranscriptionRow: View {
    let record: TranscriptionRecord
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main row content
            HStack(alignment: .top, spacing: 12) {
                // Text content (clickable to expand)
                VStack(alignment: .leading, spacing: 4) {
                    // Show full text if expanded, preview if not
                    Text(isExpanded ? record.text : record.textPreview)
                        .font(.body)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Metadata: timestamp and model
                    HStack(spacing: 8) {
                        Text(record.formattedTimestamp)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("•")
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
                .onTapGesture {
                    onToggleExpand()
                }

                Spacer()

                // Action buttons (show on hover or when expanded)
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

#Preview {
    HistoryView()
        .frame(width: 450, height: 350)
}
