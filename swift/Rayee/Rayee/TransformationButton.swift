//
//  TransformationButton.swift
//  Rayee
//
//  A pill-shaped button for triggering text transformations.
//  Shows loading spinner when active, checkmark on success.
//

import SwiftUI

/// States a transformation button can be in
enum TransformButtonState {
    case idle
    case loading
    case success
}

/// A single transformation button with icon and label
struct TransformationButton: View {
    let type: TransformationType
    let state: TransformButtonState
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                buttonIcon
                    .font(.system(size: 11))
                    .frame(width: 14, height: 14)

                Text(type.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(buttonBackground)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled && state != .loading ? 0.5 : 1.0)
        .help("\(type.label) (\u{2318}\(type.shortcutNumber))")
    }

    @ViewBuilder
    private var buttonIcon: some View {
        switch state {
        case .idle:
            Image(systemName: type.icon)
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
        case .success:
            Image(systemName: "checkmark")
                .foregroundColor(.green)
        }
    }

    private var buttonBackground: some View {
        Group {
            if state == .loading {
                Capsule().fill(Color.accentColor.opacity(0.2))
            } else if state == .success {
                Capsule().fill(Color.green.opacity(0.15))
            } else {
                Capsule().fill(Color.secondary.opacity(0.12))
            }
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .loading: return .accentColor
        case .success: return .green
        case .idle: return .primary
        }
    }
}

#Preview {
    HStack {
        TransformationButton(type: .grammar, state: .idle, disabled: false) {}
        TransformationButton(type: .bullets, state: .loading, disabled: true) {}
        TransformationButton(type: .rephrase, state: .success, disabled: false) {}
    }
    .padding()
}
