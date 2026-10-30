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

        // Step 1: Remember what the user had copied, then put our text on the clipboard
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(of: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount
        AppLogger.diag("clipboard set (\(text.count) chars), physical mods=\(AppLogger.diagPhysicalModifiers())")  // DIAG

        // Step 2: Small delay to ensure the clipboard is ready, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.simulatePaste(text: text)

            // Step 3: Give the user's clipboard back, unless something new was copied meanwhile
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.clipboardRestoreDelay) {
                if pasteboard.changeCount == ourChangeCount {
                    snapshot.restore(to: pasteboard)
                    AppLogger.diag("clipboard restored")  // DIAG
                } else {
                    AppLogger.diag("clipboard restore skipped (changed since)")  // DIAG
                }
            }
        }
    }

    /// Simulate pressing Cmd+V to paste from clipboard
    private func simulatePaste(text: String) {
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
        let targetApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        AppLogger.diag("Cmd+V keyDown posting, physical mods=\(AppLogger.diagPhysicalModifiers()), front=\(targetApp)")  // DIAG
        keyDown.post(tap: .cghidEventTap)

        // Small delay between key down and key up for reliability
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            keyUp.post(tap: .cghidEventTap)
            AppLogger.diag("Cmd+V keyUp posted, physical mods=\(AppLogger.diagPhysicalModifiers()), front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")  // DIAG
            AppLogger.log("Pasted \(text.count) chars into \(targetApp)", category: "paste")
            print("PasteManager: Paste command sent")
        }
    }
}

/// A copy of everything on a pasteboard (text, images, files, rich text),
/// so it can be put back after Rayee borrows the clipboard to paste.
struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                }
            }
            return dataByType
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restoredItems = items.map { dataByType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dataByType {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}
