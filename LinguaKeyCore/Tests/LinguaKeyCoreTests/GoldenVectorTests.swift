import XCTest
@testable import LinguaKeyCore

/// Verifies the Swift memory model reproduces the Python reference exactly.
///
/// The reference in `tools/engine/fsrs.py` is where the model was designed and
/// property-tested. No Swift toolchain was reachable when it was written, so
/// these vectors are the mechanism that stops the two implementations drifting.
/// A failure here means the Swift and the reference disagree, and the reference
/// is the one with 34 property tests behind it.
///
/// Regenerate with `python3 tools/engine/golden.py` and treat a diff in the JSON
/// as a deliberate model change requiring a note in STATE.md, never as noise.
final class GoldenVectorTests: XCTestCase {

    struct Golden: Decodable {
        struct Constants: Decodable {
            let decay: Double
            let factor: Double
            let suppression_horizon_days: Double
            let seconds_per_day: Double
        }
        struct Scalar: Decodable {
            let fn: String
            let expect: Double
            let stability: Double?
            let difficulty: Double?
            let elapsed_days: Double?
            let r: Double?
            let eta: Double?
            let grade: Int?
            let zipf: Double?
            let cognate_max: Double?
            let false_friend: Bool?
        }
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
        struct Step: Decodable {
            let day: Double
            let channel: String
            let grade: Int
            let recognition: Snapshot
            let production: Snapshot
            let mastery: Double
            let suppress: Bool
        }
        struct Features: Decodable {
            let zipf: Double
            let cognate_max: Double
            let false_friend: Bool?
        }
        struct Scenario: Decodable {
            let name: String
            let features: Features
            let steps: [Step]
        }
        let tolerance: Double
        let weights: [Double]
        let eta: [String: Double]
        let constants: Constants
        let scalars: [Scalar]
        let scenarios: [Scenario]
    }

    private func loadGolden() throws -> Golden {
        let url = Fixtures.goldenVectors
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("golden vectors missing. Run: python3 tools/engine/golden.py")
        }
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    func testWeightsAndConstantsMatch() throws {
        let golden = try loadGolden()
        XCTAssertEqual(FSRS.w.count, golden.weights.count)
        for (index, expected) in golden.weights.enumerated() {
            XCTAssertEqual(FSRS.w[index], expected, accuracy: 1e-12, "w[\(index)]")
        }
        XCTAssertEqual(FSRS.decay, golden.constants.decay, accuracy: 1e-12)
        XCTAssertEqual(FSRS.factor, golden.constants.factor, accuracy: 1e-12)
        XCTAssertEqual(FSRS.suppressionHorizonDays,
                       golden.constants.suppression_horizon_days, accuracy: 1e-12)
        XCTAssertEqual(FSRS.secondsPerDay, golden.constants.seconds_per_day, accuracy: 1e-12)
    }

    func testEfficacyWeightsMatch() throws {
        let golden = try loadGolden()
        for channel in Channel.allCases {
            guard let expected = golden.eta[channel.rawValue] else {
                XCTFail("no golden eta for \(channel.rawValue)")
                continue
            }
            XCTAssertEqual(channel.eta, expected, accuracy: 1e-12, channel.rawValue)
        }
        // The one that matters most: tapping Insert must be worth nothing.
        XCTAssertEqual(Channel.inserted.eta, 0.0)
    }

    func testScalarVectors() throws {
        let golden = try loadGolden()
        let tolerance = golden.tolerance
        var checked = 0

        for vector in golden.scalars {
            let actual: Double
            switch vector.fn {
            case "retrievability":
                actual = FSRS.retrievability(stability: vector.stability!,
                                             elapsedDays: vector.elapsed_days!)
            case "initial_stability":
                actual = FSRS.initialStability(grade: Grade(rawValue: vector.grade!)!)
            case "initial_difficulty":
                actual = FSRS.initialDifficulty(grade: Grade(rawValue: vector.grade!)!)
            case "next_difficulty":
                actual = FSRS.nextDifficulty(vector.difficulty!,
                                             grade: Grade(rawValue: vector.grade!)!)
            case "stability_after_success":
                actual = FSRS.stabilityAfterSuccess(stability: vector.stability!,
                                                    difficulty: vector.difficulty!,
                                                    r: vector.r!,
                                                    grade: Grade(rawValue: vector.grade!)!)
            case "stability_after_failure":
                actual = FSRS.stabilityAfterFailure(stability: vector.stability!,
                                                    difficulty: vector.difficulty!, r: vector.r!)
            case "stability_after_exposure":
                actual = FSRS.stabilityAfterExposure(stability: vector.stability!,
                                                     difficulty: vector.difficulty!,
                                                     r: vector.r!, eta: vector.eta!)
            case "difficulty_prior":
                actual = FSRS.difficultyPrior(zipf: vector.zipf!,
                                              cognateMax: vector.cognate_max!,
                                              falseFriend: vector.false_friend ?? false)
            case "stability_prior":
                actual = FSRS.stabilityPrior(cognateMax: vector.cognate_max!)
            default:
                XCTFail("unknown golden function \(vector.fn)")
                continue
            }
            XCTAssertEqual(actual, vector.expect, accuracy: tolerance,
                           "\(vector.fn) expected \(vector.expect), got \(actual)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 300, "golden vectors look truncated")
    }

    /// Replays whole event histories and compares every intermediate state.
    /// This is what catches routing bugs, which scalar vectors cannot see: an
    /// exposure leaking into the production trace produces perfectly correct
    /// arithmetic applied to the wrong trace.
    func testScenarios() throws {
        let golden = try loadGolden()
        let tolerance = golden.tolerance

        for scenario in golden.scenarios {
            var item = Item.new(key: "golden",
                                zipf: scenario.features.zipf,
                                cognateMax: scenario.features.cognate_max,
                                falseFriend: scenario.features.false_friend ?? false,
                                now: 0)

            for (index, step) in scenario.steps.enumerated() {
                let now = step.day * FSRS.secondsPerDay
                guard let channel = Channel(rawValue: step.channel),
                      let grade = Grade(rawValue: step.grade) else {
                    XCTFail("bad golden step in \(scenario.name)")
                    continue
                }
                item.observe(channel, now: now, grade: grade)

                let label = "\(scenario.name) step \(index) (\(step.channel) day \(step.day))"
                assertTrace(item.recognition, step.recognition, now: now,
                            tolerance: tolerance, label: "\(label) recognition")
                assertTrace(item.production, step.production, now: now,
                            tolerance: tolerance, label: "\(label) production")
                XCTAssertEqual(item.mastery(now: now), step.mastery, accuracy: tolerance,
                               "\(label) mastery")
                XCTAssertEqual(item.shouldSuppress(now: now), step.suppress, "\(label) suppress")
            }
        }
    }

    private func assertTrace(_ actual: Trace, _ expected: Golden.Snapshot,
                             now: TimeInterval, tolerance: Double, label: String) {
        XCTAssertEqual(actual.stability, expected.stability, accuracy: tolerance,
                       "\(label) stability")
        XCTAssertEqual(actual.difficulty, expected.difficulty, accuracy: tolerance,
                       "\(label) difficulty")
        XCTAssertEqual(actual.reps, expected.reps, "\(label) reps")
        XCTAssertEqual(actual.lapses, expected.lapses, "\(label) lapses")
        XCTAssertEqual(actual.exposures, expected.exposures, "\(label) exposures")
        XCTAssertEqual(actual.effectiveReps, expected.effective_reps, accuracy: tolerance,
                       "\(label) effectiveReps")
        XCTAssertEqual(actual.lastGradedFailed, expected.last_graded_failed,
                       "\(label) lastGradedFailed")
        XCTAssertEqual(actual.retrievability(now: now), expected.retrievability,
                       accuracy: tolerance, "\(label) retrievability")
    }
}
