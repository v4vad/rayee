//
//  PanelButtonStyles.swift
//  Rayee
//
//  Custom button styles for the floating recording panel.
//  Small pill-shaped buttons with a subtle appearance.
//

import SwiftUI

/// Small pill-shaped button with a subtle appearance
struct PillButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .foregroundColor(foregroundColor)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isProminent {
            return isPressed ? Color.accentColor.opacity(0.8) : Color.accentColor
        } else {
            return isPressed ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        isProminent ? .white : .primary
    }
}

#Preview("Buttons") {
    HStack(spacing: 12) {
        Button("Cancel") {}
            .buttonStyle(PillButtonStyle(isProminent: false))
        Button("Done") {}
            .buttonStyle(PillButtonStyle(isProminent: true))
    }
    .padding()
    .background(Color.black.opacity(0.05))
}
