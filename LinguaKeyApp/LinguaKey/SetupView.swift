import SwiftUI
import UniformTypeIdentifiers
import StudyKit
import StudySystem

/// The two things that can be broken on this device, plus the export button.
///
/// The export button is here because of the 7-day expiry: every seventh day the
/// build dies and has to be reinstalled from Xcode, and the log in the App Group
/// survives that only if the app is not deleted first. The log is the only thing
/// in this project worth more than the build.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            List {
                Section("Language") {
                    LabeledContent("Spanish to English", value: model.packStatus)
                    PackDownloadButton { await model.refreshTranslator() }
                    Text("""
                        Word meanings work with no pack and no network. The pack \
                        only adds the whole-sentence translation.
                        """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Data") {
                    LabeledContent("Tables",
                                   value: SetupView.megabytes(model.stagedByteCount))
                    LabeledContent("Staging",
                                   value: model.stagingOutcome?.rawValue ?? "not run")
                    LabeledContent("Event log", value: SetupView.megabytes(model.logByteCount))
                    LabeledContent("Events", value: "\(model.store.eventCount)")
                    LabeledContent("Loaded by", value: model.loadOutcome?.rawValue ?? "not loaded")
                    if model.skippedLines > 0 {
                        LabeledContent("Skipped lines", value: "\(model.skippedLines)")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Export the event log") { exporting = true }
                    Button("Rebuild from the log") { model.reload() }
                } footer: {
                    Text("""
                        This build expires 7 days after it is installed. Reinstall it \
                        from Xcode before then. Do NOT delete the app to reinstall it: \
                        deleting it destroys the App Group container and every event in \
                        it. Export first if you are unsure.
                        """)
                }
            }
            .navigationTitle("Setup")
            .fileExporter(isPresented: $exporting,
                          document: EventLogDocument(url: model.storage?.eventLog),
                          contentType: .json,
                          defaultFilename: "linguakey-events") { _ in }
        }
    }

    static func megabytes(_ bytes: Int) -> String {
        bytes == 0 ? "none" : String(format: "%.2f MB", Double(bytes) / 1_048_576)
    }
}

/// Exports the raw log, not a summary. Anything that reshapes it on the way out
/// is a second implementation of the fold and will disagree with the first one.
struct EventLogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    private let data: Data

    init(url: URL?) {
        data = url.flatMap { try? Data(contentsOf: $0) } ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
