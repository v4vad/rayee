//
//  RecorderState.swift
//  Rayee
//
//  What the recorder shows, how tall each state is, and what Esc, clicks and a finished
//  transcript do. Pure values and functions, so they can be tested.
//

import Foundation
import CoreGraphics

/// The one button an error can offer.
enum RecorderErrorAction: Equatable {
    case openMicrophoneSettings

    var label: String {
        switch self {
        case .openMicrophoneSettings: return "Open Settings"
        }
    }

    var settingsURL: URL {
        switch self {
        case .openMicrophoneSettings: return SystemSettingsLink.microphone
        }
    }
}

/// What the recorder is showing right now.
enum RecorderPhase: Equatable {
    case hidden
    case listening
    case transcribing
    case cleaningUp
    case pasted
    /// Nowhere to paste: show the text with a Copy button
    case result(text: String)
    case error(message: String, action: RecorderErrorAction?)

    /// Seconds until the recorder closes by itself, or nil to stay open.
    var autoDismissDelay: TimeInterval? {
        switch self {
        case .pasted: return 0.8
        case .result: return 20
        case .error: return 8
        case .hidden, .listening, .transcribing, .cleaningUp: return nil
        }
    }

    /// Hovering keeps states with something to read open. "Pasted" always closes on time.
    var hoverPausesDismiss: Bool {
        switch self {
        case .result, .error: return true
        default: return false
        }
    }

    /// Only the Result takes the keyboard (Return copies). Otherwise focus stays with the user's app.
    var takesKeyboardFocus: Bool {
        if case .result = self { return true }
        return false
    }
}

/// What a key press or click asks for.
enum RecorderCommand: Equatable {
    case none
    case stopRecording
    case cancelRecording
    case skipCleanup
    case dismiss
}

enum RecorderLayout {
    static let compactHeight: CGFloat = 44
    static let lineHeight: CGFloat = 18
    static let charsPerLine = 36
    static let maxResultLines = 4
    static let maxErrorLines = 4
    static let maxLiveLines = 3
    /// Gap below the live words, above the bottom edge
    private static let liveTextPadding: CGFloat = 12
    /// Padding above and below the text plus the button row (16 + 8 + 32 + 12)
    private static let textWithButtons: CGFloat = 68
    /// Padding above and below the text alone (16 + 16)
    private static let textOnly: CGFloat = 32
    /// The tallest any state gets; the window is sized for this.
    static let maxBodyHeight: CGFloat = textWithButtons + lineHeight * CGFloat(maxResultLines)

    /// A rough line count for a 300 pt wide body, without measuring text.
    static func estimatedLines(_ text: String, max: Int) -> Int {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { total, line in
            total + Swift.max(1, Int((Double(line.count) / Double(charsPerLine)).rounded(.up)))
        }
        return Swift.min(Swift.max(lines, 1), max)
    }

    /// Never fewer lines than `previous`, so the recorder grows while recording and doesn't shrink.
    static func liveLines(previous: Int, transcript: LiveTranscript) -> Int {
        if transcript.isEmpty { return previous }
        return Swift.max(previous, estimatedLines(transcript.text, max: maxLiveLines))
    }

    /// Height of the body below the menu bar for a state.
    static func bodyHeight(for phase: RecorderPhase, liveLines: Int = 0) -> CGFloat {
        switch phase {
        case .hidden:
            return 0
        case .listening where liveLines > 0:
            return compactHeight + lineHeight * CGFloat(Swift.min(liveLines, maxLiveLines)) + liveTextPadding
        case .listening, .transcribing, .cleaningUp, .pasted:
            return compactHeight
        case .result(let text):
            return textWithButtons + lineHeight * CGFloat(estimatedLines(text, max: maxResultLines))
        case .error(let message, let action):
            let padding = action == nil ? textOnly : textWithButtons
            return padding + lineHeight * CGFloat(estimatedLines(message, max: maxErrorLines))
        }
    }
}

enum RecorderRules {
    /// Live words show only while the microphone is open.
    static func acceptsLiveTranscript(in phase: RecorderPhase) -> Bool {
        if case .listening = phase { return true }
        return false
    }

    static func escape(in phase: RecorderPhase) -> RecorderCommand {
        switch phase {
        case .listening: return .cancelRecording
        case .cleaningUp: return .skipCleanup
        case .result, .error: return .dismiss
        case .hidden, .transcribing, .pasted: return .none
        }
    }

    static func click(in phase: RecorderPhase) -> RecorderCommand {
        switch phase {
        case .listening: return .stopRecording
        case .cleaningUp: return .skipCleanup
        default: return .none
        }
    }

    /// What to show once the transcript is ready.
    static func afterTranscription(text: String, didPaste: Bool, smartDictationWillRun: Bool) -> RecorderPhase {
        if text.isEmpty { return .hidden }
        if smartDictationWillRun { return .cleaningUp }
        return didPaste ? .pasted : .result(text: text)
    }

    /// When Smart Dictation finishes, fails or is skipped (`cleaned` is nil for the last two):
    /// the text to paste (if any) and what to show.
    static func afterCleanup(raw: String, cleaned: String?, canPaste: Bool) -> (phase: RecorderPhase, pasteText: String?) {
        let text = cleaned ?? raw
        return canPaste ? (.pasted, text) : (.result(text: text), nil)
    }

    /// Paste only when the user asked (hotkey or menu), the setting is on, there's text,
    /// an app that can take it, and permission to send ⌘V.
    static func canPaste(requested: Bool, enabled: Bool, text: String, hasTarget: Bool, hasAccessibility: Bool) -> Bool {
        requested && enabled && !text.isEmpty && hasTarget && hasAccessibility
    }
}
