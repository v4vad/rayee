//
//  RayeeApp.swift
//  Rayee
//
//  Main entry point for the Rayee menu bar app.
//  Menu bar icon is managed by MenuBarController (NSStatusItem) for Bartender compatibility.
//

import SwiftUI

@main
struct RayeeApp: App {
    // NSApplication delegate for handling app lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
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
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize logging first so we capture everything
        AppLogger.initialize()
        menuBarController = MenuBarController(appState: AppState.shared)

        // Request permissions immediately on first launch
        requestPermissionsOnFirstLaunch()

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
