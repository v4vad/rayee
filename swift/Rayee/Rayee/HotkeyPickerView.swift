//
//  HotkeyPickerView.swift
//  Rayee
//
//  A key combination recorder that lets users set their preferred hotkey.
//  Shows the current hotkey, detects conflicts with common macOS shortcuts.
//

import SwiftUI
import Carbon.HIToolbox

/// Known system shortcuts that might conflict
private let knownConflicts: [(modifiers: UInt32, keyCode: UInt32, name: String)] = [
    (UInt32(cmdKey), UInt32(kVK_Space), "Spotlight"),
    (UInt32(cmdKey | shiftKey), UInt32(kVK_ANSI_3), "Screenshot"),
    (UInt32(cmdKey | shiftKey), UInt32(kVK_ANSI_4), "Screenshot Selection"),
    (UInt32(cmdKey | shiftKey), UInt32(kVK_ANSI_5), "Screenshot Options"),
    (UInt32(cmdKey), UInt32(kVK_Tab), "App Switcher"),
    (UInt32(cmdKey), UInt32(kVK_ANSI_Q), "Quit App"),
    (UInt32(cmdKey), UInt32(kVK_ANSI_W), "Close Window"),
    (UInt32(cmdKey), UInt32(kVK_ANSI_C), "Copy"),
    (UInt32(cmdKey), UInt32(kVK_ANSI_V), "Paste"),
    (UInt32(cmdKey), UInt32(kVK_ANSI_X), "Cut"),
    (UInt32(cmdKey), UInt32(kVK_ANSI_Z), "Undo"),
    (UInt32(cmdKey), UInt32(kVK_ANSI_A), "Select All"),
]

struct HotkeyPickerView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var isRecording = false
    @State private var pendingConfig: HotkeyConfig?
    @State private var conflictWarning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current hotkey display
            HStack {
                Text("Recording Hotkey")
                    .font(.headline)
                Spacer()
                hotkeyDisplay
            }

            Text("Press this shortcut anywhere on your Mac to start recording")
                .font(.caption)
                .foregroundColor(.secondary)

            // Conflict warning
            if let warning = conflictWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)

                HStack {
                    Button("Use Anyway") {
                        applyPendingConfig()
                    }
                    .controlSize(.small)

                    Button("Cancel") {
                        pendingConfig = nil
                        conflictWarning = nil
                        isRecording = false
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear { setupKeyMonitor() }
    }

    // MARK: - Hotkey Display

    private var hotkeyDisplay: some View {
        Button(action: { isRecording.toggle() }) {
            HStack(spacing: 4) {
                if isRecording {
                    Text("Press keys...")
                        .foregroundColor(.orange)
                } else {
                    Text(settings.hotkeyConfig.displayString)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Key Monitor

    private func setupKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }

            let keyCode = UInt32(event.keyCode)
            var modifiers: UInt32 = 0

            if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }

            // Require at least one modifier
            guard modifiers != 0 else { return nil }

            let newConfig = HotkeyConfig(modifiers: modifiers, keyCode: keyCode)

            // Check for conflicts
            if let conflict = checkConflict(newConfig) {
                pendingConfig = newConfig
                conflictWarning = "\(newConfig.displayString) is used by \(conflict). Use anyway?"
            } else {
                settings.hotkeyConfig = newConfig
                isRecording = false
                conflictWarning = nil
                pendingConfig = nil
                NotificationCenter.default.post(name: .hotkeyConfigChanged, object: nil)
            }

            return nil
        }
    }

    /// Check if a hotkey config conflicts with known system shortcuts
    private func checkConflict(_ config: HotkeyConfig) -> String? {
        for known in knownConflicts {
            if config.modifiers == known.modifiers && config.keyCode == known.keyCode {
                return known.name
            }
        }
        return nil
    }

    /// Apply the pending config despite the conflict
    private func applyPendingConfig() {
        guard let config = pendingConfig else { return }
        settings.hotkeyConfig = config
        isRecording = false
        conflictWarning = nil
        pendingConfig = nil
        NotificationCenter.default.post(name: .hotkeyConfigChanged, object: nil)
    }
}

#Preview {
    HotkeyPickerView()
        .padding()
        .frame(width: 400)
}
