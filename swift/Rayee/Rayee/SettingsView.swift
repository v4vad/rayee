//
//  SettingsView.swift
//  Rayee
//
//  Settings window UI for configuring hotkeys, model selection,
//  auto-paste behavior, and custom vocabulary.
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
            generalTab
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
        }
        .frame(width: 450, height: 350)
        .onAppear {
            // Check if we should open to a specific tab
            if let requestedTab = UserDefaults.standard.string(forKey: "settingsTab") {
                switch requestedTab {
                case "vocabulary": selectedTab = 1
                case "history": selectedTab = 2
                default: break
                }
                // Clear the preference after using it
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

    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            // Server Status Section
            Section {
                HStack {
                    Circle()
                        .fill(appState.isServerOnline ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text("Server Status")
                    Spacer()
                    Text(appState.isServerOnline ? "Online" : "Offline")
                        .foregroundColor(appState.isServerOnline ? .green : .red)
                }
            }

            Divider()

            // Hotkey Section
            Section {
                HStack {
                    Text("Global Hotkey")
                    Spacer()
                    hotkeyRecorderButton
                }
                Text("Press this keyboard shortcut anywhere to start transcription")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Model Selection Section
            Section {
                Picker("AI Model", selection: $settings.selectedModel) {
                    ForEach(TranscriptionModel.allCases) { model in
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                        }
                        .tag(model)
                    }
                }
                .pickerStyle(.menu)

                Text(settings.selectedModel.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Auto-Paste Section
            Section {
                Toggle("Auto-paste after transcription", isOn: $settings.autoPasteEnabled)
                    .onChange(of: settings.autoPasteEnabled) { newValue in
                        if newValue {
                            checkAccessibilityPermission()
                        }
                    }

                Text("Automatically paste transcribed text where your cursor is")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if settings.autoPasteEnabled {
                    accessibilityStatusView
                }
            }

            Divider()

            // Sound Feedback Section
            Section {
                Toggle("Play sounds", isOn: $settings.soundsEnabled)

                Text("Play audio feedback when recording starts and stops")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Recording Timeout Section
            Section {
                Toggle("Recording timeout", isOn: $settings.timeoutEnabled)

                Text("When enabled, recording stops after 60 seconds")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Silence Detection Section
            Section {
                HStack {
                    Text("Silence detection")
                    Spacer()
                    Text(String(format: "%.0fs", settings.silenceDuration))
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: $settings.silenceDuration,
                    in: Config.minSilenceDuration...Config.maxSilenceDuration,
                    step: 5
                )

                Text("After you stop speaking, recording ends after this many seconds of silence")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
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

    // MARK: - Hotkey Recorder Button
    private var hotkeyRecorderButton: some View {
        Button(action: {
            isRecordingHotkey.toggle()
        }) {
            HStack(spacing: 4) {
                if isRecordingHotkey {
                    Text("Press keys...")
                        .foregroundColor(.orange)
                } else {
                    Text(settings.hotkeyConfig.displayString)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecordingHotkey ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecordingHotkey ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            setupHotkeyRecording()
        }
    }

    // MARK: - Accessibility Status View
    private var accessibilityStatusView: some View {
        HStack {
            if PasteManager.shared.hasAccessibilityPermission() {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Accessibility permission granted")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Accessibility permission needed")
                    .font(.caption)
                    .foregroundColor(.orange)
                Spacer()
                Button("Grant Access") {
                    openAccessibilitySettings()
                }
                .font(.caption)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helper Methods

    private func addWord() {
        settings.addVocabularyWord(newVocabularyWord)
        newVocabularyWord = ""
    }

    private func checkAccessibilityPermission() {
        if !PasteManager.shared.hasAccessibilityPermission() {
            showingAccessibilityAlert = true
        }
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
