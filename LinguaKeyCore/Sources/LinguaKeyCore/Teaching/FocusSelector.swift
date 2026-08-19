import Foundation

/// What to teach in one sentence.
///
/// Replaces the PRD's threshold ladder, which was monotone in a single number
/// while its own stated requirements were multi-objective, and which handed the
/// least effective gloss format to the newest items.
///
///     value = learning gain x need x novelty x readiness - intrusion
///
/// Deterministic on purpose. A scoring function can be ablated and reproduces
/// exactly on identical input; an LLM's choice of focus word can do neither,
/// which would make the A/B evaluation arms meaningless.
public struct Candidate: Sendable, Equatable {
    public let surface: String
    public let lemma: String
    public let key: String
    public let kind: Kind
    public let score: Double
    public let reason: String
    public let gloss: String
    public let feats: String
    public let trap: Trap?
    /// Carried through so the caller can seed a cold-start item without a second
    /// table lookup, and so the event that creates the item can record the priors
    /// it was created from.
    public let zipf: Double
    public let cognateMax: Double

    public enum Kind: String, Sendable { case vocabulary, grammar }

    public init(surface: String, lemma: String, key: String, kind: Kind, score: Double,
                reason: String, gloss: String, feats: String, trap: Trap?,
                zipf: Double, cognateMax: Double) {
        self.surface = surface
        self.lemma = lemma
        self.key = key
        self.kind = kind
        self.score = score
        self.reason = reason
        self.gloss = gloss
        self.feats = feats
        self.trap = trap
        self.zipf = zipf
        self.cognateMax = cognateMax
    }
}

public struct FocusSelector: Sendable {

    /// At most one vocabulary concept and one grammar note per sentence. Kept
    /// from the PRD, which was right about this and stricter than most products.
    public static let budgetVocabulary = 1
    public static let budgetGrammar = 1

    /// Below this, teach nothing.
    ///
    /// PRD section 25 asks for the learning UI to disappear when it has nothing
    /// useful to teach, and that needs a number to be real. Without a floor the
    /// selector always returns its best-of-a-bad-lot, so a sentence containing
    /// only known words still gets annotated and the bar becomes something to
    /// ignore. Research 06 predicts banner blindness within weeks; a bar that is
    /// quiet most of the time is what buys attention when it does speak.
    public static let minTeachingValue = 0.85

    /// Above this Zipf a word is acquired from exposure alone. `ser` and `estar`
    /// are not vocabulary lessons however common they are.
    public static let freeByExposureZipf = 6.6

    /// Function words carry the grammar, not the vocabulary.
    static let skipPOS: Set<String> = ["PREP", "CONJ", "DET", "ART", "PRON",
                                       "PROP", "NUM", "CONTR"]

    /// A paradigm cell is only worth a note when the cell itself carries a
    /// lesson. "masculine singular noun" is not a lesson; "first person singular
    /// present subjunctive" is. Without this filter every sentence produces a
    /// grammar note about noun gender, which burns the one-note budget on noise.
    static let teachableCellTags: Set<String> = [
        "IND", "SBJV", "IMP", "COND", "FUT", "PST", "PRS", "IPFV", "PFV",
        "V.CVB", "V.PTCP", "NFIN"
    ]

    private let tables: Tables
    private let interference: Interference

    public init(tables: Tables, interference: Interference) {
        self.tables = tables
        self.interference = interference
    }

    public static func tokenize(_ sentence: String) -> [String] {
        sentence.precomposedStringWithCanonicalMapping
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
    }

    /// Choose one reading, and say whether the choice was ambiguous.
    ///
    /// Most-frequent-lemma is the honest baseline. The real disambiguators are
    /// NLTagger's context-sensitive tag and the translator-alignment check
    /// (translate the focus word alone, see whether it appears in the sentence
    /// translation), neither of which lives in this package.
    static func pickReading(_ readings: [Reading]) -> (Reading, Bool)? {
        guard var best = readings.first else { return nil }
        // Strictly-greater, so the FIRST maximal reading wins. Swift's
        // `max(by:)` keeps the LAST one, and the reference implementation is
        // Python's `max`, which keeps the first. On a tie the two would pick
        // different lemmas and the behaviour tests would disagree for no
        // discoverable reason.
        func rank(_ r: Reading) -> (Double, Int) { (r.zipf, r.hasFeatures ? 1 : 0) }
        for reading in readings.dropFirst() where rank(reading) > rank(best) {
            best = reading
        }
        let lemmas = Set(readings.map(\.lemma))
        return (best, lemmas.count > 1)
    }

    func score(_ reading: Reading, item: Item?, now: TimeInterval,
               ambiguous: Bool, seenThisSession: Int) -> (Double, String) {
        let gain: Double
        let readiness: Double
        let r: Double
        var evidence = 0.0

        if let item {
            let trace = item.production
            r = trace.retrievability(now: now)
            gain = FSRS.growth(stability: trace.stability, difficulty: trace.difficulty, r: r)
            readiness = 1.0 - abs(r - 0.85) / 0.85
            evidence = trace.effectiveReps
        } else {
            // An unseen item is assumed maximally retrievable, which keeps it
            // out of the "due for review" branch below; its gain and readiness
            // are the flat newcomer priors.
            r = 1.0
            gain = 1.0
            readiness = 0.6
        }

        var need = min(1.0, reading.zipf / 7.0)
        let novelty = 1.0 - reading.cognateMax

        // A false friend is worth teaching precisely BECAUSE it looks familiar,
        // so this is the one place similarity raises the score. Membership in the
        // curated list is the test, never the orthographic score.
        let trap = interference[reading.lemma]
        let trapBonus = trap != nil ? 0.9 : 0.0

        if reading.zipf >= FocusSelector.freeByExposureZipf && trap == nil {
            need *= 0.15
        }

        var intrusion = 0.35 * Double(seenThisSession)
        if ambiguous {
            // Teaching the wrong sense is worse than teaching nothing.
            intrusion += 0.4
        }

        let value = 0.45 * gain + 0.25 * need + 0.20 * novelty + 0.10 * readiness
            + trapBonus - intrusion

        let reason: String
        if let trap {
            reason = trap.reasonLine
        } else if reading.zipf >= FocusSelector.freeByExposureZipf {
            reason = "very common, acquired from exposure"
        } else if novelty > 0.6 {
            reason = "not a cognate, genuinely new"
        } else if evidence > 0 && r < 0.85 {
            reason = "due for review"
        } else if need > 0.8 {
            reason = "very common"
        } else {
            reason = "useful"
        }
        return (value, reason)
    }

    /// Pick at most one vocabulary item and one grammar note for this sentence.
    public func select(sentence: String, state: [String: Item], now: TimeInterval,
                       sessionCounts: [String: Int] = [:]) -> [Candidate] {

        // Ask the memory model whether to stay quiet. This has to be a hard veto
        // rather than a score adjustment: a false friend carries a large constant
        // bonus, so without it a trap the learner has demonstrably mastered would
        // keep being taught forever, which is the "assistance never fades"
        // complaint the adaptive design exists to fix.
        func suppressed(_ key: String) -> Bool {
            state[key]?.shouldSuppress(now: now) ?? false
        }

        var vocabulary: [Candidate] = []
        var grammar: [Candidate] = []

        for surface in FocusSelector.tokenize(sentence) {
            guard let (reading, ambiguous) = FocusSelector.pickReading(tables.lookup(surface)),
                  !FocusSelector.skipPOS.contains(reading.pos) else { continue }

            // A suppressed lemma silences the whole token, grammar note
            // included. Annotating the paradigm cell of a word the learner has
            // demonstrably mastered still puts a bar on screen about a word they
            // know, which is the thing suppression exists to stop.
            let key = reading.lemmaKey
            if suppressed(key) { continue }

            let (value, reason) = score(reading, item: state[key], now: now,
                                        ambiguous: ambiguous,
                                        seenThisSession: sessionCounts[key] ?? 0)
            vocabulary.append(Candidate(
                surface: surface, lemma: reading.lemma, key: key, kind: .vocabulary,
                score: value, reason: reason, gloss: reading.gloss,
                feats: reading.feats, trap: interference[reading.lemma],
                zipf: reading.zipf, cognateMax: reading.cognateMax))

            let tags = Set(reading.feats.split(separator: ";").dropFirst().map(String.init))
            if let cell = reading.cellKey, !suppressed(cell),
               !tags.isDisjoint(with: FocusSelector.teachableCellTags) {
                let (base, reason) = score(reading, item: state[cell], now: now,
                                           ambiguous: ambiguous,
                                           seenThisSession: sessionCounts[cell] ?? 0)
                // A paradigm cell is worth teaching when the FORM is the new
                // thing, which is exactly when the lemma itself is familiar.
                let value = base + 0.3 * reading.cognateMax
                grammar.append(Candidate(
                    surface: surface, lemma: reading.lemma, key: cell, kind: .grammar,
                    score: value, reason: reason, gloss: reading.gloss,
                    feats: reading.feats, trap: nil,
                    zipf: reading.zipf, cognateMax: reading.cognateMax))
            }
        }

        // Highest score first, ties broken by position in the sentence.
        // `Array.sort` is not guaranteed stable and the reference implementation
        // is Python's `list.sort`, which is; without the index tie-break two
        // words that score identically could be ordered differently by the two
        // implementations, and the behaviour tests would disagree on input that
        // is not obviously a tie.
        func byScoreThenPosition(_ list: inout [Candidate]) {
            list = list.enumerated()
                .sorted { ($0.element.score, -Double($0.offset))
                        > ($1.element.score, -Double($1.offset)) }
                .map(\.element)
        }
        byScoreThenPosition(&vocabulary)
        byScoreThenPosition(&grammar)

        var chosen = Array(vocabulary
            .filter { $0.score >= FocusSelector.minTeachingValue }
            .prefix(FocusSelector.budgetVocabulary))

        // Never let the grammar note land on the same word as the vocabulary
        // note. Two annotations on one token reads as clutter and violates the
        // budget's intent even while satisfying its letter.
        let taken = Set(chosen.map(\.surface))
        chosen += grammar
            .filter { !taken.contains($0.surface) && $0.score >= FocusSelector.minTeachingValue }
            .prefix(FocusSelector.budgetGrammar)

        return chosen
    }
}
