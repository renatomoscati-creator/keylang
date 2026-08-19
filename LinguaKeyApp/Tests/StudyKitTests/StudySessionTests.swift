import XCTest
@testable import StudyKit
import LinguaKeyCore

/// The arm is the only thing that varies. If a test here ever shows the arms
/// selecting different words, the experiment is measuring two variables and
/// nothing it produces means anything.
final class StudySessionTests: XCTestCase {

    private let sentence = "Quiero un vaso de agua"
    private let vaso = "LEM:vaso|N|0"

    private func session(arm: Arm, store: ItemStore = ItemStore(),
                         now: TimeInterval = 0) throws -> StudySession {
        // A salt is searched for that puts `vaso` in the wanted arm, rather than
        // stubbing the assignment, so the real assignment function stays in the
        // path being tested.
        let assignment = try saltPutting(vaso, in: arm)
        return StudySession(sentence: sentence, selector: try Fixtures.selector(),
                            store: store, assignment: assignment, now: now)
    }

    private func saltPutting(_ key: String, in arm: Arm) throws -> ArmAssignment {
        for index in 0..<1000 {
            let assignment = ArmAssignment(salt: "test-salt-\(index)")
            if assignment.arm(for: key) == arm { return assignment }
        }
        throw XCTSkip("no salt found putting \(key) in arm \(arm.rawValue)")
    }

    func testEveryArmSelectsTheSameWord() throws {
        let selected = try Arm.allCases.map { arm in
            try session(arm: arm).focuses.map(\.candidate.key).sorted()
        }
        XCTAssertEqual(Set(selected).count, 1, "the arms disagreed on what to teach: \(selected)")
        XCTAssertTrue(selected[0].contains(vaso))
    }

    func testControlTeachesNothingButStillLogsTheExposure() throws {
        let control = try session(arm: .control)
        XCTAssertTrue(control.taught.isEmpty)

        let events = control.presentationEvents(store: ItemStore())
        let forVaso = events.filter { $0.itemKey == vaso }
        XCTAssertEqual(forVaso.map(\.channel), [.exposeGlanced])
        XCTAssertEqual(forVaso.first?.arm, .control)
    }

    func testRecognitionShowsTheGlossAndSaysSo() throws {
        let recognition = try session(arm: .recognition)
        XCTAssertFalse(recognition.taught.isEmpty)
        let channels = recognition.presentationEvents(store: ItemStore())
            .filter { $0.itemKey == vaso }.map(\.channel)
        XCTAssertEqual(channels, [.exposeGlanced, .exposeDwelled])
    }

    func testRetrievalWaitsForAnAnswer() throws {
        let retrieval = try session(arm: .retrieval)
        let focus = try XCTUnwrap(retrieval.focuses.first { $0.candidate.key == vaso })
        XCTAssertTrue(focus.isTaught)

        let presented = retrieval.presentationEvents(store: ItemStore())
            .filter { $0.itemKey == vaso }
        XCTAssertEqual(presented.map(\.channel), [.exposeGlanced])
        XCTAssertNil(presented.first?.grade, "an exposure carried a grade")

        let answered = retrieval.answerEvent(focus, grade: .good, at: 30,
                                             store: ItemStore())
        XCTAssertEqual(answered.channel, .recall)
        XCTAssertEqual(answered.grade, .good)

        // Revealing without answering is weaker than answering, and is not a
        // grade. The exposure-efficacy fit in Phase 08 rests on that difference.
        let revealed = retrieval.revealEvent(focus, at: 30, store: ItemStore())
        XCTAssertEqual(revealed.channel, .tapped)
        XCTAssertNil(revealed.grade)
        XCTAssertLessThan(Channel.tapped.eta, Channel.recall.eta)
    }

    func testPriorsRideOnlyOnTheEventThatCreatesTheItem() throws {
        let recognition = try session(arm: .recognition)
        let events = recognition.presentationEvents(store: ItemStore())
            .filter { $0.itemKey == vaso }
        XCTAssertNotNil(events.first?.features)
        XCTAssertNil(events.dropFirst().first?.features,
                     "priors were repeated on an event that did not create the item")

        // And not at all once the item is known.
        var known = ItemStore()
        for event in events { known.apply(event) }
        let second = try session(arm: .recognition, store: known)
        let repeated = second.presentationEvents(store: known)
        XCTAssertFalse(repeated.isEmpty, "vaso stopped being selected after two exposures")
        XCTAssertTrue(repeated.allSatisfy { $0.features == nil })
    }

    func testAFalseFriendIsTaughtAsOne() throws {
        let recognition = try session(arm: .recognition)
        let focus = try XCTUnwrap(recognition.taught.first { $0.candidate.key == vaso })
        XCTAssertNotNil(focus.candidate.trap)
        XCTAssertTrue(focus.candidate.reason.contains("false friend"))
    }

    func testNothingToTeachProducesNoEvents() throws {
        let assignment = ArmAssignment(salt: "any")
        let empty = StudySession(sentence: "y de la que en el a",
                                 selector: try Fixtures.selector(), store: ItemStore(),
                                 assignment: assignment, now: 0)
        XCTAssertTrue(empty.focuses.isEmpty)
        XCTAssertTrue(empty.presentationEvents(store: ItemStore()).isEmpty)
    }

    func testASuppressedItemProducesNeitherFocusNorEvent() throws {
        var store = ItemStore()
        store.apply(Fixtures.event(vaso, .recall, at: 0, grade: .good,
                                   features: ItemFeatures(zipf: 4.6, cognateMax: 1.0)))
        store.apply(Fixtures.event(vaso, .recall, at: FSRS.secondsPerDay, grade: .good))
        store.apply(Fixtures.event(vaso, .recall, at: 3 * FSRS.secondsPerDay, grade: .good))
        store.apply(Fixtures.event(vaso, .recall, at: 8 * FSRS.secondsPerDay, grade: .good))

        let now = 8 * FSRS.secondsPerDay
        try XCTSkipUnless(store.items[vaso]?.shouldSuppress(now: now) ?? false,
                          "precondition: vaso should be suppressed by now")
        let quiet = try session(arm: .recognition, store: store, now: now)
        XCTAssertFalse(quiet.focuses.contains { $0.candidate.key == vaso })
        XCTAssertFalse(quiet.presentationEvents(store: store).contains { $0.itemKey == vaso })
    }

    func testTheSentenceIsHashedNotStoredInTheEvent() throws {
        let recognition = try session(arm: .recognition)
        let event = try XCTUnwrap(recognition.presentationEvents(store: ItemStore()).first)
        XCTAssertEqual(event.sentenceHash, ArmAssignment.fnv1a64(sentence))
        // The user's own messages are not this app's to keep.
        let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Quiero un vaso"))
    }
}
