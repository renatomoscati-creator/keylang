import XCTest
@testable import StudyKit
import LinguaKeyCore

/// Pins the log format and the fold to `tools/engine/store.py`.
///
/// The interesting failures here are not arithmetic. They are a field renamed on
/// one side, a channel raw value that does not match, or a nil optional encoded
/// as `null` where the other side expects the key to be absent. This test reads
/// a log the reference wrote, through the real `EventLog`, and folds it through
/// the real `ItemStore`, so all of that is exercised in one pass.
///
/// Regenerate with `python3 tools/engine/golden_store.py`.
final class StoreGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Snapshot: Decodable {
            let stability: Double
            let difficulty: Double
            let reps: Int
            let lapses: Int
            let exposures: Int
            let effective_reps: Double
            let last_graded_failed: Bool
            let retrievability: Double
        }
        struct ItemGolden: Decodable {
            let recognition: Snapshot
            let production: Snapshot
            let mastery: Double
            let suppress: Bool
        }
        let tolerance: Double
        let now: TimeInterval
        let event_count: Int
        let skipped_lines: Int
        let complete_byte_count: Int
        let items: [String: ItemGolden]
    }

    private var storage: Storage!

    override func setUpWithError() throws {
        storage = try Fixtures.temporaryStorage()
    }

    override func tearDownWithError() throws {
        Fixtures.remove(storage)
    }

    /// Copies the reference log into a temporary container and opens it for real.
    private func load() throws -> (Golden, EventLog) {
        let events = Fixtures.repoRoot
            .appendingPathComponent("build/golden/store-events.jsonl")
        let vectors = Fixtures.repoRoot
            .appendingPathComponent("build/golden/store-golden.json")
        guard FileManager.default.fileExists(atPath: events.path),
              FileManager.default.fileExists(atPath: vectors.path) else {
            throw XCTSkip("store vectors missing. Run: python3 tools/engine/golden_store.py")
        }
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: vectors))
        let log = try EventLog(url: storage.eventLog)
        try Data(contentsOf: events).write(to: storage.eventLog)
        return (golden, log)
    }

    func testTheReferenceLogReadsAsExpected() throws {
        let (golden, log) = try load()
        let result = log.read()
        XCTAssertEqual(result.events.count, golden.event_count,
                       "the Swift decoder disagreed about how many records are readable")
        // Three unreadable lines: an unknown schema, a line that is not JSON, and
        // a torn final line. The blank line between them is not corruption.
        XCTAssertEqual(result.skipped, golden.skipped_lines)
        XCTAssertEqual(log.completeByteCount(), golden.complete_byte_count,
                       "the torn tail was not excluded from the complete byte count")
    }

    func testOptionalsAreAbsentRatherThanNull() throws {
        let (_, log) = try load()
        let events = log.read().events
        // Swift encodes a nil Optional with encodeIfPresent, so the reference
        // must omit the key entirely. Round-tripping proves both directions.
        let ungraded = events.filter { $0.grade == nil }
        XCTAssertFalse(ungraded.isEmpty, "the vectors carry no ungraded event to check")
        let encoder = JSONEncoder()
        for event in ungraded.prefix(5) {
            let text = String(decoding: try encoder.encode(event), as: UTF8.self)
            XCTAssertFalse(text.contains("\"grade\""))
            XCTAssertFalse(text.contains("null"))
        }
    }

    func testPriorsAreNeverRepeated() throws {
        let (_, log) = try load()
        var seen = Set<String>()
        var createdWithoutPriors: [String] = []
        for event in log.read().events {
            if seen.insert(event.itemKey).inserted {
                if event.features == nil { createdWithoutPriors.append(event.itemKey) }
            } else {
                XCTAssertNil(event.features,
                             "\(event.itemKey) repeated its priors on a later event")
            }
        }
        // The vectors deliberately include exactly one item created with no
        // priors at all, standing in for a build that stopped sending them. It
        // must still fold into a usable item rather than being dropped.
        XCTAssertEqual(createdWithoutPriors, ["LEM:desconocido|N|0"])
    }

    func testTheFoldMatchesTheReference() throws {
        let (golden, log) = try load()
        let store = ItemStore.fold(log.read().events)

        XCTAssertEqual(Set(store.items.keys), Set(golden.items.keys))

        for (key, expected) in golden.items {
            let item = try XCTUnwrap(store.items[key], key)
            expect(item.recognition, expected.recognition, "\(key).recognition",
                   golden.now, golden.tolerance)
            expect(item.production, expected.production, "\(key).production",
                   golden.now, golden.tolerance)
            XCTAssertEqual(item.mastery(now: golden.now), expected.mastery,
                           accuracy: golden.tolerance, "\(key).mastery")
            // Both answers are pinned, not just the negative one: the vectors
            // carry an item that is genuinely known, one whose last graded event
            // was a failure, and one with twenty exposures and no recall.
            XCTAssertEqual(item.shouldSuppress(now: golden.now), expected.suppress,
                           "\(key).suppress")
        }
    }

    func testFoldingIsIdenticalWhetherReadWholeOrIncrementally() throws {
        // The store is loaded from a snapshot on a warm launch and from a full
        // replay on a cold one. They have to agree, or a relaunch would silently
        // change what the app says it knows.
        let (golden, log) = try load()
        let full = ItemStore.load(log: log, storage: storage)
        XCTAssertEqual(full.outcome, .rebuiltNoSnapshot)
        try full.store.save(to: storage, logByteCount: full.logByteCount)

        let warm = ItemStore.load(log: log, storage: storage)
        XCTAssertEqual(warm.outcome, .snapshotUsed)
        XCTAssertEqual(warm.store.items, full.store.items)
        XCTAssertEqual(warm.store.eventCount, golden.event_count)
    }

    private func expect(_ actual: Trace, _ expected: Golden.Snapshot, _ label: String,
                        _ now: TimeInterval, _ tolerance: Double) {
        XCTAssertEqual(actual.stability, expected.stability, accuracy: tolerance,
                       "\(label).stability")
        XCTAssertEqual(actual.difficulty, expected.difficulty, accuracy: tolerance,
                       "\(label).difficulty")
        XCTAssertEqual(actual.reps, expected.reps, "\(label).reps")
        XCTAssertEqual(actual.lapses, expected.lapses, "\(label).lapses")
        XCTAssertEqual(actual.exposures, expected.exposures, "\(label).exposures")
        XCTAssertEqual(actual.effectiveReps, expected.effective_reps, accuracy: tolerance,
                       "\(label).effectiveReps")
        XCTAssertEqual(actual.lastGradedFailed, expected.last_graded_failed,
                       "\(label).lastGradedFailed")
        XCTAssertEqual(actual.retrievability(now: now), expected.retrievability,
                       accuracy: tolerance, "\(label).retrievability")
    }
}
