import Foundation

/// A documented cross-linguistic trap: a Spanish word that looks like something
/// the learner knows and means something else.
public struct Trap: Sendable, Codable, Equatable {
    public let es: String
    public let means: String
    public let trap: String
    public let want: String
    public let italianLookalike: String?
    public let language: String

    enum CodingKeys: String, CodingKey {
        case es, means, trap, want
        case italianLookalike = "it_lookalike"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        es = try container.decode(String.self, forKey: .es)
        means = try container.decode(String.self, forKey: .means)
        trap = try container.decode(String.self, forKey: .trap)
        want = try container.decode(String.self, forKey: .want)
        italianLookalike = try container.decodeIfPresent(String.self, forKey: .italianLookalike)
        language = ""
    }

    init(es: String, means: String, trap: String, want: String,
         italianLookalike: String?, language: String) {
        self.es = es
        self.means = means
        self.trap = trap
        self.want = want
        self.italianLookalike = italianLookalike
        self.language = language
    }

    /// What the learner reads. Says the wrong meaning and then the right word,
    /// because knowing only that a word is a trap leaves them stuck mid-sentence.
    public var explanation: String {
        let looksLike = italianLookalike ?? trap
        return "looks like \(looksLike), actually means \(means). For \(trap), use \(want)."
    }

    /// Why the selector picked this word. Kept byte-identical to the reference
    /// implementation's string in `tools/engine/focus.py`, because the behaviour
    /// tests match on it and a paraphrase here would silently pass on one side
    /// and fail on the other.
    public var reasonLine: String {
        let looksLike = italianLookalike ?? trap
        return "false friend: looks like '\(looksLike)', actually means '\(means)'"
    }
}

/// The curated false-friend list.
///
/// This is the AUTHORITY on what is a false friend. The orthographic cognate
/// score is not, and must never be used as one: it is semantics-free by design,
/// and 90% of common Spanish lemmas score high on it for an Italian speaker.
/// Treating "looks Italian" as "means something else" flags `llegar`~`legare`
/// and `comprar`~`comprare`, which are true cognates and exactly the words a
/// learner gets for free.
///
/// These lemmas are also force-included in the morphology build, because false
/// friends are low frequency by nature and a frequency-ranked cut drops exactly
/// the words this product is best placed to teach.
public struct Interference: Sendable {

    public private(set) var byLemma: [String: Trap] = [:]

    private struct Payload: Decodable {
        let italian: [Trap]
        let english: [Trap]
    }

    public init(contentsOf url: URL) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
        for (language, traps) in [("italian", payload.italian), ("english", payload.english)] {
            for trap in traps {
                let key = trap.es.precomposedStringWithCanonicalMapping.lowercased()
                guard byLemma[key] == nil else { continue }
                byLemma[key] = Trap(es: trap.es, means: trap.means, trap: trap.trap,
                                    want: trap.want, italianLookalike: trap.italianLookalike,
                                    language: language)
            }
        }
    }

    /// Load from the same data root as `Tables`.
    public init(root: URL) throws {
        try self.init(contentsOf: root.appendingPathComponent("interference.json"))
    }

    public subscript(lemma: String) -> Trap? {
        byLemma[lemma.precomposedStringWithCanonicalMapping.lowercased()]
    }
}
