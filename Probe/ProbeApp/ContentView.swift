import SwiftUI
import Translation

/// Host app. Two jobs only:
///   1. Download the en->es and it->es language packs. Only a session created
///      through `.translationTask` can request downloads; the headless
///      `init(installedSource:target:)` the keyboard uses cannot. Packs land in
///      a system-wide store shared with every app on the device, which is the
///      fact the whole architecture rests on.
///   2. Read back the log the keyboard wrote.
struct ContentView: View {

    @State private var config: TranslationSession.Configuration?
    @State private var pending: (source: String, target: String)?
    @State private var status = "idle"
    @State private var log = ""

    private let en = Locale.Language(identifier: "en")
    private let it = Locale.Language(identifier: "it")
    private let es = Locale.Language(identifier: "es")

    var body: some View {
        NavigationStack {
            List {
                Section("1. Language packs") {
                    Button("Prepare en -> es") { prepare(en, es, "en_es") }
                    Button("Prepare it -> es") { prepare(it, es, "it_es") }
                    Button("Check availability (P1 + P3)") { Task { await checkAvailability() } }
                    LabeledContent("status", value: status)
                }

                Section("2. Container") {
                    LabeledContent("kind", value: ProbeLog.containerKind)
                    LabeledContent("group", value: ProbeLog.appGroupID ?? "none")
                    Text(ProbeLog.logURL.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Section("3. Probe log") {
                    Button("Refresh") { log = ProbeLog.read() }
                    Button("Reset log", role: .destructive) {
                        ProbeLog.reset(); log = ""
                    }
                    ShareLink(item: ProbeLog.logURL) { Text("Export probe-log.txt") }
                    Text(log.isEmpty ? "(tap Refresh)" : log)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("keylang probe")
            // The download prompt only appears from a .translationTask context.
            .translationTask(config) { session in
                do {
                    try await session.prepareTranslation()
                    let tag = pending.map { "\($0.source)_\($0.target)" } ?? "unknown"
                    ProbeLog.write("P1", "pack.prepared.\(tag)", "ok", "host app")
                    status = "prepared \(tag)"
                } catch {
                    ProbeLog.writeError("P1", "pack.prepare", error)
                    status = "prepare failed: \(error)"
                }
            }
            .onAppear { log = ProbeLog.read() }
        }
    }

    private func prepare(_ source: Locale.Language, _ target: Locale.Language, _ tag: String) {
        status = "preparing \(tag)..."
        pending = (source.minimalIdentifier, target.minimalIdentifier)
        // Reassigning the configuration is what re-triggers .translationTask.
        config = TranslationSession.Configuration(source: source, target: target)
    }

    /// P1 and P3 from the host side. The keyboard repeats these; a disagreement
    /// between the two is itself a finding, because it would mean the pack store
    /// is not as system-wide as Apple documents.
    private func checkAvailability() async {
        let availability = LanguageAvailability()

        let enEs = await availability.status(from: en, to: es)
        ProbeLog.write("P1", "availability.en_es", describe(enEs), "host app")

        let itEs = await availability.status(from: it, to: es)
        ProbeLog.write("P3", "availability.it_es", describe(itEs), "host app")

        status = "en->es \(describe(enEs)), it->es \(describe(itEs))"
        log = ProbeLog.read()
    }

    private func describe(_ status: LanguageAvailability.Status) -> String {
        switch status {
        case .installed:   return "installed"
        case .supported:   return "supported"
        case .unsupported: return "unsupported"
        @unknown default:  return "unknown"
        }
    }
}
