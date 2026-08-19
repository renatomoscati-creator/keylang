import Foundation
import LinguaKeyCore

/// Item state, derived by folding the event log.
///
/// Never the source of truth. `mastery` is not stored anywhere, in this type or
/// on disk, because a stored number cannot decay and a schema that keeps one is
/// the exact mistake the stress test found in the PRD.
public struct ItemStore: Sendable {

    public private(set) var items: [String: Item] = [:]
    public private(set) var eventCount = 0

    public init() {}

    /// Apply one event. Creating the item on first sight is why events carry
    /// their cold-start features: the fold must not need the 3.7 MB tables.
    public mutating func apply(_ event: Event) {
        var item = items[event.itemKey] ?? ItemStore.create(event)
        item.observe(event.channel, now: event.at, grade: event.grade ?? .good)
        items[event.itemKey] = item
        eventCount += 1
    }

    private static func create(_ event: Event) -> Item {
        let features = event.features ?? ItemFeatures(zipf: 3.0, cognateMax: 0.0)
        return Item.new(key: event.itemKey,
                        zipf: features.zipf,
                        cognateMax: features.cognateMax,
                        falseFriend: features.falseFriend,
                        length: features.length,
                        isConstruction: features.isConstruction,
                        irregular: features.irregular,
                        now: event.at)
    }

    public static func fold(_ events: [Event]) -> ItemStore {
        var store = ItemStore()
        for event in events { store.apply(event) }
        return store
    }

    // MARK: - Snapshot

    /// A startup cache, never an authority. If it disagrees with the log by so
    /// much as a byte the log wins and this is thrown away.
    public struct Snapshot: Codable, Sendable {
        public let logByteCount: Int
        public let eventCount: Int
        public let items: [String: Item]
    }

    public enum LoadOutcome: String, Sendable {
        case snapshotUsed
        case rebuiltNoSnapshot
        case rebuiltStale
        case rebuiltUnreadable
    }

    public struct LoadResult: Sendable {
        public let store: ItemStore
        public let outcome: LoadOutcome
        public let skippedLines: Int
        public let logByteCount: Int
    }

    /// Load, preferring the snapshot and falling back to a full replay.
    ///
    /// The comparison is against the log's last COMPLETE line, not its size, so
    /// a torn tail left by a jetsam kill does not make the snapshot look stale
    /// on every launch forever.
    public static func load(log: EventLog, storage: Storage) -> LoadResult {
        let complete = log.completeByteCount()

        if let data = try? Data(contentsOf: storage.snapshot) {
            if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                if snapshot.logByteCount == complete {
                    var store = ItemStore()
                    store.items = snapshot.items
                    store.eventCount = snapshot.eventCount
                    return LoadResult(store: store, outcome: .snapshotUsed,
                                      skippedLines: 0, logByteCount: complete)
                }
                return rebuild(log: log, complete: complete, outcome: .rebuiltStale)
            }
            return rebuild(log: log, complete: complete, outcome: .rebuiltUnreadable)
        }
        return rebuild(log: log, complete: complete, outcome: .rebuiltNoSnapshot)
    }

    private static func rebuild(log: EventLog, complete: Int,
                                outcome: LoadOutcome) -> LoadResult {
        let result = log.read()
        return LoadResult(store: fold(result.events), outcome: outcome,
                          skippedLines: result.skipped, logByteCount: complete)
    }

    public func save(to storage: Storage, logByteCount: Int) throws {
        try storage.createIfNeeded()
        let snapshot = Snapshot(logByteCount: logByteCount, eventCount: eventCount, items: items)
        try JSONEncoder().encode(snapshot).write(to: storage.snapshot, options: .atomic)
    }

    // MARK: - Queries

    /// Derived at read time, always.
    public func mastery(_ key: String, now: TimeInterval) -> Double? {
        items[key]?.mastery(now: now)
    }

    public func due(now: TimeInterval, retention: Double = 0.85) -> [Item] {
        items.values
            .filter { $0.production.retrievability(now: now) < retention }
            .sorted { $0.production.retrievability(now: now) < $1.production.retrievability(now: now) }
    }
}
