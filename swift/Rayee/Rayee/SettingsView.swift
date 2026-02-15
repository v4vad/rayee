//
//  SettingsView.swift
//  Rayee
//
//  Settings window UI with a two-pane sidebar layout.
//  Left sidebar shows section icons, right pane shows settings content.
//

import SwiftUI
import Carbon.HIToolbox

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case models
    case transformations
    case vocabulary
    case history
    case uploads

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .models: return "Models"
        case .transformations: return "Transforms"
        case .vocabulary: return "Vocabulary"
        case .history: return "History"
        case .uploads: return "Uploads"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .models: return "cpu"
        case .transformations: return "wand.and.stars"
        case .vocabulary: return "text.book.closed"
        case .history: return "clock.arrow.circlepath"
        case .uploads: return "square.and.arrow.up"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings = SettingsManager.shared
    @State private var isRecordingHotkey = false
    @State private var newVocabularyWord = ""
    @State private var showingAccessibilityAlert = false
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.label, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            detailView
        }
        .frame(minWidth: Config.settingsWindowWidth, minHeight: Config.settingsWindowMinHeight)
        .onAppear {
            // Check if we should open to a specific tab
            if let requestedTab = UserDefaults.standard.string(forKey: "settingsTab") {
                switch requestedTab {
                case "models":
                    selectedTab = .models
                case "transformations":
                    selectedTab = .transformations
                case "vocabulary":
                    selectedTab = .vocabulary
                case "history":
                    selectedTab = .history
                case "uploads":
                    selectedTab = .uploads
                default:
                    break
                }
                // Clear the preference after using it
                UserDefaults.standard.removeObject(forKey: "settingsTab")
            }

            setupHotkeyRecording()
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

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsTab(
                isRecordingHotkey: $isRecordingHotkey,
                showingAccessibilityAlert: $showingAccessibilityAlert
            )
        case .models:
            ModelsSettingsTab()
        case .transformations:
            TransformationsSettingsTab()
        case .vocabulary:
            vocabularyTab
        case .history:
            HistoryView()
        case .uploads:
            UploadsView()
        }
    }

    // MARK: - Vocabulary Tab

    private var vocabularyTab: some View {
        VStack(spacing: 16) {
            // Header explanation
            Text("Add words that Rayee might mishear (names, technical terms, etc.)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top)

            // Add word input
            HStack {
                TextField("Add a word...", text: $newVocabularyWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addWord()
                    }

                Button(action: addWord) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(newVocabularyWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)

            // Word list
            if settings.vocabularyList.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No custom words yet")
                        .foregroundColor(.secondary)
                    Text("Add words above to improve transcription accuracy")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(settings.vocabularyList, id: \.self) { word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button(action: {
                                settings.removeVocabularyWord(word)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            let word = settings.vocabularyList[index]
                            settings.removeVocabularyWord(word)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func addWord() {
        settings.addVocabularyWord(newVocabularyWord)
        newVocabularyWord = ""
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func setupHotkeyRecording() {
        // Set up local key event monitor for recording new hotkeys
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingHotkey else { return event }

            // Get the key code and modifiers
            let keyCode = UInt32(event.keyCode)
            var modifiers: UInt32 = 0

            // Convert NSEvent modifier flags to Carbon modifier flags
            if event.modifierFlags.contains(.control) {
                modifiers |= UInt32(controlKey)
            }
            if event.modifierFlags.contains(.option) {
                modifiers |= UInt32(optionKey)
            }
            if event.modifierFlags.contains(.shift) {
                modifiers |= UInt32(shiftKey)
            }
            if event.modifierFlags.contains(.command) {
                modifiers |= UInt32(cmdKey)
            }

            // Require at least one modifier key
            if modifiers != 0 {
                settings.hotkeyConfig = HotkeyConfig(modifiers: modifiers, keyCode: keyCode)
                isRecordingHotkey = false

                // Notify HotkeyManager to re-register the hotkey
                NotificationCenter.default.post(name: .hotkeyConfigChanged, object: nil)
            }

            return nil  // Consume the event
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let hotkeyConfigChanged = Notification.Name("hotkeyConfigChanged")
    static let openSetupGuide = Notification.Name("openSetupGuide")
}

#Preview {
    SettingsView()
}
