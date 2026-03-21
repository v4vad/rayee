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

    // Debounced search
    @State private var searchTask: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 0) {
            // Search bar at top
            searchBar
                .padding()

            // Divider between search and list
            Divider()

            // Main content: list of transcriptions or empty state
            if historyManager.transcriptions.isEmpty && !historyManager.isLoadingMore {
                emptyStateView
            } else {
                transcriptionList
            }

            // Footer with clear all button (only show if there's history)
            if historyManager.count > 0 {
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
                .onChange(of: searchText) { newValue in
                    searchTask?.cancel()
                    let task = DispatchWorkItem {
                        historyManager.performSearch(query: newValue)
                    }
                    searchTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchTask?.cancel()
                    searchText = ""
                    historyManager.performSearch(query: "")
                }) {
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
                ForEach(historyManager.transcriptions) { record in
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
                    .onAppear {
                        if record.id == historyManager.transcriptions.last?.id {
                            historyManager.loadNextPage()
                        }
                    }
                }

                if historyManager.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }

                if !historyManager.hasMorePages && !historyManager.transcriptions.isEmpty {
                    Text("End of history")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
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
    @State private var showOriginal = false

    /// The text to display (final or original)
    private var displayText: String {
        if showOriginal, let original = record.originalText {
            return original
        }
        return isExpanded ? record.text : record.textPreview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayText)
                        .font(.body)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Metadata row
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

                        // Transformation tags
                        ForEach(record.transformationTags, id: \.self) { tag in
                            Text(tag.capitalized)
                                .font(.caption2)
                                .foregroundColor(.purple)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.12))
                                .cornerRadius(3)
                        }
                    }

                    // Show original toggle
                    if record.wasTransformed && isExpanded {
                        Button(action: { showOriginal.toggle() }) {
                            Text(showOriginal ? "Show transformed" : "Show original")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
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
        .onHover { hovering in isHovering = hovering }
    }
}

#Preview {
    HistoryView()
        .frame(width: 450, height: 350)
}
