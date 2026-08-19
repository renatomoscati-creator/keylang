import XCTest
@testable import StudyKit
import LinguaKeyCore

/// The log is the only thing in this product worth more than the build that
/// reads it, so its failure modes are tested rather than assumed.
final class EventLogTests: XCTestCase {

    private var storage: Storage!

    override func setUpWithError() throws {
        storage = try Fixtures.temporaryStorage()
    }

    override func tearDownWithError() throws {
        Fixtures.remove(storage)
    }

    func testRoundTrip() throws {
        let log = try EventLog(url: storage.eventLog)
        let written = (0..<50).map {
            Fixtures.event("LEM:w\($0)|N|0", .exposeDwelled, at: Double($0) * 60)
        }
        for event in written { try log.append(event) }

        let result = log.read()
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(result.events, written)
    }

    func testATornFinalLineIsDroppedAndTheRestSurvives() throws {
        // The expected case on this device, not an exceptional one: jetsam kills
        // the extension part-way through a write and leaves half a JSON object.
        let log = try EventLog(url: storage.eventLog)
        for index in 0..<10 {
            try log.append(Fixtures.event("LEM:w\(index)|N|0", .exposeGlanced,
                                          at: Double(index)))
        }
        let handle = try FileHandle(forWritingTo: storage.eventLog)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"schema":1,"id":"not-fin"#.utf8))
        try handle.close()

        let result = log.read()
        XCTAssertEqual(result.events.count, 10)
        XCTAssertEqual(result.skipped, 1)
    }

    func testAnUnreadableRecordDoesNotCostTheOthers() throws {
        let log = try EventLog(url: storage.eventLog)
        try log.append(Fixtures.event("LEM:a|N|0", .exposeDwelled, at: 1))
        // A record from a schema this build does not understand, exactly what a
        // downgrade after an experiment change would produce.
        let handle = try FileHandle(forWritingTo: storage.eventLog)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"schema\":99,\"id\":\"x\"}\n".utf8))
        try handle.write(contentsOf: Data("not json at all\n".utf8))
        try handle.close()
        try log.append(Fixtures.event("LEM:b|N|0", .exposeDwelled, at: 2))

        let result = log.read()
        XCTAssertEqual(result.events.map(\.itemKey), ["LEM:a|N|0", "LEM:b|N|0"])
        XCTAssertEqual(result.skipped, 2)
    }

    func testBlankLinesAreNotCountedAsSkipped() throws {
        let log = try EventLog(url: storage.eventLog)
        try log.append(Fixtures.event("LEM:a|N|0", .exposeDwelled, at: 1))
        let handle = try FileHandle(forWritingTo: storage.eventLog)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n\n".utf8))
        try handle.close()

        let result = log.read()
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.skipped, 0)
    }

    func testConcurrentWritersProduceWholeLines() throws {
        // Two processes really do write to this file. Threads are the closest
        // this test can get, and they are enough to catch a non-atomic append.
        let log = try EventLog(url: storage.eventLog)
        let group = DispatchGroup()
        for writer in 0..<4 {
            DispatchQueue.global().async(group: group) {
                for index in 0..<250 {
                    try? log.append(Fixtures.event("LEM:w\(writer)-\(index)|N|0",
                                                   .exposeGlanced, at: Double(index)))
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)

        let result = log.read()
        XCTAssertEqual(result.events.count, 1000, "an append was torn or lost")
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(Set(result.events.map(\.itemKey)).count, 1000)
    }

    func testABatchIsAllOrNothing() throws {
        let log = try EventLog(url: storage.eventLog)
        let batch = (0..<3).map {
            Fixtures.event("LEM:b\($0)|N|0", .exposeGlanced, at: Double($0))
        }
        try log.appendAll(batch)
        XCTAssertEqual(log.read().events, batch)
    }

    func testAnOversizedRecordIsRefusedRatherThanTorn() throws {
        let log = try EventLog(url: storage.eventLog)
        let huge = String(repeating: "a", count: EventLog.maximumRecordBytes)
        XCTAssertThrowsError(try log.append(Fixtures.event(huge, .exposeGlanced, at: 0)))
        XCTAssertEqual(log.read().events.count, 0, "a refused record still reached the file")
    }

    func testCompleteByteCountIgnoresATornTail() throws {
        let log = try EventLog(url: storage.eventLog)
        try log.append(Fixtures.event("LEM:a|N|0", .exposeDwelled, at: 1))
        let whole = log.completeByteCount()
        XCTAssertEqual(whole, log.byteCount)

        let handle = try FileHandle(forWritingTo: storage.eventLog)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"partial\"".utf8))
        try handle.close()

        XCTAssertEqual(log.completeByteCount(), whole)
        XCTAssertGreaterThan(log.byteCount, whole)
    }

    func testReadingFromAnOffsetSkipsWhatIsAlreadyKnown() throws {
        let log = try EventLog(url: storage.eventLog)
        try log.append(Fixtures.event("LEM:a|N|0", .exposeDwelled, at: 1))
        let offset = log.completeByteCount()
        try log.append(Fixtures.event("LEM:b|N|0", .exposeDwelled, at: 2))

        XCTAssertEqual(log.read(from: offset).events.map(\.itemKey), ["LEM:b|N|0"])
    }

    func testAnEmptyLogReadsAsEmpty() throws {
        let log = try EventLog(url: storage.eventLog)
        XCTAssertEqual(log.read().events.count, 0)
        XCTAssertEqual(log.completeByteCount(), 0)
        XCTAssertEqual(log.byteCount, 0)
    }
}
