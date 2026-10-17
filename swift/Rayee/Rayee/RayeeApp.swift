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
            MenuBarLabel(icon: appState.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)

        // Settings window - standard macOS Settings scene (Apple HIG)
        Settings {
            SettingsView()
                .environmentObject(AppState.shared)
        }

        // Onboarding - shown on first launch, and from Settings → About
        Window("Welcome to Rayee", id: "setup-guide") {
            OnboardingView()
                .environmentObject(AppState.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// The menu bar icon. It also opens the setup guide on first launch: the icon is drawn
/// at launch, while the menu's contents only appear once the user clicks the icon.
private struct MenuBarLabel: View {
    let icon: String
    @Environment(\.openWindow) private var openWindow
    private static var didCheckFirstLaunch = false

    var body: some View {
        Image(systemName: icon)
            .renderingMode(.template)
            .onAppear {
                guard !Self.didCheckFirstLaunch else { return }
                Self.didCheckFirstLaunch = true
                guard !SettingsManager.shared.hasCompletedSetup else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    openWindow(id: "setup-guide")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
    }
}

// MARK: - App Delegate
// Handles app-level events like activation and termination
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize logging first so we capture everything
        AppLogger.initialize()

        // Onboarding asks for permissions at its own steps; after setup, make sure they're requested
        if SettingsManager.shared.hasCompletedSetup {
            requestPermissionsOnFirstLaunch()
        }

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
