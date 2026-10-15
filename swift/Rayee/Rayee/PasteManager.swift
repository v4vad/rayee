//
//  PasteManager.swift
//  Rayee
//
//  Handles auto-paste functionality using the clipboard + Cmd+V approach.
//  Requires Accessibility permission to simulate keyboard events.
//

import Foundation
import Cocoa
import Carbon.HIToolbox

class PasteManager: ObservableObject {
    // Singleton instance
    static let shared = PasteManager()

    private init() {}

    // MARK: - Permission Checking

    /// Check if accessibility permission is granted (required for simulating key events)
    func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    // MARK: - Paste Operations

    /// Paste text to the currently focused application
    /// This works by: 1) Copying text to clipboard, 2) Simulating Cmd+V
    func pasteText(_ text: String) {
        guard !text.isEmpty else {
            print("PasteManager: Empty text, nothing to paste")
            return
        }

        guard hasAccessibilityPermission() else {
            print("PasteManager: No accessibility permission")
            return
        }

        // Step 1: Copy the text to the clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Step 2: Small delay to ensure the clipboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.simulatePaste()
        }
    }

    /// Simulate pressing Cmd+V to paste from clipboard
    private func simulatePaste() {
        // Create a CGEvent source
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' key
        let vKeyCode = CGKeyCode(kVK_ANSI_V)

        // Create key down event for Cmd+V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            print("PasteManager: Failed to create key down event")
            return
        }

        // Add Command modifier flag
        keyDown.flags = .maskCommand

        // Create key up event for Cmd+V
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("PasteManager: Failed to create key up event")
            return
        }

        keyUp.flags = .maskCommand

        // Post the events to simulate the key press
        // The events are posted to the currently focused application
        keyDown.post(tap: .cghidEventTap)

        // Small delay between key down and key up for reliability
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            keyUp.post(tap: .cghidEventTap)
            print("PasteManager: Paste command sent")
        }
    }
}
