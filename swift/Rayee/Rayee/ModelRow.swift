//
//  ModelRow.swift
//  Rayee
//
//  A unified model row card for displaying transcription models
//  with download/use/delete actions.
//

import SwiftUI

// MARK: - Model Row Status

enum ModelRowStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double?)  // nil = indeterminate
    case ready
    case loading
    case error(String)
}

// MARK: - Model Row View

struct ModelRow: View {
    let name: String
    let description: String
    let sizeText: String
    let isActive: Bool
    let status: ModelRowStatus
    let onUse: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Model info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(.body, weight: .medium))

                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Text(sizeText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status / Actions
            statusView
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .notDownloaded:
            Button("Download & Use") { onUse() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

        case .downloading(let progress):
            VStack(spacing: 4) {
                if let progress = progress {
                    ProgressView(value: progress, total: 100)
                        .frame(width: 80)
                    Text("\(Int(progress))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

        case .ready:
            HStack(spacing: 8) {
                if !isActive {
                    Button("Use") { onUse() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if let onDelete = onDelete {
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

        case .loading:
            ProgressView()
                .controlSize(.small)

        case .error(let msg):
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(msg)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Button("Retry") { onUse() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }
}
