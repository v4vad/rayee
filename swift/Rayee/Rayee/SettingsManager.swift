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
    static let timeoutEnabled = "timeoutEnabled"
    static let backgroundUploadEnabled = "backgroundUploadEnabled"
    static let transformationsEnabled = "transformationsEnabled"
    static let keepTransformModelLoaded = "keepTransformModelLoaded"
    static let enabledTransformations = "enabledTransformations"
    static let hasCompletedSetup = "hasCompletedSetup"
    static let fastModeEnabled = "fastModeEnabled"
    static let adaptiveVADEnabled = "adaptiveVADEnabled"
    static let selectedWhisperKitModel = "selectedWhisperKitModel"
}

// MARK: - AI Model Options
// rawValue must match Python's AVAILABLE_MODELS keys exactly
enum TranscriptionModel: String, CaseIterable, Identifiable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case large = "large-v3"  // Python uses "large-v3" not "large"
    case largeTurbo = "large-v3-turbo"
    case distilSmallEn = "distil-small.en"
    case distilMediumEn = "distil-medium.en"
    case distilLargeV3 = "distil-large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (Fastest)"
        case .base: return "Base (Fast)"
        case .small: return "Small (Balanced)"
        case .medium: return "Medium (Better)"
        case .large: return "Large (Best Quality)"
        case .largeTurbo: return "Large Turbo (Fast + Accurate)"
        case .distilSmallEn: return "Distil Small (English)"
        case .distilMediumEn: return "Distil Medium (English)"
        case .distilLargeV3: return "Distil Large (English)"
        }
    }

    var description: String {
        switch self {
        case .tiny: return "~1GB RAM, fastest transcription"
        case .base: return "~1GB RAM, fast with good accuracy"
        case .small: return "~2GB RAM, good balance of speed and accuracy"
        case .medium: return "~5GB RAM, better accuracy"
        case .large: return "~10GB RAM, highest accuracy"
        case .largeTurbo: return "~4GB RAM, near-best accuracy, much faster than large"
        case .distilSmallEn: return "~1GB RAM, fast English-only"
        case .distilMediumEn: return "~2GB RAM, balanced English-only"
        case .distilLargeV3: return "~4GB RAM, best English-only"
        }
    }

    var sizeMB: Int {
        switch self {
        case .tiny: return 75
        case .base: return 145
        case .small: return 488
        case .medium: return 1500
        case .large: return 3000
        case .largeTurbo: return 1600
        case .distilSmallEn: return 330
        case .distilMediumEn: return 750
        case .distilLargeV3: return 1400
        }
    }

    var formattedSize: String {
        if sizeMB >= 1000 {
            return String(format: "%.1f GB", Double(sizeMB) / 1000.0)
        }
        return "\(sizeMB) MB"
    }
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

    // How long to wait after speech stops before ending recording (in seconds)
    @Published var silenceDuration: Double {
        didSet { UserDefaults.standard.set(silenceDuration, forKey: SettingsKey.silenceDuration) }
    }

    // Whether to enforce a 60-second maximum recording time
    // When false, recording continues until you stop it or silence is detected
    @Published var timeoutEnabled: Bool {
        didSet { UserDefaults.standard.set(timeoutEnabled, forKey: SettingsKey.timeoutEnabled) }
    }

    // Whether upload transcription runs in the background (allows recording during upload)
    // When false (default), uploading blocks recording until it finishes
    @Published var backgroundUploadEnabled: Bool {
        didSet { UserDefaults.standard.set(backgroundUploadEnabled, forKey: SettingsKey.backgroundUploadEnabled) }
    }

    // Whether text transformations are enabled
    @Published var transformationsEnabled: Bool {
        didSet { UserDefaults.standard.set(transformationsEnabled, forKey: SettingsKey.transformationsEnabled) }
    }

    // Whether to keep the transform LLM loaded in memory (uses ~800MB RAM)
    @Published var keepTransformModelLoaded: Bool {
        didSet { UserDefaults.standard.set(keepTransformModelLoaded, forKey: SettingsKey.keepTransformModelLoaded) }
    }

    // Which transformation types to show in the UI
    @Published var enabledTransformations: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledTransformations), forKey: SettingsKey.enabledTransformations) }
    }

    // Whether the user has completed the first-launch setup
    @Published var hasCompletedSetup: Bool {
        didSet { UserDefaults.standard.set(hasCompletedSetup, forKey: SettingsKey.hasCompletedSetup) }
    }

    // Whether fast transcription mode is enabled (beam_size=1 instead of 5)
    @Published var fastModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(fastModeEnabled, forKey: SettingsKey.fastModeEnabled)
            syncFastModeToServer()
        }
    }

    // Whether adaptive VAD is enabled (auto-calibrates silence threshold for 200ms at recording start)
    @Published var adaptiveVADEnabled: Bool {
        didSet { UserDefaults.standard.set(adaptiveVADEnabled, forKey: SettingsKey.adaptiveVADEnabled) }
    }

    private static let fwToWhisperKitNames: [String: String] = [
        "tiny": "openai_whisper-tiny",
        "base": "openai_whisper-base",
        "small": "openai_whisper-small",
        "medium": "openai_whisper-medium",
        "large-v3": "openai_whisper-large-v3",
        "large-v3-turbo": "openai_whisper-large-v3-turbo",
        "distil-small.en": "distil-whisper_distil-small.en",
        "distil-medium.en": "distil-whisper_distil-medium.en",
        "distil-large-v3": "distil-whisper_distil-large-v3"
    ]

    var selectedWhisperKitModel: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: SettingsKey.selectedWhisperKitModel) {
                return saved
            }
            // Migrate from old FasterWhisper name
            if let oldName = UserDefaults.standard.string(forKey: SettingsKey.selectedModel),
               let migrated = Self.fwToWhisperKitNames[oldName] {
                UserDefaults.standard.set(migrated, forKey: SettingsKey.selectedWhisperKitModel)
                return migrated
            }
            return "openai_whisper-small"
        }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.selectedWhisperKitModel) }
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

        // Load silence duration setting (default: 30 seconds)
        if let savedDuration = UserDefaults.standard.object(forKey: SettingsKey.silenceDuration) as? Double {
            self.silenceDuration = savedDuration
        } else {
            self.silenceDuration = 30.0
        }

        // Load timeout enabled setting (default: true - 60 second limit enabled)
        if UserDefaults.standard.object(forKey: SettingsKey.timeoutEnabled) != nil {
            self.timeoutEnabled = UserDefaults.standard.bool(forKey: SettingsKey.timeoutEnabled)
        } else {
            self.timeoutEnabled = true
        }

        // Load background upload setting (default: false - blocking mode)
        if UserDefaults.standard.object(forKey: SettingsKey.backgroundUploadEnabled) != nil {
            self.backgroundUploadEnabled = UserDefaults.standard.bool(forKey: SettingsKey.backgroundUploadEnabled)
        } else {
            self.backgroundUploadEnabled = Config.defaultBackgroundUpload
        }

        // Load transformations enabled (default: true)
        if UserDefaults.standard.object(forKey: SettingsKey.transformationsEnabled) != nil {
            self.transformationsEnabled = UserDefaults.standard.bool(forKey: SettingsKey.transformationsEnabled)
        } else {
            self.transformationsEnabled = true
        }

        // Load keep transform model loaded (default: false)
        if UserDefaults.standard.object(forKey: SettingsKey.keepTransformModelLoaded) != nil {
            self.keepTransformModelLoaded = UserDefaults.standard.bool(forKey: SettingsKey.keepTransformModelLoaded)
        } else {
            self.keepTransformModelLoaded = false
        }

        // Load enabled transformations (default: all 5)
        let allTypes = Set(TransformationType.allCases.map(\.rawValue))
        if let saved = UserDefaults.standard.stringArray(forKey: SettingsKey.enabledTransformations) {
            self.enabledTransformations = Set(saved)
        } else {
            self.enabledTransformations = allTypes
        }

        // Load setup completion flag (default: false)
        self.hasCompletedSetup = UserDefaults.standard.bool(forKey: SettingsKey.hasCompletedSetup)

        // Load fast mode setting (default: false)
        self.fastModeEnabled = UserDefaults.standard.bool(forKey: SettingsKey.fastModeEnabled)

        // Load adaptive VAD setting (default: false)
        self.adaptiveVADEnabled = UserDefaults.standard.bool(forKey: SettingsKey.adaptiveVADEnabled)
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
        silenceDuration = 30.0
        timeoutEnabled = true
        backgroundUploadEnabled = Config.defaultBackgroundUpload
        transformationsEnabled = true
        keepTransformModelLoaded = false
        enabledTransformations = Set(TransformationType.allCases.map(\.rawValue))
        fastModeEnabled = false
        adaptiveVADEnabled = false
    }

    func syncFastModeToServer() {
        // No-op: WhisperKit reads fastModeEnabled directly from SettingsManager
    }
}
