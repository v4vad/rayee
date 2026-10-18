//
//  TransformationState.swift
//  Rayee
//
//  The text clean-up Rayee runs. Only Smart Dictation is left; its prompt lives in
//  MLXTransformManager.buildPrompt.
//

import Foundation

enum TransformationType: String, CaseIterable, Identifiable {
    case smartDictation

    var id: String { rawValue }
}
