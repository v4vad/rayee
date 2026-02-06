//
//  SettingsView.swift
//  Rayee
//
//  Settings window UI for configuring hotkeys, model selection,
//  auto-paste behavior, custom vocabulary, and file uploads.
//

import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings = SettingsManager.shared
    @State private var isRecordingHotkey = false
    @State private var newVocabularyWord = ""
    @State private var showingAccessibilityAlert = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(
                isRecordingHotkey: $isRecordingHotkey,
                showingAccessibilityAlert: $showingAccessibilityAlert
            )
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            vocabularyTab
                .tabItem {
                    Label("Vocabulary", systemImage: "text.book.closed")
                }
                .tag(1)

            historyTab
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(2)

            UploadsView()
                .tabItem {
                    Label("Uploads", systemImage: "square.and.arrow.up")
                }
                .tag(3)
        }
        .frame(minWidth: Config.settingsWindowWidth, minHeight: Config.settingsWindowMinHeight)
        .onAppear {
            // Check if we should open to a specific tab
            if let requestedTab = UserDefaults.standard.string(forKey: "settingsTab") {
                switch requestedTab {
                case "vocabulary": selectedTab = 1
                case "history": selectedTab = 2
                case "uploads": selectedTab = 3
                default: break
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

    // MARK: - History Tab
    private var historyTab: some View {
        HistoryView()
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

// MARK: - Notification for hotkey changes
extension Notification.Name {
    static let hotkeyConfigChanged = Notification.Name("hotkeyConfigChanged")
}

#Preview {
    SettingsView()
}
