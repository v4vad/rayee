//
//  SystemStatus.swift
//  Rayee
//
//  What stops Rayee from working, and links to where the user fixes it.
//

import AppKit

/// Pages in System Settings that Rayee sends the user to.
enum SystemSettingsLink {
    static let microphone = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
