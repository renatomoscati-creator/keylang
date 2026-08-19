import XCTest
@testable import StudyKit

/// Pinned to `tools/engine/arms.py` by golden vectors.
///
/// This is the one function in the product with a failure mode that looks like
/// working code: a process-seeded hash reassigns arms on every launch, the app
/// behaves normally, and the experiment is worthless by the time anyone notices.
final class ArmAssignmentTests: XCTestCase {

    struct Golden: Decodable {
        struct Assignment: Decodable {
            let salt: String
            let key: String
            let arm: String
        }
        struct Distribution: Decodable {
            let salt: String
            let count: Int
            let counts: [String: Int]
        }
        let arms: [String]
        let fnv1a64: [String: String]
        let assignments: [Assignment]
        let distribution: Distribution
    }

    private func loadGolden() throws -> Golden {
        let url = Fixtures.armGolden
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("arm vectors missing. Run: python3 tools/engine/golden_arms.py")
        }
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    func testHashMatchesTheReference() throws {
        let golden = try loadGolden()
        for (text, expected) in golden.fnv1a64 {
            XCTAssertEqual(String(ArmAssignment.fnv1a64(text)), expected,
                           "fnv1a64(\(text.debugDescription))")
        }
    }

    func testPublishedFNVVectors() {
        // Independent of the reference: these are the published FNV-1a 64 test
        // vectors, so an error copied into both implementations still fails here.
        XCTAssertEqual(ArmAssignment.fnv1a64(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(ArmAssignment.fnv1a64("a"), 0xaf63_dc4c_8601_ec8c)
        XCTAssertEqual(ArmAssignment.fnv1a64("foobar"), 0x8594_4171_f739_67e8)
    }

    func testAssignmentsMatchTheReference() throws {
        let golden = try loadGolden()
        XCTAssertFalse(golden.assignments.isEmpty)
        for row in golden.assignments {
            let arm = ArmAssignment(salt: row.salt).arm(for: row.key)
            XCTAssertEqual(arm.rawValue, row.arm,
                           "salt \(row.salt.debugDescription) key \(row.key.debugDescription)")
        }
    }

    func testDistributionMatchesTheReference() throws {
        let golden = try loadGolden()
        let assignment = ArmAssignment(salt: golden.distribution.salt)
        var counts: [String: Int] = [:]
        for index in 0..<golden.distribution.count {
            counts[assignment.arm(for: "LEM:word\(index)|N|0").rawValue, default: 0] += 1
        }
        XCTAssertEqual(counts, golden.distribution.counts)
    }

    func testAssignmentIsStableAcrossInstances() {
        let key = "LEM:vaso|N|0"
        XCTAssertEqual(ArmAssignment(salt: "s").arm(for: key),
                       ArmAssignment(salt: "s").arm(for: key))
    }

    func testTheSeparatorKeepsSaltAndKeyApart() {
        XCTAssertNotEqual(ArmAssignment.fnv1a64("ab\u{1}c"),
                          ArmAssignment.fnv1a64("a\u{1}bc"))
    }

    func testSaltIsCreatedOnceAndReused() throws {
        let storage = try Fixtures.temporaryStorage()
        defer { Fixtures.remove(storage) }

        let first = try ArmAssignment.load(storage)
        let second = try ArmAssignment.load(storage)
        XCTAssertEqual(first.salt, second.salt)
        XCTAssertFalse(first.salt.isEmpty)
    }
}
