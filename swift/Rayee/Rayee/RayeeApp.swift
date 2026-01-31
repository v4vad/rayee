//
//  RayeeApp.swift
//  Rayee
//
//  Main entry point for the Rayee menu bar app.
//  This file creates the app and puts a waveform icon in your menu bar.
//

import SwiftUI

@main
struct RayeeApp: App {
    // The shared app state - tracks status, transcribed text, etc.
    @StateObject private var appState = AppState()

    // NSApplication delegate for handling app lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // MenuBarExtra creates the menu bar icon and popup
        // Instead of a regular window, this app lives in the menu bar
        MenuBarExtra {
            // This is what appears when you click the menu bar icon
            MenuBarView()
                .environmentObject(appState)
                .onAppear {
                    // Start listening for global hotkey when UI appears
                    appState.startHotkeyListening()
                }
        } label: {
            // The icon that appears in the menu bar
            // Changes based on current status
            Image(systemName: appState.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)  // Shows a popup window instead of a dropdown menu

        // Settings window - opens when user clicks the gear icon
        Window("Rayee Settings", id: "settings") {
            SettingsView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - App Delegate
// Handles app-level events like activation and termination
class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App has fully launched
        print("Rayee launched")

        // Start the bundled Python server
        // In development mode (no bundled server), this will detect that
        // and let the user run the server manually
        ServerManager.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up before quitting
        HotkeyManager.shared.stop()

        // Stop the Python server
        ServerManager.shared.stop()

        print("Rayee terminating")
    }
}

