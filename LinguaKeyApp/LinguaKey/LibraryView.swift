import SwiftUI
import StudyKit
import LinguaKeyCore

/// Every item, its state and its arm.
///
/// This screen exists to debug the experiment, not to motivate the learner. If
/// it ever grows a streak counter it has been misunderstood.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var sort: Sort = .weakest
    @State private var armFilter: Arm?
    @State private var now = Date().timeIntervalSince1970

    enum Sort: String, CaseIterable, Identifiable {
        case weakest = "Weakest"
        case strongest = "Strongest"
        case mostSeen = "Most seen"
        case key = "Name"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items, id: \.key) { item in
                    ItemRow(item: item, now: now, arm: model.assignment.arm(for: item.key))
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Divider()
                        Picker("Arm", selection: $armFilter) {
                            Text("All arms").tag(Arm?.none)
                            ForEach(Arm.allCases, id: \.self) { arm in
                                Text("Arm \(arm.rawValue)").tag(Arm?.some(arm))
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable {
                model.reload()
                now = Date().timeIntervalSince1970
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing yet",
                        systemImage: "text.book.closed",
                        description: Text("Share some Spanish into LinguaKey to start."))
                }
            }
        }
    }

    private var items: [Item] {
        let all = model.store.items.values.filter { item in
            armFilter.map { model.assignment.arm(for: item.key) == $0 } ?? true
        }
        switch sort {
        case .weakest:
            return all.sorted { $0.production.retrievability(now: now)
                              < $1.production.retrievability(now: now) }
        case .strongest:
            return all.sorted { $0.production.retrievability(now: now)
                              > $1.production.retrievability(now: now) }
        case .mostSeen:
            return all.sorted { $0.recognition.exposures > $1.recognition.exposures }
        case .key:
            return all.sorted { $0.key < $1.key }
        }
    }
}
