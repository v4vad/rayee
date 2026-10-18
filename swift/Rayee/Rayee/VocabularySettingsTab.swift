//
//  VocabularySettingsTab.swift
//  Rayee
//
//  Settings → Dictionary
//

import SwiftUI

struct VocabularySettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var newVocabularyWord = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Add a word or name", text: $newVocabularyWord)
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .disabled(trimmedWord.isEmpty)
                }
            } footer: {
                Text("Words Rayee often gets wrong, like names or technical terms.")
            }

            Section {
                if settings.vocabularyList.isEmpty {
                    Text("No words yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.vocabularyList, id: \.self) { word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button {
                                settings.removeVocabularyWord(word)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Remove")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var trimmedWord: String {
        newVocabularyWord.trimmingCharacters(in: .whitespaces)
    }

    private func addWord() {
        guard !trimmedWord.isEmpty else { return }
        settings.addVocabularyWord(newVocabularyWord)
        newVocabularyWord = ""
    }
}

#Preview {
    VocabularySettingsTab()
        .frame(width: 540, height: 420)
}
