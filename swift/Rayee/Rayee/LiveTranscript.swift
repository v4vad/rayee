//
//  LiveTranscript.swift
//  Rayee
//
//  The words shown in the recorder while the user speaks: settled words that won't change,
//  and a draft that the recognizer keeps rewriting. Pure values, so they can be tested.
//

import Foundation

struct LiveTranscript: Equatable {
    /// Words the recognizer has finished with
    private(set) var settled = ""
    /// Words still being decided; replaced on every update
    private(set) var draft = ""

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var text: String { settled + draft }

    /// A final result is settled; a draft result replaces the previous draft.
    mutating func apply(_ text: String, isFinal: Bool) {
        if isFinal {
            settled += text
            draft = ""
        } else {
            draft = text
        }
    }

    /// The end of the text, cut at a word boundary, split back into settled and draft parts.
    func visibleTail(maxCharacters: Int) -> (settled: String, draft: String) {
        guard text.count > maxCharacters else { return (settled, draft) }
        var start = text.index(text.endIndex, offsetBy: -maxCharacters)
        if let space = text[start...].firstIndex(of: " ") {
            start = text.index(after: space)
        }
        let offset = text.distance(from: text.startIndex, to: start)
        if offset >= settled.count {
            return ("", String(draft.dropFirst(offset - settled.count)))
        }
        let tailSettled = String(settled.dropFirst(offset)).drop { $0.isWhitespace }
        return (String(tailSettled), draft)
    }
}
