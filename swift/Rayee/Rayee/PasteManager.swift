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

    @Published var lastPasteSuccessful: Bool = true

    private init() {}

    // MARK: - Permission Checking

    /// Check if accessibility permission is granted (required for simulating key events)
    func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Check permission and prompt user to grant it if not already granted
    func checkAndRequestPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
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
            lastPasteSuccessful = false
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
            lastPasteSuccessful = false
            return
        }

        // Add Command modifier flag
        keyDown.flags = .maskCommand

        // Create key up event for Cmd+V
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("PasteManager: Failed to create key up event")
            lastPasteSuccessful = false
            return
        }

        keyUp.flags = .maskCommand

        // Post the events to simulate the key press
        // The events are posted to the currently focused application
        keyDown.post(tap: .cghidEventTap)

        // Small delay between key down and key up for reliability
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            keyUp.post(tap: .cghidEventTap)
            self?.lastPasteSuccessful = true
            print("PasteManager: Paste command sent")
        }
    }

    // MARK: - Alternative: Direct Text Input
    // This method types text character by character using keyboard events.
    // It's slower but doesn't use the clipboard. Currently unused but kept for reference.

    /// Type text character by character (alternative to clipboard approach)
    /// This preserves the clipboard but is slower for long text
    func typeText(_ text: String) {
        guard hasAccessibilityPermission() else {
            print("PasteManager: No accessibility permission for typing")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)

        for char in text {
            // Convert character to string for CGEvent
            let charString = String(char)

            // Create key event using the character
            guard let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                continue
            }

            // Set the Unicode character to type
            var unicodeChar = Array(charString.utf16)
            keyDownEvent.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
            keyDownEvent.post(tap: .cghidEventTap)

            guard let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }

            keyUpEvent.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
            keyUpEvent.post(tap: .cghidEventTap)

            // Small delay between characters to ensure they're processed
            Thread.sleep(forTimeInterval: 0.01)
        }

        print("PasteManager: Typed \(text.count) characters")
    }
}
