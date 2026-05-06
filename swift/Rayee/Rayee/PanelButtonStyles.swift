//
//  PanelButtonStyles.swift
//  Rayee
//
//  Button styles for the floating recording panel.
//

import SwiftUI

// MARK: - Blue pill (Done, primary action)

struct BluePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .default, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background(
                Capsule().fill(Color(hex: 0x0A84FF).opacity(configuration.isPressed ? 0.7 : 1.0))
            )
    }
}

// MARK: - Gray pill (Copy, secondary action)

struct GrayPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .default, weight: .medium))
            .foregroundColor(.white.opacity(0.82))
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background(
                Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            )
    }
}

// MARK: - Icon button (Format toggle)

struct IconButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(isActive ? 0.14 : (configuration.isPressed ? 0.12 : 0.07)))
            )
    }
}

// MARK: - Ghost text (Discard)

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(configuration.isPressed ? 0.2 : 0.35))
    }
}

// MARK: - Legacy pill (kept for any remaining callers)

struct PillButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isProminent
                    ? Color(hex: 0x0A84FF).opacity(configuration.isPressed ? 0.7 : 1.0)
                    : Color.white.opacity(configuration.isPressed ? 0.12 : 0.07)
                )
            )
            .foregroundColor(isProminent ? .white : .white.opacity(0.82))
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double(hex         & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Previews

#Preview("Button styles") {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            Button("Done") {}
                .buttonStyle(BluePillButtonStyle())
            Button("Copy") {}
                .buttonStyle(GrayPillButtonStyle())
            Button(action: {}) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.70))
            }
            .buttonStyle(IconButtonStyle(isActive: false))
            Button("Discard") {}
                .buttonStyle(GhostButtonStyle())
        }
        HStack(spacing: 12) {
            Button(action: {}) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.70))
            }
            .buttonStyle(IconButtonStyle(isActive: true))
        }
    }
    .padding(24)
    .background(Color(hex: 0x1C1C1E))
}
