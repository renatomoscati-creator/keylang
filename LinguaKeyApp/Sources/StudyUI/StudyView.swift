import SwiftUI
import StudyKit
import LinguaKeyCore

/// The whole study surface: one sentence, its translation if there is one, and
/// at most one vocabulary card and one grammar card.
///
/// Lives in the package rather than in either target because the app and the
/// share extension are different processes, and two copies of this drift within
/// a week.
public struct StudyView: View {

    private let session: StudySession
    private let translator: any Translator
    private let store: ItemStore
    private let onEvents: ([Event]) -> Void
    private let onDone: (() -> Void)?

    @State private var translation: String?
    @State private var translationProblem: String?
    @State private var presented = false
    @State private var handled: Set<String> = []

    public init(session: StudySession, translator: any Translator, store: ItemStore,
                onEvents: @escaping ([Event]) -> Void, onDone: (() -> Void)? = nil) {
        self.session = session
        self.translator = translator
        self.store = store
        self.onEvents = onEvents
        self.onDone = onDone
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gutter) {
                SentenceView(sentence: session.sentence, marked: markedSurfaces)

                translationBlock

                ForEach(session.taught, id: \.candidate.key) { focus in
                    if !handled.contains(focus.candidate.key) {
                        FocusCardView(focus: focus) { outcome in
                            record(focus, outcome)
                        }
                    }
                }

                if session.taught.isEmpty {
                    // Section 25 of the PRD asks for the teaching UI to disappear
                    // when it has nothing useful to say, and this is that. It is
                    // also what the control arm sees, which is why it is worded as
                    // a normal state and not as a failure.
                    Text("Nothing new here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let onDone {
                    Button("Done", action: onDone)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.gutter)
        }
        .task { await start() }
    }

    private var markedSurfaces: Set<String> {
        Set(session.taught.map(\.candidate.surface))
    }

    @ViewBuilder
    private var translationBlock: some View {
        if let translation {
            Text(translation)
                .font(.body)
                .foregroundStyle(.secondary)
                .studyCard()
        } else if let translationProblem {
            // One line, not an error screen. Word-level teaching runs entirely
            // offline, so a missing pack costs the sentence translation and
            // nothing else. An app that shows an error the first time it is
            // opened is an app that never gets opened again.
            Label(translationProblem, systemImage: "arrow.down.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    @MainActor
    private func start() async {
        if !presented {
            presented = true
            // Written as one batch, so a kill mid-session leaves either all of
            // these events or none of them.
            onEvents(session.presentationEvents(store: store))
        }
        guard translator.isAvailable else {
            translationProblem = "No Spanish pack yet. Open LinguaKey to download it."
            return
        }
        do {
            translation = try await translator.translate(session.sentence)
        } catch {
            translationProblem = "\(error)"
        }
    }

    @MainActor
    private func record(_ focus: StudySession.Focus, _ outcome: FocusCardView.Outcome) {
        let now = Date().timeIntervalSince1970
        switch outcome {
        case .graded(let grade):
            onEvents([session.answerEvent(focus, grade: grade, at: now, store: store)])
            handled.insert(focus.candidate.key)
        case .revealed:
            onEvents([session.revealEvent(focus, at: now, store: store)])
        }
    }
}
