//
//  VocabularySettingsTab.swift
//  Rayee
//
//  Settings tab for managing custom vocabulary words.
//  Extracted from SettingsView to follow the same pattern as GeneralSettingsTab.
//

import SwiftUI

struct VocabularySettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var newVocabularyWord = ""

    var body: some View {
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

    // MARK: - Helper Methods

    private func addWord() {
        settings.addVocabularyWord(newVocabularyWord)
        newVocabularyWord = ""
    }
}

#Preview {
    VocabularySettingsTab()
        .frame(width: 540, height: 420)
}
