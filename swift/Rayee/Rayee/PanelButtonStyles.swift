//
//  PanelButtonStyles.swift
//  Rayee
//
//  Custom button styles for the floating recording panel.
//  Small pill-shaped buttons with keyboard shortcut hints.
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

/// Button with keyboard hint (e.g., "⎋ Cancel")
struct HotkeyButton: View {
    let title: String
    let hotkeySymbol: String
    let isProminent: Bool
    let action: () -> Void

    init(
        _ title: String,
        hotkeySymbol: String,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.hotkeySymbol = hotkeySymbol
        self.isProminent = isProminent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(hotkeySymbol)
                    .font(.system(size: 11))
                    .opacity(0.7)
                Text(title)
            }
        }
        .buttonStyle(PillButtonStyle(isProminent: isProminent))
    }
}

#Preview("Buttons") {
    HStack(spacing: 12) {
        HotkeyButton("Cancel", hotkeySymbol: "⎋") {}
        HotkeyButton("Done", hotkeySymbol: "↵", isProminent: true) {}
    }
    .padding()
    .background(Color.black.opacity(0.05))
}
