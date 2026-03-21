//
//  TransformationState.swift
//  Rayee
//
//  Holds UI state for text transformations.
//  No networking — just tracks what the UI needs to show.
//

import Foundation

/// Available transformation types (must match Python's AVAILABLE_TRANSFORMATIONS)
enum TransformationType: String, CaseIterable, Identifiable {
    case grammar
    case bullets
    case rephrase
    case formal
    case casual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grammar: return "Grammar"
        case .bullets: return "Bullets"
        case .rephrase: return "Rephrase"
        case .formal: return "Formal"
        case .casual: return "Casual"
        }
    }

    var icon: String {
        switch self {
        case .grammar: return "textformat.abc"
        case .bullets: return "list.bullet"
        case .rephrase: return "arrow.triangle.2.circlepath"
        case .formal: return "briefcase"
        case .casual: return "face.smiling"
        }
    }

    /// Keyboard shortcut number (1-5)
    var shortcutNumber: Int {
        switch self {
        case .grammar: return 1
        case .bullets: return 2
        case .rephrase: return 3
        case .formal: return 4
        case .casual: return 5
        }
    }
}

/// UI state for the transformation flow
class TransformationState: ObservableObject {
    /// Whether a transformation is currently in progress
    @Published var isTransforming = false

    /// The original text before transformation
    @Published var previewOriginal = ""

    /// The transformed text result
    @Published var previewTransformed = ""

    /// Which transformation is currently active
    @Published var activeType: TransformationType?

    /// Error message if transformation fails
    @Published var error: String?

    /// Streaming text accumulated token by token during transformation
    @Published var streamingText: String = ""

    /// Whether to show the preview (original vs transformed)
    @Published var showPreview = false

    /// Whether any transformation UI is active (loading, preview, or error)
    var isActive: Bool {
        isTransforming || showPreview || error != nil
    }

    /// Reset all state
    func reset() {
        isTransforming = false
        previewOriginal = ""
        previewTransformed = ""
        activeType = nil
        error = nil
        showPreview = false
        streamingText = ""
    }

    /// Start a transformation
    func startTransformation(text: String, type: TransformationType) {
        previewOriginal = text
        activeType = type
        isTransforming = true
        error = nil
        showPreview = false
        streamingText = ""
    }

    /// Append a streaming token to the accumulated streaming text
    func appendStreamingToken(_ token: String) {
        streamingText += token
    }

    /// Complete a transformation with the result
    func completeTransformation(transformedText: String) {
        previewTransformed = transformedText
        isTransforming = false
        showPreview = true
    }

    /// Fail a transformation with an error
    func failTransformation(message: String) {
        error = message
        isTransforming = false
        activeType = nil
    }
}
