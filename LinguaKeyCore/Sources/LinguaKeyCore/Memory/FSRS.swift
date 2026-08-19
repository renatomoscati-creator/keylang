import Foundation

/// FSRS-6 as a memory-state estimator, with attenuated exposures.
///
/// Ported from `tools/engine/fsrs.py` and verified against the golden vectors
/// that file emits. If you change anything here, regenerate the vectors and
/// expect `GoldenVectorTests` to tell you what moved.
///
/// This is not a scheduler. FSRS was built to choose an optimal next interval,
/// and this product cannot make the user message someone about arriving late on
/// day 12. Timing is exogenous, so the model is used for exactly one question,
/// `retrievability(item, modality, now)`, and a separate policy layer decides
/// what to do about the answer.
public enum FSRS {

    /// FSRS-6 defaults, transcribed from `fsrs-rs/src/model.rs`. Do not renumber.
    public static let w: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722,
        0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
        0.0912, 0.0658, 0.1542
    ]

    public static let decay = -w[20]
    public static let factor = exp(log(0.9) / decay) - 1.0

    public static let minStability = 0.001
    public static let minDifficulty = 1.0
    public static let maxDifficulty = 10.0
    public static let secondsPerDay: TimeInterval = 86_400

    /// How far ahead to ask "will they still know this".
    ///
    /// One day is too short to see the damage a lapse does: after a failure that
    /// collapses stability from 20 days to 2.3, retrievability one day later is
    /// still 0.95, which reads as "known". Seven days matches how this product
    /// is used, since the next time an item is genuinely needed is a week away
    /// rather than tomorrow.
    public static let suppressionHorizonDays = 7.0

    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }

    /// Probability of recall now. Power law, not exponential.
    public static func retrievability(stability: Double, elapsedDays: Double) -> Double {
        guard elapsedDays > 0 else { return 1.0 }
        return pow(elapsedDays / max(stability, minStability) * factor + 1.0, decay)
    }

    /// Days until retrievability falls to `desiredRetention`.
    public static func interval(stability: Double, desiredRetention: Double) -> Double {
        stability / factor * (pow(desiredRetention, 1.0 / decay) - 1.0)
    }

    public static func initialStability(grade: Grade) -> Double {
        max(w[grade.rawValue - 1], minStability)
    }

    public static func initialDifficulty(grade: Grade) -> Double {
        clamp(w[4] - exp(w[5] * Double(grade.rawValue - 1)) + 1.0, minDifficulty, maxDifficulty)
    }

    static func dampen(_ delta: Double, _ difficulty: Double) -> Double {
        (10.0 - difficulty) * delta / 9.0
    }

    public static func nextDifficulty(_ difficulty: Double, grade: Grade) -> Double {
        let moved = difficulty + dampen(-w[6] * Double(grade.rawValue - 3), difficulty)
        let reverted = w[7] * (initialDifficulty(grade: .easy) - moved) + moved
        return clamp(reverted, minDifficulty, maxDifficulty)
    }

    /// The bracket shared by graded success and attenuated exposure.
    ///
    /// `(exp((1 - r) * w[10]) - 1)` is the spacing effect: it goes to zero as `r`
    /// goes to one, so a repetition of something already known perfectly is
    /// worth almost nothing. That property is what makes it safe to feed noisy
    /// incidental exposures into a model built for graded review.
    static func growth(stability: Double, difficulty: Double, r: Double) -> Double {
        exp(w[8]) * (11.0 - difficulty) * pow(stability, -w[9]) * (exp((1.0 - r) * w[10]) - 1.0)
    }

    public static func stabilityAfterSuccess(stability: Double, difficulty: Double,
                                             r: Double, grade: Grade) -> Double {
        let hard = grade == .hard ? w[15] : 1.0
        let easy = grade == .easy ? w[16] : 1.0
        let value = stability * (growth(stability: stability, difficulty: difficulty, r: r)
                                 * hard * easy + 1.0)
        return max(value, minStability)
    }

    public static func stabilityAfterFailure(stability: Double, difficulty: Double,
                                             r: Double) -> Double {
        let longTerm = w[11] * pow(difficulty, -w[12])
            * (pow(stability + 1.0, w[13]) - 1.0) * exp((1.0 - r) * w[14])
        let shortTerm = stability / exp(w[17] * w[18])
        return max(min(longTerm, shortTerm), minStability)
    }

    public static func stabilitySameDay(stability: Double, grade: Grade) -> Double {
        let value = stability * max(1.0, exp(w[17] * (Double(grade.rawValue) - 3 + w[18]))
                                    * pow(stability, -w[19]))
        return max(value, minStability)
    }

    /// An ungraded exposure. Difficulty deliberately does not move: seeing a word
    /// is no evidence about how hard it is.
    public static func stabilityAfterExposure(stability: Double, difficulty: Double,
                                              r: Double, eta: Double) -> Double {
        guard eta > 0 else { return stability }
        let value = stability * (eta * growth(stability: stability, difficulty: difficulty,
                                              r: r) + 1.0)
        return max(value, minStability)
    }

    // MARK: - Cold start

    /// Difficulty before any evidence, from item features.
    ///
    /// The cheapest high-value piece of the design: without it every unseen word
    /// starts at maximum difficulty and the one-item-per-sentence teaching
    /// budget gets spent explaining `hotel` and `taxi`.
    ///
    /// `falseFriend` RAISES difficulty because the trap is in the meaning.
    /// Research 06 found false cognates are easier on FORM and harder on
    /// MEANING, which is also why the two traces are scored separately.
    public static func difficultyPrior(zipf: Double, cognateMax: Double,
                                       falseFriend: Bool = false, length: Int = 0,
                                       isConstruction: Bool = false,
                                       irregular: Bool = false) -> Double {
        let value = 5.0
            - 0.45 * (zipf - 4.0)
            - 2.20 * cognateMax
            + 1.40 * (falseFriend ? 1.0 : 0.0)
            + 0.30 * (length > 9 ? 1.0 : 0.0)
            + 0.60 * (isConstruction ? 1.0 : 0.0)
            + 0.80 * (irregular ? 1.0 : 0.0)
        return clamp(value, minDifficulty, maxDifficulty)
    }

    /// Cognates start stickier, because they already hook onto something known.
    public static func stabilityPrior(cognateMax: Double) -> Double {
        clamp(0.4 * exp(1.1 * cognateMax), 0.4, 4.0)
    }
}

public enum Grade: Int, Sendable, Codable {
    case again = 1, hard = 2, good = 3, easy = 4
}

public enum Modality: Int, Sendable, Codable {
    case recognition = 0, production = 1
}

/// How an observation reached us. Determines efficacy and which trace moves.
public enum Channel: String, Sendable, Codable, CaseIterable {
    case exposeGlanced = "EXPOSE_GLANCED"   // shown, no interaction, under 800 ms
    case exposeDwelled = "EXPOSE_DWELLED"   // shown, visible >= 1.5 s
    case tapped = "TAPPED"                  // tapped for a breakdown, gloss or audio
    case inserted = "INSERTED"              // tapped Insert. Copying is not producing.
    case recall = "RECALL"                  // answered a recall prompt
    case produced = "PRODUCED"              // typed the Spanish unprompted
    case corrected = "CORRECTED"            // a Mode E correction was accepted

    /// Efficacy weight. Priors to be FITTED from the event log, not facts.
    ///
    /// The roughly 10:1 exposure-to-review ratio operationalises the
    /// meta-analytic finding that repetition explains only 12-17% of the
    /// variance in incidental vocabulary learning.
    ///
    /// `inserted` is deliberately zero. The user needed the Spanish, the system
    /// supplied it without retrieval, and the log would otherwise record "sent a
    /// Spanish message", the product's own success metric, while no learning
    /// occurred.
    public var eta: Double {
        switch self {
        case .exposeGlanced: return 0.03
        case .exposeDwelled: return 0.10
        case .tapped:        return 0.30
        case .inserted:      return 0.00
        case .recall, .produced, .corrected: return 1.00
        }
    }

    public var isGraded: Bool {
        switch self {
        case .recall, .produced, .corrected: return true
        default: return false
        }
    }
}
