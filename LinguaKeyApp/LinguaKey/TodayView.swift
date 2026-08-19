import SwiftUI
import StudyKit
import LinguaKeyCore

/// What the fold says, and nothing that is not in the log.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var now = Date().timeIntervalSince1970
    @State private var studying = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Items seen", value: "\(model.store.items.count)")
                    LabeledContent("Events", value: "\(model.store.eventCount)")
                    LabeledContent("Due now", value: "\(model.due(now: now).count)")
                } header: {
                    Text("Since you started")
                } footer: {
                    Text("""
                        Share Spanish text from any app into LinguaKey to add to this. \
                        Nothing here is stored as a score: every number is recomputed \
                        from the event log each time you open the app.
                        """)
                }

                Section("Weakest right now") {
                    let due = model.due(now: now)
                    if due.isEmpty {
                        Text("Nothing due.").foregroundStyle(.secondary)
                    }
                    ForEach(due.prefix(20), id: \.key) { item in
                        ItemRow(item: item, now: now, arm: model.assignment.arm(for: item.key))
                    }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Study text", systemImage: "text.viewfinder") { studying = true }
                }
            }
            .sheet(isPresented: $studying) { PasteStudyView() }
            .refreshable {
                model.reload()
                now = Date().timeIntervalSince1970
            }
        }
    }
}

/// One item, showing the two traces separately.
///
/// They are separate because production is the product's stated goal and
/// recognition is what exposure buys. Collapsing them into one bar would hide
/// exactly the thing the experiment is trying to measure.
struct ItemRow: View {
    let item: Item
    let now: TimeInterval
    let arm: Arm

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ItemRow.label(item.key)).font(.body)
                Spacer()
                Text(arm.rawValue)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            HStack(spacing: 12) {
                trace("recognition", item.recognition)
                trace("production", item.production)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func trace(_ name: String, _ value: Trace) -> some View {
        Text("\(name) \(Int(value.retrievability(now: now) * 100))%")
    }

    /// `LEM:vaso|N|0` is a key, not a word.
    static func label(_ key: String) -> String {
        if key.hasPrefix("LEM:") {
            return String(key.dropFirst(4).split(separator: "|").first ?? "")
        }
        if key.hasPrefix("CELL:") {
            return String(key.dropFirst(5)).replacingOccurrences(of: "|", with: " ")
        }
        return key
    }
}
