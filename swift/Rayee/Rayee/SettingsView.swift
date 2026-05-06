//
//  SettingsView.swift
//  Rayee
//
//  Settings window — standard macOS toolbar-tab layout (Apple HIG).
//  Used as the body of the Settings scene in RayeeApp.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRecordingHotkey = false
    @State private var showingAccessibilityAlert = false
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(
                isRecordingHotkey: $isRecordingHotkey,
                showingAccessibilityAlert: $showingAccessibilityAlert
            )
            .tabItem { Label("General", systemImage: "gear") }
            .tag(0)

            ModelsSettingsTab()
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag(1)

            TransformationsSettingsTab()
                .tabItem { Label("Transforms", systemImage: "wand.and.stars") }
                .tag(2)

            VocabularySettingsTab()
                .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }
                .tag(3)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(4)

            UploadsView()
                .tabItem { Label("Uploads", systemImage: "square.and.arrow.up") }
                .tag(5)
        }
        .frame(width: 540, height: 420)
        .onAppear {
            // Deep-link to a specific tab if requested (e.g. from the menu)
            if let requestedTab = UserDefaults.standard.string(forKey: "settingsTab") {
                switch requestedTab {
                case "models":        selectedTab = 1
                case "transformations": selectedTab = 2
                case "vocabulary":    selectedTab = 3
                case "history":       selectedTab = 4
                case "uploads":       selectedTab = 5
                default:              break
                }
                UserDefaults.standard.removeObject(forKey: "settingsTab")
            }
        }
        .alert("Accessibility Permission Required", isPresented: $showingAccessibilityAlert) {
            Button("Open System Settings") {
                openAccessibilitySettings()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("To use global hotkeys and auto-paste, Rayee needs Accessibility permission. Please enable it in System Settings > Privacy & Security > Accessibility.")
        }
    }

    // MARK: - Helper Methods

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let hotkeyConfigChanged = Notification.Name("hotkeyConfigChanged")
    static let openSetupGuide = Notification.Name("openSetupGuide")
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
