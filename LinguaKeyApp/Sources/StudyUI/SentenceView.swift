import SwiftUI
import StudyKit
import LinguaKeyCore

/// The user's own sentence, with the taught words marked.
///
/// In the control arm nothing is marked, which is the point: the sentence is
/// identical, only the teaching is withheld.
public struct SentenceView: View {

    private let sentence: String
    private let marked: Set<String>

    public init(sentence: String, marked: Set<String>) {
        self.sentence = sentence
        self.marked = Set(marked.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
    }

    public var body: some View {
        Text(attributed)
            .font(.title3)
            .textSelection(.enabled)
    }

    /// Split on non-letters and rebuild, so punctuation and spacing survive.
    /// Rebuilding from tokens alone would quietly rewrite the user's text.
    private var attributed: AttributedString {
        var out = AttributedString()
        let source = sentence.precomposedStringWithCanonicalMapping
        var run = ""
        var runIsWord = false

        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            if runIsWord && marked.contains(run.lowercased()) {
                piece.underlineStyle = .single
                piece.foregroundColor = Theme.focusTint
            }
            out.append(piece)
            run = ""
        }

        for character in source {
            let isWord = character.isLetter
            if isWord != runIsWord { flush(); runIsWord = isWord }
            run.append(character)
        }
        flush()
        return out
    }
}
