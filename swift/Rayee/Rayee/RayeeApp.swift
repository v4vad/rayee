//
//  RayeeApp.swift
//  Rayee
//
//  Main entry point for the Rayee menu bar app.
//  Uses SwiftUI MenuBarExtra for the menu bar icon (reliable, Bartender-compatible).
//

import SwiftUI

@main
struct RayeeApp: App {
    // NSApplication delegate for handling app lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // MenuBarExtra creates the menu bar icon and dropdown menu
        MenuBarExtra {
            SimpleMenuView()
                .environmentObject(AppState.shared)
        } label: {
            Image(systemName: AppState.shared.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.menu)

        // Settings window - opens from menu or floating panel
        Window("Rayee Settings", id: "settings") {
            SettingsView()
                .environmentObject(AppState.shared)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: Config.settingsWindowWidth, height: Config.settingsWindowMinHeight)
        .defaultPosition(.center)

        // Setup guide window - shown on first launch or from menu
        Window("System Status", id: "setup-guide") {
            SetupGuideView()
                .environmentObject(AppState.shared)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - App Delegate
// Handles app-level events like activation and termination
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize logging first so we capture everything
        AppLogger.initialize()

        // Request permissions immediately on first launch
        requestPermissionsOnFirstLaunch()

        // Start the bundled Python server
        ServerManager.shared.start()

        // Initialize the update manager so background update checks begin
        _ = UpdateManager.shared

        // Backup hotkey start — fires on the main thread after the app has fully settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.hotkeyBackupStartDelay) {
            AppLogger.log("Backup hotkey start from AppDelegate", category: "hotkey")
            HotkeyManager.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up before quitting
        HotkeyManager.shared.stop()

        // Stop the Python server
        ServerManager.shared.stop()

        // Log shutdown and close the log file
        AppLogger.shutdown()
    }

    /// Request microphone and accessibility permissions on first launch
    private func requestPermissionsOnFirstLaunch() {
        // Request microphone permission (for recording)
        Task {
            let granted = await AudioRecorder.requestMicrophonePermission()
            print("Microphone permission: \(granted ? "granted" : "denied/pending")")
        }

        // Request accessibility permission (for hotkey and auto-paste)
        _ = HotkeyManager.shared.checkAccessibilityPermission()
    }
}
