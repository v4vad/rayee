//
//  RayeeApp.swift
//  Rayee
//
//  Main entry point for the Rayee menu bar app.
//  Uses SwiftUI MenuBarExtra for the menu bar icon — required for Bartender 6 / macOS 26 compatibility.
//

import SwiftUI

@main
struct RayeeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            SimpleMenuView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.menu)

        // Settings window - standard macOS Settings scene (Apple HIG)
        Settings {
            SettingsView()
                .environmentObject(AppState.shared)
        }

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
