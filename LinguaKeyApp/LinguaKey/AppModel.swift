import Foundation
import Observation
import StudyKit
import StudySystem
import LinguaKeyCore

/// Everything the app holds, in one place.
///
/// Deliberately not a stack of singletons: the share extension is a separate
/// process that builds the same objects from the same App Group, and anything
/// that quietly assumed one instance per device would work in the app and fail
/// in the extension, which is the hardest kind of bug to see on this hardware.
@MainActor
@Observable
public final class AppModel {

    public enum Readiness: Equatable {
        case loading
        case ready
        case noAppGroup
        case noTables(String)
    }

    public private(set) var readiness: Readiness = .loading
    public private(set) var store = ItemStore()
    public private(set) var loadOutcome: ItemStore.LoadOutcome?
    public private(set) var skippedLines = 0
    public private(set) var stagingOutcome: DataStaging.Outcome?
    public private(set) var translator: any Translator = UnavailableTranslator()
    public private(set) var packStatus = "checking"

    public private(set) var storage: Storage?
    public private(set) var log: EventLog?
    public private(set) var selector: FocusSelector?
    public private(set) var assignment = ArmAssignment(salt: "unset")

    public init() {}

    public func start() async {
        guard let storage = Storage.shared() else {
            readiness = .noAppGroup
            return
        }
        self.storage = storage

        stagingOutcome = DataStaging.run(into: storage)

        do {
            try storage.createIfNeeded()
            assignment = try ArmAssignment.load(storage)
            let log = try EventLog(url: storage.eventLog)
            self.log = log

            let tables = try Tables(root: storage.data)
            let interference = try Interference(root: storage.data)
            selector = FocusSelector(tables: tables, interference: interference)

            reload()
            readiness = .ready
        } catch {
            readiness = .noTables("\(error)")
        }
        await refreshTranslator()
    }

    public func reload() {
        guard let log, let storage else { return }
        let result = ItemStore.load(log: log, storage: storage)
        store = result.store
        loadOutcome = result.outcome
        skippedLines = result.skippedLines
        // The snapshot is a startup cache and nothing more. Rewriting it after a
        // rebuild is what keeps the next launch fast; failing to write it costs
        // time and never correctness, so it is not worth surfacing.
        try? store.save(to: storage, logByteCount: result.logByteCount)
    }

    public func record(_ events: [Event]) {
        guard let log, !events.isEmpty else { return }
        do {
            try log.appendAll(events)
            for event in events { store.apply(event) }
        } catch {
            // The log is the only thing here worth more than the build that
            // reads it. A failure to append is worth seeing, not swallowing.
            print("event log append failed: \(error)")
        }
    }

    public func refreshTranslator() async {
        let system = await SystemTranslator.current()
        translator = system
        packStatus = system.isAvailable ? "installed" : "not downloaded"
    }

    // MARK: - Derived, never stored

    public func due(now: TimeInterval = Date().timeIntervalSince1970) -> [Item] {
        store.due(now: now)
    }

    public var logByteCount: Int { log?.byteCount ?? 0 }
    public var stagedByteCount: Int { storage.map(DataStaging.stagedByteCount) ?? 0 }
}
