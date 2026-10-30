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
    static let silenceDuration = "silenceDuration"
    // Removed in the design refresh; only migrateRemovedSettings reads them
    static let timeoutEnabled = "timeoutEnabled"
    static let transformationsEnabled = "transformationsEnabled"
    static let enabledTransformations = "enabledTransformations"
    static let hasCompletedSetup = "hasCompletedSetup"
    static let adaptiveVADEnabled = "adaptiveVADEnabled"
    static let selectedWhisperKitModel = "selectedWhisperKitModel"
    static let smartDictationEnabled = "smartDictationEnabled"
    static let recorderStyle = "recorderStyle"
    static let transformModel = "transformModel"
    static let livePreviewEnabled = "livePreviewEnabled"
    static let livePreviewLanguage = "livePreviewLanguage"
}

// MARK: - Hotkey Configuration
struct HotkeyConfig: Equatable, Codable {
    var modifiers: UInt32
    var keyCode: UInt32

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
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // The hotkey combination for starting transcription
    @Published var hotkeyConfig: HotkeyConfig {
        didSet { saveHotkeyConfig() }
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

    // How long to wait after speech stops before ending recording (in seconds)
    @Published var silenceDuration: Double {
        didSet { UserDefaults.standard.set(silenceDuration, forKey: SettingsKey.silenceDuration) }
    }

    // Whether the user has completed the first-launch setup
    @Published var hasCompletedSetup: Bool {
        didSet { UserDefaults.standard.set(hasCompletedSetup, forKey: SettingsKey.hasCompletedSetup) }
    }

    // Whether adaptive VAD is enabled (auto-calibrates silence threshold for 200ms at recording start)
    @Published var adaptiveVADEnabled: Bool {
        didSet { UserDefaults.standard.set(adaptiveVADEnabled, forKey: SettingsKey.adaptiveVADEnabled) }
    }

    // Whether Smart Dictation auto-processes transcriptions with the LLM (default: off)
    @Published var smartDictationEnabled: Bool {
        didSet { UserDefaults.standard.set(smartDictationEnabled, forKey: SettingsKey.smartDictationEnabled) }
    }

    // Where the recorder appears: out of the notch when there is one, or always floating under the menu bar
    @Published var recorderStyle: RecorderStyle {
        didSet { UserDefaults.standard.set(recorderStyle.rawValue, forKey: SettingsKey.recorderStyle) }
    }

    // Which on-device text model runs transformations: a TransformModel raw value, or
    // TransformModelSelection.automaticTag. Automatic is saved as no value at all.
    @Published var transformModel: String {
        didSet {
            guard !isReloadingTransformModel else { return }
            if transformModel == TransformModelSelection.automaticTag {
                UserDefaults.standard.removeObject(forKey: SettingsKey.transformModel)
            } else {
                UserDefaults.standard.set(transformModel, forKey: SettingsKey.transformModel)
            }
        }
    }

    // Show draft words in the recorder while speaking
    @Published var livePreviewEnabled: Bool {
        didSet { UserDefaults.standard.set(livePreviewEnabled, forKey: SettingsKey.livePreviewEnabled) }
    }

    // Language for the live preview (BCP-47)
    @Published var livePreviewLanguage: String {
        didSet { UserDefaults.standard.set(livePreviewLanguage, forKey: SettingsKey.livePreviewLanguage) }
    }

    // True while `reloadTransformModelFromDefaults` updates the value, so it isn't written back
    private var isReloadingTransformModel = false

    // Re-reads the saved text model choice into memory without writing anything back
    func reloadTransformModelFromDefaults() {
        isReloadingTransformModel = true
        defer { isReloadingTransformModel = false }
        transformModel = TransformModelSelection(
            savedValue: UserDefaults.standard.string(forKey: SettingsKey.transformModel)
        ).tag
    }

    private static let fwToWhisperKitNames: [String: String] = [
        "tiny": "openai_whisper-tiny",
        "base": "openai_whisper-base",
        "small": "openai_whisper-small",
        "medium": "openai_whisper-medium",
        "large-v3": "openai_whisper-large-v3",
        "large-v3-turbo": "openai_whisper-large-v3_turbo",
        "distil-small.en": "distil-whisper_distil-small.en",
        "distil-medium.en": "distil-whisper_distil-medium.en",
        "distil-large-v3": "distil-whisper_distil-large-v3"
    ]

    var selectedWhisperKitModel: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: SettingsKey.selectedWhisperKitModel) {
                return saved
            }
            // Migrate from old FasterWhisper name; unmapped old names fall back to the old default
            if let oldName = UserDefaults.standard.string(forKey: SettingsKey.selectedModel) {
                let migrated = Self.fwToWhisperKitNames[oldName] ?? WhisperModelCatalog.legacyDefault
                UserDefaults.standard.set(migrated, forKey: SettingsKey.selectedWhisperKitModel)
                return migrated
            }
            return WhisperModelCatalog.recommended
        }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.selectedWhisperKitModel) }
    }

    private init() {
        Self.migrateRemovedSettings(in: UserDefaults.standard)

        // Load saved settings or use defaults

        // Load hotkey configuration
        let savedModifiers = UserDefaults.standard.object(forKey: SettingsKey.hotkeyModifiers) as? UInt32
        let savedKeyCode = UserDefaults.standard.object(forKey: SettingsKey.hotkeyKeyCode) as? UInt32

        if let modifiers = savedModifiers, let keyCode = savedKeyCode {
            self.hotkeyConfig = HotkeyConfig(modifiers: modifiers, keyCode: keyCode)
        } else {
            self.hotkeyConfig = .default
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

        // Load silence duration setting (default: 30 seconds)
        if let savedDuration = UserDefaults.standard.object(forKey: SettingsKey.silenceDuration) as? Double {
            self.silenceDuration = savedDuration
        } else {
            self.silenceDuration = 30.0
        }

        // Load setup completion flag (default: false)
        let completedSetup = UserDefaults.standard.bool(forKey: SettingsKey.hasCompletedSetup)
        self.hasCompletedSetup = completedSetup

        // v0.9: save a speech model choice once. Existing installs keep the old default
        // (small); new installs get the recommended turbo model.
        // (Uses the local `completedSetup`: `self` can't be read until init has set every property.)
        let legacyModelFolder = Config.whisperKitDownloadBase
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(WhisperModelCatalog.legacyDefault)
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Only created once the user has transcribed something.
        let historyDB = home.appendingPathComponent(".rayee/history.db")
        // Models lived in Documents before v0.7.1.
        let preV071Models = home.appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml")
        let fm = FileManager.default
        WhisperModelCatalog.pinDefaultIfNeeded(
            in: UserDefaults.standard,
            isExistingInstall: completedSetup
                || fm.fileExists(atPath: legacyModelFolder.path)
                || fm.fileExists(atPath: historyDB.path)
                || fm.fileExists(atPath: preV071Models.path)
        )

        // Load adaptive VAD setting (default: false)
        self.adaptiveVADEnabled = UserDefaults.standard.bool(forKey: SettingsKey.adaptiveVADEnabled)

        // Load recorder style (default: automatic)
        self.recorderStyle = RecorderStyle(
            rawValue: UserDefaults.standard.string(forKey: SettingsKey.recorderStyle) ?? "") ?? .automatic

        // Load smart dictation setting (default: false — opt-in)
        if UserDefaults.standard.object(forKey: SettingsKey.smartDictationEnabled) != nil {
            self.smartDictationEnabled = UserDefaults.standard.bool(forKey: SettingsKey.smartDictationEnabled)
        } else {
            self.smartDictationEnabled = false
        }

        // Load text model choice (unknown or missing → Automatic)
        self.transformModel = TransformModelSelection(
            savedValue: UserDefaults.standard.string(forKey: SettingsKey.transformModel)
        ).tag

        // Load live preview (on unless turned off)
        if UserDefaults.standard.object(forKey: SettingsKey.livePreviewEnabled) != nil {
            self.livePreviewEnabled = UserDefaults.standard.bool(forKey: SettingsKey.livePreviewEnabled)
        } else {
            self.livePreviewEnabled = true
        }
        self.livePreviewLanguage = UserDefaults.standard.string(forKey: SettingsKey.livePreviewLanguage)
            ?? LivePreviewLanguages.defaultIdentifier
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
        autoPasteEnabled = true
        vocabularyList = []
        soundsEnabled = true
        silenceDuration = 30.0
        adaptiveVADEnabled = false
        smartDictationEnabled = false
        recorderStyle = .automatic
        // Automatic is saved as no value; setting it removes the saved key
        transformModel = TransformModelSelection.automaticTag
        livePreviewEnabled = true
        livePreviewLanguage = LivePreviewLanguages.defaultIdentifier
    }

    /// The design refresh removed three settings. Carry over what they meant, then delete them:
    /// with "Enable text transformations" off, Smart Dictation never ran, so it stays off.
    static func migrateRemovedSettings(in defaults: UserDefaults) {
        if defaults.object(forKey: SettingsKey.transformationsEnabled) != nil,
           !defaults.bool(forKey: SettingsKey.transformationsEnabled) {
            defaults.set(false, forKey: SettingsKey.smartDictationEnabled)
        }
        defaults.removeObject(forKey: SettingsKey.transformationsEnabled)
        defaults.removeObject(forKey: SettingsKey.enabledTransformations)
        defaults.removeObject(forKey: SettingsKey.timeoutEnabled)
    }
}
