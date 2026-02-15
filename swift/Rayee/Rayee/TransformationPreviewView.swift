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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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

    @ViewBuilder
    private var actionButtons: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                buttonRow
            }
        } else {
            buttonRow
        }
    }

    private var buttonRow: some View {
        HStack {
            useOriginalButton
            Spacer()
            useTransformedButton
        }
    }

    @ViewBuilder
    private var useOriginalButton: some View {
        if #available(macOS 26, *) {
            Button(action: onUseOriginal) {
                HStack(spacing: 4) {
                    Text("⎋")
                        .font(.system(size: 11))
                        .opacity(0.7)
                    Text("Original")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.glass)
        } else {
            HotkeyButton("Original", hotkeySymbol: "⎋", action: onUseOriginal)
        }
    }

    @ViewBuilder
    private var useTransformedButton: some View {
        if #available(macOS 26, *) {
            Button(action: { onUseTransformed(transformState.previewTransformed) }) {
                HStack(spacing: 4) {
                    Text("↵")
                        .font(.system(size: 11))
                        .opacity(0.7)
                    Text("Use This")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.glassProminent)
        } else {
            HotkeyButton("Use This", hotkeySymbol: "↵", isProminent: true) {
                onUseTransformed(transformState.previewTransformed)
            }
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
    .frame(width: 260)
    .padding()
}
