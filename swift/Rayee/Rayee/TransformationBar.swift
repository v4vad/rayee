//
//  TransformationBar.swift
//  Rayee
//
//  A horizontal row of transformation buttons that appears below
//  the transcription result. Supports Cmd+1 through Cmd+5 shortcuts.
//

import SwiftUI

/// Horizontal bar of transformation buttons
struct TransformationBar: View {
    @ObservedObject var transformState: TransformationState
    let enabledTypes: Set<String>
    let onTransform: (TransformationType) -> Void

    /// The transformation types to show (filtered by user settings)
    private var visibleTypes: [TransformationType] {
        TransformationType.allCases.filter { enabledTypes.contains($0.rawValue) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(visibleTypes) { type in
                    TransformationButton(
                        type: type,
                        state: buttonState(for: type),
                        disabled: transformState.isTransforming && transformState.activeType != type,
                        action: { onTransform(type) }
                    )
                    .keyboardShortcut(keyboardShortcut(for: type), modifiers: .command)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Determine the visual state for a specific button
    private func buttonState(for type: TransformationType) -> TransformButtonState {
        guard transformState.activeType == type else { return .idle }
        if transformState.isTransforming { return .loading }
        if transformState.showPreview { return .success }
        return .idle
    }

    /// Map transformation type to keyboard shortcut key
    private func keyboardShortcut(for type: TransformationType) -> KeyEquivalent {
        switch type.shortcutNumber {
        case 1: return "1"
        case 2: return "2"
        case 3: return "3"
        case 4: return "4"
        case 5: return "5"
        default: return "1"
        }
    }
}

#Preview {
    TransformationBar(
        transformState: TransformationState(),
        enabledTypes: Set(TransformationType.allCases.map(\.rawValue)),
        onTransform: { _ in }
    )
    .padding()
}
