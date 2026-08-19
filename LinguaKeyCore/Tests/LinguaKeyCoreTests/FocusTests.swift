import XCTest
@testable import LinguaKeyCore

/// The 22 behaviours from `tools/engine/test_focus.py`, run against the same
/// built tables.
///
/// Unlike `GoldenVectorTests` these are not numeric replays. Focus selection
/// depends on the whole 3.7 MB morphology table, so freezing its outputs into
/// vectors would freeze the data build too, and rebuilding the data would then
/// look like a regression in the selector. What is asserted instead is the set
/// of properties the design actually promises: false friends surface, true
/// cognates do not get called false friends, the one-note budget holds, a
/// sentence with nothing to teach teaches nothing, and exposure alone never buys
/// silence.
final class FocusTests: XCTestCase {

    private func pick(_ sentence: String,
                      state: [String: Item] = [:],
                      now: TimeInterval = 0,
                      sessionCounts: [String: Int] = [:]) throws -> [Candidate] {
        try Fixtures.selector().select(sentence: sentence, state: state, now: now,
                                       sessionCounts: sessionCounts)
    }

    private func keys(_ chosen: [Candidate]) -> Set<String> {
        Set(chosen.map(\.key))
    }

    // MARK: - False friends win

    func testFalseFriendsAreChosen() throws {
        // Each of these is in `data/interference.json` and each is a word an
        // Italian speaker will confidently get wrong.
        let cases = [
            ("Voy a comprar mantequilla y pan", "pan"),
            ("El problema es que salgo muy tarde", "salir"),
            ("Quiero un vaso de agua", "vaso"),
            ("Espero que vengas pronto", "pronto"),
        ]
        for (sentence, lemma) in cases {
            let chosen = try pick(sentence)
            XCTAssertTrue(
                chosen.contains { $0.lemma == lemma && $0.reason.contains("false friend") },
                "\(lemma) not flagged in \(sentence). Got \(chosen.map { ($0.surface, $0.reason) })")
        }
    }

    // MARK: - True cognates do not

    func testTrueCognatesAreNotCalledFalseFriends() throws {
        // The bug this replaced: using the orthographic score as if it were
        // semantic flagged `llegar`~`legare` and `comprar`~`comprare`, which are
        // true cognates and exactly the words a learner gets for free.
        let cases = [
            ("Probablemente llegaré sobre las ocho", "llegar"),
            ("Voy a comprar pan", "comprar"),
            ("Tengo que estudiar", "estudiar"),
        ]
        for (sentence, lemma) in cases {
            let chosen = try pick(sentence)
            XCTAssertFalse(
                chosen.contains { $0.lemma == lemma && $0.reason.contains("false friend") },
                "\(lemma) wrongly flagged as a false friend")
        }
    }

    // MARK: - The budget

    func testAtMostOneNoteOfEachKindAndNeverOnTheSameWord() throws {
        let sentences = [
            "Probablemente llegaré sobre las ocho y quiero comprar pan y vino",
            "El problema es que salgo muy tarde y tengo mucha prisa",
        ]
        for sentence in sentences {
            let chosen = try pick(sentence)
            XCTAssertLessThanOrEqual(chosen.filter { $0.kind == .vocabulary }.count, 1,
                                     "more than one vocabulary note for \(sentence)")
            XCTAssertLessThanOrEqual(chosen.filter { $0.kind == .grammar }.count, 1,
                                     "more than one grammar note for \(sentence)")
            XCTAssertEqual(Set(chosen.map(\.surface)).count, chosen.count,
                           "two notes landed on one word in \(sentence)")
        }
    }

    // MARK: - Silence

    func testNothingToTeachTeachesNothing() throws {
        XCTAssertTrue(try pick("y de la que en el a").isEmpty,
                      "function words alone produced a note")
        XCTAssertTrue(try pick("qwertz asdfgh zxcvbn").isEmpty,
                      "nonsense produced a note")
        XCTAssertTrue(try pick("").isEmpty, "the empty string produced a note")
    }

    // MARK: - State changes the answer

    func testKnownItemIsDropped() throws {
        // The behaviour the PRD promised and its threshold ladder could not
        // deliver, because a stored float cannot decay.
        let sentence = "Quiero un vaso de agua"
        let key = "LEM:vaso|N|0"
        XCTAssertTrue(keys(try pick(sentence)).contains(key),
                      "vaso should be taught while unknown")

        var item = Item.new(key: key, zipf: 4.6, cognateMax: 1.0, now: 0)
        for day in [1.0, 3.0, 8.0] {
            item.observe(.recall, now: day * FSRS.secondsPerDay, grade: .good)
        }
        let after = try pick(sentence, state: [key: item], now: 8 * FSRS.secondsPerDay)
        XCTAssertFalse(keys(after).contains(key),
                       "vaso still taught after three successful recalls: \(keys(after).sorted())")
    }

    func testExposureAloneNeverBuysSilence() throws {
        // Same failure mode as F3 in the stress test: counting having been shown
        // a word as having learned it. Forty dwelled exposures is far more than
        // any real session produces.
        let sentence = "Quiero un vaso de agua"
        let key = "LEM:vaso|N|0"
        var item = Item.new(key: key, zipf: 4.6, cognateMax: 1.0, now: 0)
        for day in 1...40 {
            item.observe(.exposeDwelled, now: Double(day) * FSRS.secondsPerDay)
        }
        let still = try pick(sentence, state: [key: item], now: 40 * FSRS.secondsPerDay)
        XCTAssertTrue(keys(still).contains(key),
                      "40 exposures silenced vaso: \(keys(still).sorted())")
    }

    // MARK: - Repetition within a session

    func testRepeatingWithinOneSessionIsDamped() throws {
        let damped = try pick("Quiero un vaso de agua",
                              sessionCounts: ["LEM:vaso|N|0": 3])
        XCTAssertFalse(keys(damped).contains("LEM:vaso|N|0"),
                       "vaso taught a fourth time in one session: \(keys(damped).sorted())")
    }

    // MARK: - Grammar notes are teachable

    func testTheFutureFormGetsTheGrammarNote() throws {
        let grammar = try pick("Probablemente llegaré sobre las ocho")
            .filter { $0.kind == .grammar }
        XCTAssertTrue(grammar.contains { $0.feats.contains("FUT") },
                      "no future-tense note. Got \(grammar.map(\.key))")
    }

    func testNounGenderNeverBecomesAGrammarNote() throws {
        // "masculine singular noun" is not a lesson, and without the teachable
        // cell filter every sentence produces one, burning the one-note budget.
        let chosen = try pick("Quiero un vaso de agua")
        XCTAssertFalse(chosen.contains { $0.key.hasPrefix("CELL:N|") },
                       "a noun paradigm cell became a grammar note")
    }

    // MARK: - Invariants the reference relies on

    func testTokenizerDropsDigitsAndPunctuation() throws {
        XCTAssertEqual(FocusSelector.tokenize("Son las 8:30, ¿vale?"),
                       ["Son", "las", "vale"])
    }

    func testAccentsAreNormalisedBeforeLookup() throws {
        // iOS hands you decomposed accents from some hosts and precomposed from
        // others; the two are different bytes for the same word.
        let decomposed = "llegare\u{0301}"
        let precomposed = "llegaré"
        let selector = try Fixtures.selector()
        XCTAssertEqual(selector.select(sentence: decomposed, state: [:], now: 0).map(\.key),
                       selector.select(sentence: precomposed, state: [:], now: 0).map(\.key))
    }

    func testSuppressedLemmaSilencesItsGrammarNoteToo() throws {
        let sentence = "Probablemente llegaré sobre las ocho"
        let lemmaKey = "LEM:llegar|V|0"
        var item = Item.new(key: lemmaKey, zipf: 6.05, cognateMax: 1.0, now: 0)
        for day in [1.0, 3.0, 8.0, 20.0] {
            item.observe(.recall, now: day * FSRS.secondsPerDay, grade: .easy)
        }
        let now = 20 * FSRS.secondsPerDay
        try XCTSkipUnless(item.shouldSuppress(now: now),
                          "precondition: llegar should be suppressed by now")
        let chosen = try pick(sentence, state: [lemmaKey: item], now: now)
        XCTAssertFalse(chosen.contains { $0.surface.lowercased() == "llegaré" },
                       "a suppressed lemma still produced a note")
    }
}
