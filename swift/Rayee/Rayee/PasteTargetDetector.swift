//
//  PasteTargetDetector.swift
//  Rayee
//
//  Detects whether there's a valid text input target for pasting.
//  Used to decide whether to auto-paste or show text in the floating panel.
//

import Foundation
import AppKit

/// Checks if the current frontmost application can accept pasted text
struct PasteTargetDetector {

    /// Returns true if there's likely a valid place to paste text
    /// Returns false for: desktop, Finder with no windows, Rayee itself
    static func hasValidPasteTarget() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let bundleID = frontApp.bundleIdentifier ?? ""

        // List of apps/situations where paste won't work well
        let noTextInputApps = [
            "com.apple.finder",           // Finder (usually no text input)
            "com.apple.dock",             // Dock
            "com.apple.loginwindow",      // Login window
            "com.apple.notificationcenterui",  // Notification Center
        ]

        // Check if it's Rayee itself
        if bundleID == Bundle.main.bundleIdentifier {
            return false
        }

        // Check if it's a known no-text-input app
        if noTextInputApps.contains(bundleID) {
            // For Finder, check if there are any windows open
            // If there are windows, there might be a rename operation or dialog
            if bundleID == "com.apple.finder" {
                return finderHasActiveWindow()
            }
            return false
        }

        // Default: assume the app can accept text
        return true
    }

    /// Check if Finder has any windows that might accept text input
    private static func finderHasActiveWindow() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier == "com.apple.finder" else {
            return false
        }

        // Check if Finder has any windows open
        // We use NSRunningApplication to get window count
        // Note: This is a heuristic - Finder windows don't always have text fields

        // Get the list of windows for the frontmost app
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        // Count windows belonging to Finder
        let finderPID = frontApp.processIdentifier
        let finderWindows = windowList.filter { windowInfo in
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32 else {
                return false
            }
            return ownerPID == finderPID
        }

        // If Finder has windows, there might be a dialog or rename happening
        return !finderWindows.isEmpty
    }
}
