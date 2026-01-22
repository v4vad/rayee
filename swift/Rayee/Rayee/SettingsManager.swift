//
//  SettingsManager.swift
//  Rayee
//
//  Manages user preferences using UserDefaults.
//  Settings are automatically saved and persist between app launches.
//

import Foundation
import SwiftUI
import Carbon.HIToolbox

// MARK: - Settings Keys
// These are the "addresses" where each setting is stored in UserDefaults
enum SettingsKey {
    static let hotkeyModifiers = "hotkeyModifiers"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let selectedModel = "selectedModel"
    static let autoPasteEnabled = "autoPasteEnabled"
    static let vocabularyList = "vocabularyList"
    static let soundsEnabled = "soundsEnabled"
}

// MARK: - AI Model Options
// The different transcription models available
// Smaller models are faster but less accurate; larger models are more accurate but slower
enum TranscriptionModel: String, CaseIterable, Identifiable {
    case tiny = "tiny"
    case small = "small"
    case medium = "medium"
    case large = "large"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (Fastest)"
        case .small: return "Small (Balanced)"
        case .medium: return "Medium (Better)"
        case .large: return "Large (Best Quality)"
        }
    }

    var description: String {
        switch self {
        case .tiny: return "~1GB RAM, fastest transcription"
        case .small: return "~2GB RAM, good balance of speed and accuracy"
        case .medium: return "~5GB RAM, better accuracy"
        case .large: return "~10GB RAM, highest accuracy"
        }
    }
}

// MARK: - Hotkey Configuration
// Stores the keyboard shortcut as modifier flags (Option, Command, etc.) + a key code
struct HotkeyConfig: Equatable, Codable {
    var modifiers: UInt32  // Modifier keys (Option, Command, Shift, Control)
    var keyCode: UInt32    // The main key (Space, A, B, etc.)

    // Default: Option + Space
    static let `default` = HotkeyConfig(
        modifiers: UInt32(optionKey),  // Option key
        keyCode: UInt32(kVK_Space)     // Space bar
    )

    // Human-readable description of the hotkey
    var displayString: String {
        var parts: [String] = []

        // Check which modifier keys are included
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        // Add the main key name
        parts.append(keyCodeToString(keyCode))

        return parts.joined()
    }

    // Convert a key code number to a readable name
    private func keyCodeToString(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "Key \(keyCode)"
        }
    }
}

// MARK: - Settings Manager
// Central manager for all app settings
// Uses @Published so SwiftUI views automatically update when settings change
class SettingsManager: ObservableObject {
    // Singleton instance - one shared settings manager for the whole app
    static let shared = SettingsManager()

    // The hotkey combination for starting transcription
    @Published var hotkeyConfig: HotkeyConfig {
        didSet { saveHotkeyConfig() }
    }

    // Which AI model to use for transcription
    @Published var selectedModel: TranscriptionModel {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: SettingsKey.selectedModel) }
    }

    // Whether to automatically paste text after transcription
    @Published var autoPasteEnabled: Bool {
        didSet { UserDefaults.standard.set(autoPasteEnabled, forKey: SettingsKey.autoPasteEnabled) }
    }

    // Custom vocabulary words to improve transcription accuracy
    @Published var vocabularyList: [String] {
        didSet { UserDefaults.standard.set(vocabularyList, forKey: SettingsKey.vocabularyList) }
    }

    // Whether to play audio feedback sounds
    @Published var soundsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: SettingsKey.soundsEnabled) }
    }

    private init() {
        // Load saved settings or use defaults

        // Load hotkey configuration
        let savedModifiers = UserDefaults.standard.object(forKey: SettingsKey.hotkeyModifiers) as? UInt32
        let savedKeyCode = UserDefaults.standard.object(forKey: SettingsKey.hotkeyKeyCode) as? UInt32

        if let modifiers = savedModifiers, let keyCode = savedKeyCode {
            self.hotkeyConfig = HotkeyConfig(modifiers: modifiers, keyCode: keyCode)
        } else {
            self.hotkeyConfig = .default
        }

        // Load selected model (default: small)
        if let modelString = UserDefaults.standard.string(forKey: SettingsKey.selectedModel),
           let model = TranscriptionModel(rawValue: modelString) {
            self.selectedModel = model
        } else {
            self.selectedModel = .small
        }

        // Load auto-paste setting (default: enabled)
        if UserDefaults.standard.object(forKey: SettingsKey.autoPasteEnabled) != nil {
            self.autoPasteEnabled = UserDefaults.standard.bool(forKey: SettingsKey.autoPasteEnabled)
        } else {
            self.autoPasteEnabled = true
        }

        // Load vocabulary list (default: empty)
        self.vocabularyList = UserDefaults.standard.stringArray(forKey: SettingsKey.vocabularyList) ?? []

        // Load sounds setting (default: enabled)
        if UserDefaults.standard.object(forKey: SettingsKey.soundsEnabled) != nil {
            self.soundsEnabled = UserDefaults.standard.bool(forKey: SettingsKey.soundsEnabled)
        } else {
            self.soundsEnabled = true
        }
    }

    // Save hotkey configuration to UserDefaults
    private func saveHotkeyConfig() {
        UserDefaults.standard.set(hotkeyConfig.modifiers, forKey: SettingsKey.hotkeyModifiers)
        UserDefaults.standard.set(hotkeyConfig.keyCode, forKey: SettingsKey.hotkeyKeyCode)
    }

    // Add a word to the vocabulary list
    func addVocabularyWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !vocabularyList.contains(trimmed) else { return }
        vocabularyList.append(trimmed)
    }

    // Remove a word from the vocabulary list
    func removeVocabularyWord(_ word: String) {
        vocabularyList.removeAll { $0 == word }
    }

    // Reset all settings to defaults
    func resetToDefaults() {
        hotkeyConfig = .default
        selectedModel = .small
        autoPasteEnabled = true
        vocabularyList = []
        soundsEnabled = true
    }
}
