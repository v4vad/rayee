//
//  AppleTransformEngine.swift
//  Rayee
//
//  Runs text transforms on Apple's built-in on-device model (FoundationModels).
//

import Foundation
import FoundationModels

// MARK: - Availability

/// Whether Apple's built-in model can be used right now. The one place that checks.
enum AppleIntelligence {
    static var isAvailable: Bool {
        if #available(macOS 26, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
    }

    /// Short advice for the Settings picker when the model can't be used, or nil when it can.
    static var unavailableNote: String? {
        guard #available(macOS 26, *) else { return "Needs macOS 26 or later" }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings"
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence"
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still getting ready"
        default:
            return "Apple Intelligence isn't available"
        }
    }
}

// MARK: - Engine

@available(macOS 26, *)
enum AppleTransformEngine {

    /// The session's earlier turns plus the prompt to send last: the system prompt as instructions,
    /// then a prompt/response pair per worked example. Shared by the app and the model eval.
    static func makeTranscript(
        text: String, type transformType: TransformationType
    ) -> (transcript: Transcript, prompt: String) {
        let (system, user) = MLXTransformManager.buildPrompt(text: text, type: transformType)
        func segments(_ content: String) -> [Transcript.Segment] {
            [.text(.init(content: content))]
        }

        var entries: [Transcript.Entry] = [
            .instructions(.init(segments: segments(system), toolDefinitions: []))
        ]
        for example in MLXTransformManager.fewShotExamples(for: transformType) {
            let input = "<dictation>\(example.input)</dictation>" + MLXTransformManager.smartDictationReminder
            entries.append(.prompt(.init(segments: segments(input))))
            entries.append(.response(.init(assetIDs: [], segments: segments(example.output))))
        }
        return (Transcript(entries: entries), user)
    }

    /// Part of `current` that goes beyond `previous`. Streamed snapshots are the whole text so far.
    /// A snapshot that doesn't start with the previous one gives nothing for that step.
    /// Compared by unicode scalars, not characters: a snapshot can end in the middle of a
    /// character (an emoji skin tone, a Devanagari conjunct), which `hasPrefix` would reject.
    nonisolated static func delta(previous: String, current: String) -> String {
        let old = previous.unicodeScalars
        let new = current.unicodeScalars
        guard new.starts(with: old) else { return "" }
        return String(String.UnicodeScalarView(new.dropFirst(old.count)))
    }

    /// Loads Apple's model ahead of the first transform so it answers sooner.
    static func prewarm() {
        guard AppleIntelligence.isAvailable else { return }
        let (transcript, _) = makeTranscript(text: "", type: .smartDictation)
        LanguageModelSession(model: .default, transcript: transcript).prewarm()
    }

    /// Streams the transformed text to `onToken` as new pieces. Uses a fresh session per call.
    /// Returns the final full text, which is authoritative: the streamed pieces can miss part of it.
    /// Throws what FoundationModels throws (for example a guardrail refusal) and `CancellationError`.
    @MainActor
    static func stream(
        text: String,
        type transformType: TransformationType,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let (transcript, prompt) = makeTranscript(text: text, type: transformType)
        let session = LanguageModelSession(model: .default, transcript: transcript)
        let options = GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: MLXTransformManager.maxOutputTokens(for: text))

        var emitted = ""
        var latest = ""
        for try await snapshot in session.streamResponse(to: prompt, options: options) {
            try Task.checkCancellation()
            latest = snapshot.content
            let piece = delta(previous: emitted, current: latest)
            if !piece.isEmpty {
                emitted += piece
                onToken(piece)
            }
        }
        if emitted != latest {
            AppLogger.log("AppleTransformEngine: final text differs from streamed text", category: "mlx")
        }
        try Task.checkCancellation()
        return latest
    }
}
