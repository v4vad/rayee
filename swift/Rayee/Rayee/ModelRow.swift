//
//  ModelRow.swift
//  Rayee
//
//  One speech model as a Settings row: name, description and size, then its action.
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
        LabeledContent {
            statusView
        } label: {
            Text(name)
            Text("\(description) · \(sizeText)")
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .notDownloaded:
            Button("Download & Use") { onUse() }

        case .downloading(let progress):
            HStack(spacing: 8) {
                if let progress = progress {
                    ProgressView(value: progress, total: 100)
                        .frame(width: 80)
                    Text("\(Int(progress))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading…")
                }
            }
            .foregroundStyle(.secondary)

        case .ready:
            HStack(spacing: 8) {
                if isActive {
                    Label("In Use", systemImage: "checkmark")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Use") { onUse() }
                }
                if let onDelete = onDelete {
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this model")
                }
            }

        case .loading:
            ProgressView()
                .controlSize(.small)

        case .error(let msg):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .help(msg)
                Button("Retry") { onUse() }
            }
        }
    }
}
