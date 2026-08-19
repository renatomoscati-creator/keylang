import SwiftUI
import StudyKit
import LinguaKeyCore

/// One focus, presented the way its arm says.
///
/// Arm C never reaches this view: `StudySession.taught` filters it out, so there
/// is no code path where the control arm renders a card and no way to break that
/// by editing a condition here.
public struct FocusCardView: View {

    public enum Outcome: Sendable {
        case graded(Grade)
        case revealed
    }

    private let focus: StudySession.Focus
    private let onOutcome: (Outcome) -> Void

    @State private var revealed = false

    public init(focus: StudySession.Focus, onOutcome: @escaping (Outcome) -> Void) {
        self.focus = focus
        self.onOutcome = onOutcome
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch focus.arm {
            case .recognition: recognition
            case .retrieval: retrieval
            case .control: EmptyView()
            }
        }
        .studyCard()
    }

    // MARK: - Arm A

    private var recognition: some View {
        VStack(alignment: .leading, spacing: 8) {
            headline
            answer
        }
    }

    // MARK: - Arm B

    /// Reveal is on tap, never on a timer.
    ///
    /// G3 in CONTEXT, decided here: a timer measures reading speed as much as
    /// retrieval, and it takes the decision to stop trying away from the learner.
    /// A tap is the learner saying they are done retrieving, which is exactly the
    /// moment the answer is worth the most.
    @ViewBuilder
    private var retrieval: some View {
        if revealed {
            VStack(alignment: .leading, spacing: 12) {
                answer
                Text("Did you know it?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    grade(.again, "No")
                    grade(.hard, "Barely")
                    grade(.good, "Yes")
                    grade(.easy, "Easily")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(focus.candidate.kind == .grammar
                     ? "What form is \(focus.candidate.surface)?"
                     : "What does \(focus.candidate.surface) mean?")
                    .font(.headline)
                Button("Show me") {
                    revealed = true
                    onOutcome(.revealed)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Pieces

    private var headline: some View {
        HStack(spacing: 6) {
            Text(focus.candidate.surface).font(.headline)
            if focus.candidate.trap != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("False friend")
            }
        }
    }

    @ViewBuilder
    private var answer: some View {
        if let trap = focus.candidate.trap {
            // The curated list is the authority on traps, and it is the only
            // thing here allowed to say a word is one.
            Text(trap.explanation).font(.body)
        } else if focus.candidate.kind == .grammar {
            Text(FocusCardView.readable(focus.candidate.feats)).font(.body)
            Text(focus.candidate.lemma).font(.footnote).foregroundStyle(.secondary)
        } else {
            Text(focus.candidate.gloss.isEmpty ? focus.candidate.lemma
                                               : focus.candidate.gloss)
                .font(.body)
            if focus.candidate.lemma != focus.candidate.surface {
                Text("from \(focus.candidate.lemma)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func grade(_ grade: Grade, _ label: String) -> some View {
        Button(label) { onOutcome(.graded(grade)) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    /// UniMorph tags are not a sentence. `V;IND;FUT;1;SG` is not something to put
    /// in front of a learner.
    static func readable(_ feats: String) -> String {
        let names: [String: String] = [
            "IND": "indicative", "SBJV": "subjunctive", "IMP": "imperative",
            "COND": "conditional", "FUT": "future", "PST": "past",
            "PRS": "present", "IPFV": "imperfect", "PFV": "preterite",
            "NFIN": "infinitive", "V.PTCP": "participle", "V.CVB": "gerund",
            "1": "first person", "2": "second person", "3": "third person",
            "SG": "singular", "PL": "plural",
            "MASC": "masculine", "FEM": "feminine",
        ]
        let tags = feats.split(separator: ";").dropFirst().map(String.init)
        let words = tags.compactMap { names[$0] }
        return words.isEmpty ? feats : words.joined(separator: ", ")
    }
}
