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
        // MenuBarExtra creates the menu bar icon and dropdown menu
        // This app lives in the menu bar with a simple dropdown
        MenuBarExtra {
            // Simple dropdown menu with basic actions
            SimpleMenuView()
                .environmentObject(appState)
                .onAppear {
                    // Start listening for global hotkey when UI appears
                    appState.startHotkeyListening()
                }
        } label: {
            // The icon that appears in the menu bar
            // Changes based on current status and shows server status via color
            if appState.isServerOnline {
                Image(systemName: appState.menuBarIcon)
                    .symbolRenderingMode(.hierarchical)
            } else {
                Image(systemName: appState.menuBarIcon)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.red)
            }
        }
        .menuBarExtraStyle(.menu)  // Simple dropdown menu

        // Settings window - opens from menu or floating panel
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App has fully launched
        print("Rayee launched")

        // Request permissions immediately on first launch
        // This ensures the hotkey and recording work right away
        requestPermissionsOnFirstLaunch()

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

    /// Request microphone and accessibility permissions on first launch
    /// This improves the user experience by getting permissions out of the way early
    private func requestPermissionsOnFirstLaunch() {
        // Request microphone permission (for recording)
        Task {
            let granted = await AudioRecorder.requestMicrophonePermission()
            print("Microphone permission: \(granted ? "granted" : "denied/pending")")
        }

        // Request accessibility permission (for hotkey and auto-paste)
        // This shows the system dialog if permission hasn't been granted yet
        _ = HotkeyManager.shared.checkAccessibilityPermission()
    }
}
