import Foundation

/// One memory trace: a (Difficulty, Stability) pair plus the evidence behind it.
///
/// `mastery` is never stored. A stored float cannot decay, which was the core
/// defect in the PRD's original model: `mastery: 0.72` meant the same thing
/// three days later and eight months later. Retrievability is computed from
/// stability and elapsed time on every read.
public struct Trace: Sendable, Codable, Equatable {
    public var stability: Double
    public var difficulty: Double
    public var lastEventAt: TimeInterval

    /// Graded events only.
    public var reps: Int = 0
    public var lapses: Int = 0

    /// Diagnostic ONLY. Never feeds a threshold. Counting exposures as evidence
    /// is the failure mode that makes assistance fade for words the learner
    /// never learned, and then stops collecting the evidence that would correct
    /// the mistake.
    public var exposures: Int = 0

    /// Sum of efficacy weights. The honest evidence count.
    public var effectiveReps: Double = 0

    /// Whether the most recent graded outcome was a failure. A fresh lapse is a
    /// direct statement that the learner could not produce this, and no
    /// projected probability should be allowed to talk over it.
    public var lastGradedFailed: Bool = false

    public init(stability: Double, difficulty: Double, lastEventAt: TimeInterval) {
        self.stability = stability
        self.difficulty = difficulty
        self.lastEventAt = lastEventAt
    }

    public func retrievability(now: TimeInterval) -> Double {
        FSRS.retrievability(stability: stability,
                            elapsedDays: (now - lastEventAt) / FSRS.secondsPerDay)
    }
}

/// A learnable item with one trace per modality.
///
/// Two traces because receptive knowledge systematically exceeds productive, and
/// this product's stated goal is production. A single trace would let a word the
/// learner has only ever recognised count as known, and the system would go
/// quiet on exactly the words it should still be teaching.
public struct Item: Sendable, Codable, Equatable {
    public let key: String
    public var recognition: Trace
    public var production: Trace

    public init(key: String, recognition: Trace, production: Trace) {
        self.key = key
        self.recognition = recognition
        self.production = production
    }

    public subscript(modality: Modality) -> Trace {
        get { modality == .recognition ? recognition : production }
        set { if modality == .recognition { recognition = newValue } else { production = newValue } }
    }

    /// A fresh item, initialised from item features rather than from a first
    /// grade, because with incidental exposure there is often no grade at all.
    public static func new(key: String, zipf: Double, cognateMax: Double,
                           falseFriend: Bool = false, length: Int = 0,
                           isConstruction: Bool = false, irregular: Bool = false,
                           now: TimeInterval = 0) -> Item {
        let difficulty = FSRS.difficultyPrior(zipf: zipf, cognateMax: cognateMax,
                                              falseFriend: falseFriend, length: length,
                                              isConstruction: isConstruction,
                                              irregular: irregular)
        let stability = FSRS.stabilityPrior(cognateMax: cognateMax)
        let trace = Trace(stability: stability, difficulty: difficulty, lastEventAt: now)
        return Item(key: key, recognition: trace, production: trace)
    }

    /// Derived for display only. NEVER a decision variable.
    /// Weighted toward production because that is the product's stated goal.
    public func mastery(now: TimeInterval) -> Double {
        0.35 * recognition.retrievability(now: now) + 0.65 * production.retrievability(now: now)
    }

    /// Whether to stay quiet about this item.
    ///
    /// Retrievability is evaluated at a HORIZON, not at `now`. Immediately after
    /// any event elapsed time is zero and retrievability is 1.0 by definition,
    /// including immediately after a FAILED recall, so asking "do they know it
    /// this instant" would suppress the item the user just got wrong.
    ///
    /// Evidence must be real, which is the guard against exposure-counted-as-
    /// learning. Exposures contribute at most their efficacy weight, so reaching
    /// the floor by being glanced at takes an implausible number of glances.
    public func shouldSuppress(now: TimeInterval, threshold: Double = 0.90,
                               minEvidence: Double = 2.0,
                               horizonDays: Double = FSRS.suppressionHorizonDays) -> Bool {
        guard !production.lastGradedFailed else { return false }
        let future = now + horizonDays * FSRS.secondsPerDay
        let elapsed = (future - production.lastEventAt) / FSRS.secondsPerDay
        let projected = FSRS.retrievability(stability: production.stability, elapsedDays: elapsed)
        return projected >= threshold && production.effectiveReps >= minEvidence
    }

    /// Apply one observation. Returns which traces moved.
    ///
    /// Routing is the load-bearing part. Exposures reach recognition only:
    /// production is never inferred from having been shown something. A recall
    /// or unprompted production grades production in full and credits
    /// recognition at half, because producing a word is strong but indirect
    /// evidence that you recognise it.
    @discardableResult
    public mutating func observe(_ channel: Channel, now: TimeInterval,
                                 grade: Grade = .good) -> [Modality] {
        guard channel.eta > 0 else { return [] }

        if channel.isGraded {
            applyGraded(.production, grade: grade, now: now)
            guard grade != .again else { return [.production] }
            applyExposure(.recognition, eta: 0.5, now: now)
            return [.production, .recognition]
        }

        applyExposure(.recognition, eta: channel.eta, now: now)
        recognition.exposures += 1
        return [.recognition]
    }

    private mutating func applyGraded(_ modality: Modality, grade: Grade, now: TimeInterval) {
        var trace = self[modality]
        let elapsed = (now - trace.lastEventAt) / FSRS.secondsPerDay
        let r = FSRS.retrievability(stability: trace.stability, elapsedDays: elapsed)

        if trace.reps == 0 && trace.effectiveReps == 0 {
            trace.stability = FSRS.initialStability(grade: grade)
            trace.difficulty = FSRS.initialDifficulty(grade: grade)
            trace.lastGradedFailed = grade == .again
            if grade == .again { trace.lapses += 1 }
        } else if grade == .again {
            trace.stability = FSRS.stabilityAfterFailure(stability: trace.stability,
                                                         difficulty: trace.difficulty, r: r)
            trace.difficulty = FSRS.nextDifficulty(trace.difficulty, grade: grade)
            trace.lapses += 1
            trace.lastGradedFailed = true
        } else if elapsed < 1.0 / 24.0 {
            trace.stability = FSRS.stabilitySameDay(stability: trace.stability, grade: grade)
            trace.difficulty = FSRS.nextDifficulty(trace.difficulty, grade: grade)
            trace.lastGradedFailed = false
        } else {
            trace.stability = FSRS.stabilityAfterSuccess(stability: trace.stability,
                                                         difficulty: trace.difficulty,
                                                         r: r, grade: grade)
            trace.difficulty = FSRS.nextDifficulty(trace.difficulty, grade: grade)
            trace.lastGradedFailed = false
        }

        trace.reps += 1
        trace.effectiveReps += 1
        trace.lastEventAt = now
        self[modality] = trace
    }

    private mutating func applyExposure(_ modality: Modality, eta: Double, now: TimeInterval) {
        var trace = self[modality]
        let elapsed = (now - trace.lastEventAt) / FSRS.secondsPerDay
        let r = FSRS.retrievability(stability: trace.stability, elapsedDays: elapsed)
        trace.stability = FSRS.stabilityAfterExposure(stability: trace.stability,
                                                      difficulty: trace.difficulty,
                                                      r: r, eta: eta)
        // Difficulty deliberately untouched.
        trace.effectiveReps += eta
        trace.lastEventAt = now
        self[modality] = trace
    }
}
