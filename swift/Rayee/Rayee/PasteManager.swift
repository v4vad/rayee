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

    /// Paste text to the currently focused application, and return once the user's clipboard is back.
    /// This works by: 1) Copying text to clipboard, 2) Simulating Cmd+V, 3) Restoring the clipboard.
    /// Callers paste one text at a time (see DeliveryLine), so two pastes never share the clipboard.
    @MainActor
    func paste(_ text: String) async {
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

        // Step 2: Small delay to ensure the clipboard is ready, then paste
        try? await Task.sleep(for: .milliseconds(50))

        // A held modifier (e.g. Option from the hotkey) would turn Cmd+V into another shortcut
        await ModifierWait.untilReleased(
            isHeld: { Self.modifierKeysHeld() },
            sleep: { try? await Task.sleep(for: $0) })
        await simulatePaste(text: text)

        // Step 3: Give the user's clipboard back, unless something new was copied meanwhile
        try? await Task.sleep(for: .seconds(Config.clipboardRestoreDelay))
        if pasteboard.changeCount == ourChangeCount {
            snapshot.restore(to: pasteboard)
        }
    }

    /// Whether ⌘, ⌥, ⌃ or ⇧ is physically held down right now
    private static func modifierKeysHeld() -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        return !flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
    }

    /// Simulate pressing Cmd+V to paste from clipboard
    @MainActor
    private func simulatePaste(text: String) async {
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
        keyDown.post(tap: .cghidEventTap)

        // Small delay between key down and key up for reliability
        try? await Task.sleep(for: .milliseconds(20))
        keyUp.post(tap: .cghidEventTap)
        AppLogger.log("Pasted \(text.count) chars into \(targetApp)", category: "paste")
        print("PasteManager: Paste command sent")
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
