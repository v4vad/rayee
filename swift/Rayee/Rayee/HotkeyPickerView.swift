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
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Dictation shortcut") {
                shortcutButton
            }

            // Conflict warning
            if let warning = conflictWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Use Anyway") {
                        applyPendingConfig()
                    }
                    Button("Cancel") {
                        cancelRecording()
                    }
                }
                .controlSize(.small)
            }
        }
        .onAppear { setupKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Shortcut Button

    private var shortcutButton: some View {
        Button {
            if isRecording { cancelRecording() } else { isRecording = true }
        } label: {
            Text(isRecording ? "Type shortcut…" : settings.hotkeyConfig.displayString)
                .foregroundStyle(isRecording ? .secondary : .primary)
                .frame(minWidth: 90)
        }
        .help(isRecording ? "Press the new shortcut, or Esc to cancel" : "Click to change")
    }

    // MARK: - Key Monitor

    /// Listens for the new shortcut while this view is on screen. Removed on disappear, so
    /// opening Settings again doesn't stack up listeners.
    private func setupKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }

            let keyCode = UInt32(event.keyCode)
            var modifiers: UInt32 = 0

            if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }

            // Esc on its own stops recording a shortcut
            if keyCode == UInt32(kVK_Escape) && modifiers == 0 {
                cancelRecording()
                return nil
            }

            // Require at least one modifier
            guard modifiers != 0 else { return nil }

            let newConfig = HotkeyConfig(modifiers: modifiers, keyCode: keyCode)

            // Check for conflicts
            if let conflict = checkConflict(newConfig) {
                pendingConfig = newConfig
                conflictWarning = "\(newConfig.displayString) is used by \(conflict). Use it anyway?"
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

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        cancelRecording()
    }

    private func cancelRecording() {
        pendingConfig = nil
        conflictWarning = nil
        isRecording = false
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
