import XCTest
@testable import StudyKit
import LinguaKeyCore

final class ItemStoreTests: XCTestCase {

    private var storage: Storage!

    override func setUpWithError() throws {
        storage = try Fixtures.temporaryStorage()
    }

    override func tearDownWithError() throws {
        Fixtures.remove(storage)
    }

    private var sample: [Event] {
        let day = FSRS.secondsPerDay
        return [
            Fixtures.event("LEM:vaso|N|0", .exposeDwelled, at: 0,
                           features: ItemFeatures(zipf: 4.6, cognateMax: 1.0,
                                                  falseFriend: true)),
            Fixtures.event("LEM:vaso|N|0", .recall, at: day, grade: .good),
            Fixtures.event("LEM:pan|N|0", .exposeGlanced, at: day,
                           features: ItemFeatures(zipf: 5.2, cognateMax: 0.8)),
            Fixtures.event("LEM:vaso|N|0", .recall, at: 3 * day, grade: .again),
        ]
    }

    func testFoldEqualsApplyingTheSameEventsDirectly() {
        var expected = ItemStore()
        for event in sample { expected.apply(event) }
        XCTAssertEqual(ItemStore.fold(sample).items, expected.items)
    }

    func testFeaturesFromTheCreatingEventReachTheItem() throws {
        // The item is created by the first event that mentions it, so the priors
        // recorded on that event are the only thing standing between a false
        // friend and being treated like any other word of the same frequency.
        var store = ItemStore()
        store.apply(sample[0])
        let vaso = try XCTUnwrap(store.items["LEM:vaso|N|0"])

        let trap = FSRS.difficultyPrior(zipf: 4.6, cognateMax: 1.0, falseFriend: true)
        let plain = FSRS.difficultyPrior(zipf: 4.6, cognateMax: 1.0, falseFriend: false)
        XCTAssertGreaterThan(trap, plain)
        // An exposure reaches recognition only, so production still carries the
        // untouched cold-start difficulty.
        XCTAssertEqual(vaso.production.difficulty, trap, accuracy: 1e-9)
        XCTAssertEqual(vaso.production.stability,
                       FSRS.stabilityPrior(cognateMax: 1.0), accuracy: 1e-9)
    }

    func testAnEventWithNoFeaturesStillCreatesAUsableItem() throws {
        // Events written before an item existed in the tables, or by a future
        // build that stopped sending priors. Neither may lose the event.
        var store = ItemStore()
        store.apply(Fixtures.event("CELL:V|IND,FUT,1,SG", .exposeDwelled, at: 0))
        let cell = try XCTUnwrap(store.items["CELL:V|IND,FUT,1,SG"])
        XCTAssertEqual(cell.recognition.exposures, 1)
    }

    func testAFailedRecallIsVisibleInTheFold() {
        let store = ItemStore.fold(sample)
        XCTAssertTrue(store.items["LEM:vaso|N|0"]?.production.lastGradedFailed ?? false)
        XCTAssertEqual(store.items["LEM:vaso|N|0"]?.production.lapses, 1)
    }

    func testMasteryIsNeverStored() throws {
        var store = ItemStore()
        for event in sample { store.apply(event) }
        try store.save(to: storage, logByteCount: 0)
        let json = try String(contentsOf: storage.snapshot, encoding: .utf8)
        // A stored mastery cannot decay. If this ever appears on disk the model
        // has been quietly replaced by the one the stress test rejected.
        XCTAssertFalse(json.lowercased().contains("mastery"))
    }

    func testSnapshotIsUsedWhenItMatchesTheLog() throws {
        let log = try EventLog(url: storage.eventLog)
        try log.appendAll(sample)
        let rebuilt = ItemStore.load(log: log, storage: storage)
        XCTAssertEqual(rebuilt.outcome, .rebuiltNoSnapshot)
        try rebuilt.store.save(to: storage, logByteCount: rebuilt.logByteCount)

        let reloaded = ItemStore.load(log: log, storage: storage)
        XCTAssertEqual(reloaded.outcome, .snapshotUsed)
        XCTAssertEqual(reloaded.store.items, rebuilt.store.items)
    }

    func testTheLogWinsWhenItHasGrown() throws {
        let log = try EventLog(url: storage.eventLog)
        try log.appendAll(sample)
        let first = ItemStore.load(log: log, storage: storage)
        try first.store.save(to: storage, logByteCount: first.logByteCount)

        try log.append(Fixtures.event("LEM:nuevo|N|0", .exposeDwelled, at: 999,
                                      features: ItemFeatures(zipf: 3.0, cognateMax: 0.0)))
        let second = ItemStore.load(log: log, storage: storage)
        XCTAssertEqual(second.outcome, .rebuiltStale)
        XCTAssertNotNil(second.store.items["LEM:nuevo|N|0"])
    }

    func testACorruptedSnapshotRebuildsRatherThanThrowing() throws {
        let log = try EventLog(url: storage.eventLog)
        try log.appendAll(sample)
        try Data("not a snapshot".utf8).write(to: storage.snapshot)

        let result = ItemStore.load(log: log, storage: storage)
        XCTAssertEqual(result.outcome, .rebuiltUnreadable)
        XCTAssertEqual(result.store.items.count, 2)
    }

    func testATornTailDoesNotMakeTheSnapshotLookStaleForever() throws {
        // Without `completeByteCount` this is the bug that makes every launch
        // after a jetsam kill do a full replay of the whole log, forever.
        let log = try EventLog(url: storage.eventLog)
        try log.appendAll(sample)
        let first = ItemStore.load(log: log, storage: storage)
        try first.store.save(to: storage, logByteCount: first.logByteCount)

        let handle = try FileHandle(forWritingTo: storage.eventLog)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"schema\":1,\"id\":\"tor".utf8))
        try handle.close()

        XCTAssertEqual(ItemStore.load(log: log, storage: storage).outcome, .snapshotUsed)
    }

    func testDueOrdersTheMostForgottenFirst() {
        let day = FSRS.secondsPerDay
        var store = ItemStore()
        store.apply(Fixtures.event("LEM:old|N|0", .recall, at: 0, grade: .good,
                                   features: ItemFeatures(zipf: 3.0, cognateMax: 0.0)))
        store.apply(Fixtures.event("LEM:fresh|N|0", .recall, at: 40 * day, grade: .good,
                                   features: ItemFeatures(zipf: 3.0, cognateMax: 0.0)))
        let due = store.due(now: 41 * day)
        XCTAssertEqual(due.first?.key, "LEM:old|N|0")
    }
}
