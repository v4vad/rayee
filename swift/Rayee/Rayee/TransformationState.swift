//
//  TransformationState.swift
//  Rayee
//
//  Holds UI state for text transformations.
//  No networking — just tracks what the UI needs to show.
//

import Foundation

/// Available transformation types. Prompts for each live in MLXTransformManager.buildPrompt.
enum TransformationType: String, CaseIterable, Identifiable {
    case grammar
    case bullets
    case rephrase
    case formal
    case casual
    case smartDictation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grammar: return "Grammar"
        case .bullets: return "Bullets"
        case .rephrase: return "Rephrase"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .smartDictation: return "Smart Dictation"
        }
    }

    var icon: String {
        switch self {
        case .grammar: return "checkmark.circle"
        case .bullets: return "list.bullet"
        case .rephrase: return "arrow.triangle.2.circlepath"
        case .formal: return "briefcase"
        case .casual: return "bubble.left"
        case .smartDictation: return "wand.and.sparkles"
        }
    }

    /// Keyboard shortcut number (1-5). smartDictation is not a manual button so uses 0.
    var shortcutNumber: Int {
        switch self {
        case .grammar: return 1
        case .bullets: return 2
        case .rephrase: return 3
        case .formal: return 4
        case .casual: return 5
        case .smartDictation: return 0
        }
    }
}
