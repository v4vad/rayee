//
//  UploadsView.swift
//  Rayee
//
//  The "Uploads" tab in Settings showing uploaded audio file transcriptions.
//  Users can upload audio files, see transcription status, and manage past uploads.
//

import SwiftUI

struct UploadsView: View {
    @ObservedObject var uploadManager = UploadManager.shared
    @ObservedObject var historyManager = UploadHistoryManager.shared
    @ObservedObject var settings = SettingsManager.shared

    @State private var searchText = ""
    @State private var expandedId: UUID?
    @State private var showingClearConfirmation = false

    private var filteredUploads: [UploadRecord] {
        historyManager.searchUploads(query: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Upload controls at top
            uploadControls
                .padding()

            Divider()

            // Status area (shown during upload)
            if uploadManager.status != .idle {
                statusArea
                    .padding()
                Divider()
            }

            // Search bar
            if !historyManager.uploads.isEmpty {
                searchBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
            }

            // Upload list or empty state
            if filteredUploads.isEmpty && historyManager.uploads.isEmpty && uploadManager.status == .idle {
                emptyStateView
            } else if filteredUploads.isEmpty && !searchText.isEmpty {
                noResultsView
            } else {
                uploadList
            }

            // Footer
            if !historyManager.uploads.isEmpty {
                Divider()
                footerView
            }
        }
    }

    // MARK: - Upload Controls

    private var uploadControls: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: {
                    uploadManager.pickAndUploadFile()
                }) {
                    Label("Choose File", systemImage: "doc.badge.plus")
                }
                .disabled(isUploading)

                Spacer()

                Toggle("Background transcription", isOn: $settings.backgroundUploadEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Text(settings.backgroundUploadEnabled
                 ? "Transcription runs in the background — you can still record while it processes."
                 : "Recording is paused while transcription processes.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status Area

    private var statusArea: some View {
        HStack(spacing: 12) {
            switch uploadManager.status {
            case .idle:
                EmptyView()

            case .converting:
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Converting...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let name = uploadManager.currentFileName {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcribing...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let name = uploadManager.currentFileName {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

            case .success(let text):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcription complete")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(text.prefix(80) + (text.count > 80 ? "..." : ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Dismiss") {
                    uploadManager.reset()
                }
                .controlSize(.small)

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Error")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("Dismiss") {
                    uploadManager.reset()
                }
                .controlSize(.small)
            }

            if case .idle = uploadManager.status {} else {
                if case .success = uploadManager.status {} else {
                    if case .error = uploadManager.status {} else {
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search uploads...", text: $searchText)
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
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No uploaded transcriptions")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Choose an audio file above to transcribe it")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No results found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Try a different search term")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Upload List

    private var uploadList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredUploads) { record in
                    UploadRow(
                        record: record,
                        isExpanded: expandedId == record.id,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedId = expandedId == record.id ? nil : record.id
                            }
                        },
                        onCopy: { copyToClipboard(record.text) },
                        onDelete: { historyManager.deleteUpload(id: record.id) }
                    )
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("\(historyManager.count) upload\(historyManager.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Clear All Uploads") {
                showingClearConfirmation = true
            }
            .font(.caption)
            .foregroundColor(.red)
        }
        .padding()
        .alert("Clear All Uploads?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                historyManager.clearAll()
            }
        } message: {
            Text("This will permanently delete all uploaded transcription history.")
        }
    }

    // MARK: - Helpers

    private var isUploading: Bool {
        switch uploadManager.status {
        case .converting, .transcribing: return true
        default: return false
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
