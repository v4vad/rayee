//
//  TransformationPreviewView.swift
//  Rayee
//
//  Shows a before/after comparison when text has been transformed.
//  Users can choose to keep the transformed text or revert to the original.
//

import SwiftUI

/// Preview showing original and transformed text side by side
struct TransformationPreviewView: View {
    @ObservedObject var transformState: TransformationState

    /// Called when user chooses to use the transformed text
    let onUseTransformed: (String) -> Void

    /// Called when user chooses to keep the original text
    let onUseOriginal: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if transformState.isTransforming {
                loadingView
            } else if let error = transformState.error {
                errorView(message: error)
            } else if transformState.showPreview {
                previewContent
            }
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Transforming...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Button("Cancel") {
                onUseOriginal()
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Error State

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(.orange)

            Text(userFriendlyError(message))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Dismiss") {
                onUseOriginal()
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    /// Convert technical errors into plain language
    private func userFriendlyError(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("connect") || lower.contains("server") {
            return "Server not running. Check System Status."
        }
        if lower.contains("not downloaded") || lower.contains("model") {
            return "Transform model not downloaded. Download it in Settings."
        }
        if lower.contains("timeout") || lower.contains("timed out") {
            return "Transformation timed out. Try again?"
        }
        return message
    }

    // MARK: - Preview Content

    private var previewContent: some View {
        VStack(spacing: 8) {
            // Original text (dimmed)
            textBox(
                label: "Original",
                text: transformState.previewOriginal,
                style: .secondary
            )

            // Arrow indicator
            Image(systemName: "arrow.down")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // Transformed text (prominent)
            textBox(
                label: transformState.activeType?.label ?? "Transformed",
                text: transformState.previewTransformed,
                style: .primary
            )

            // Action buttons
            actionButtons
        }
    }

    // MARK: - Text Box

    private func textBox(label: String, text: String, style: TextBoxStyle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(style == .primary ? .primary : .secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(style == .primary
                            ? Color(NSColor.textBackgroundColor)
                            : Color.secondary.opacity(0.08))
                )
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack {
            Button("Original", action: onUseOriginal)
                .buttonStyle(PillButtonStyle(isProminent: false))
            Spacer()
            Button("Use This") { onUseTransformed(transformState.previewTransformed) }
                .buttonStyle(PillButtonStyle(isProminent: true))
        }
    }
}

/// Style for text boxes in the preview
private enum TextBoxStyle {
    case primary
    case secondary
}

#Preview {
    let state = TransformationState()

    TransformationPreviewView(
        transformState: {
            state.previewOriginal = "lets go too the store"
            state.previewTransformed = "Let's go to the store."
            state.activeType = .grammar
            state.showPreview = true
            return state
        }(),
        onUseTransformed: { _ in },
        onUseOriginal: {}
    )
    .frame(width: 300)
    .padding()
}
