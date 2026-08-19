import SwiftUI
import StudyKit
import StudyUI

/// Paste some Spanish and study it, without going through the share sheet.
///
/// Not a fourth screen: it is how the study surface gets exercised on device
/// without wrestling a host app into offering the extension, and it is the only
/// way to reproduce a specific sentence when something in the selector looks
/// wrong. It runs the identical `StudySession`, so anything it shows is what the
/// share extension would have shown.
struct PasteStudyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var session: StudySession?

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    StudyView(session: session, translator: model.translator,
                              store: model.store,
                              onEvents: { model.record($0) },
                              onDone: { dismiss() })
                } else {
                    input
                }
            }
            .navigationTitle(session == nil ? "Study some text" : "Study")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: Theme.gutter) {
            TextEditor(text: $text)
                .font(.title3)
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .stroke(.quaternary))
            Button("Study this") { start() }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || model.selector == nil)
            Spacer()
        }
        .padding(Theme.gutter)
    }

    private func start() {
        guard let selector = model.selector else { return }
        session = StudySession(sentence: text, selector: selector, store: model.store,
                               assignment: model.assignment,
                               now: Date().timeIntervalSince1970,
                               sourceApp: "app.paste")
    }
}
