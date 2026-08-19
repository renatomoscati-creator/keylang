import Foundation
import LinguaKeyCore

/// The three presentations of the same selected focus.
///
/// Never a different focus: the selector runs identically in all three arms, so
/// the only variable is what the learner sees. C will feel broken, because it
/// shows nothing. It is a third of the data and it is the only thing that makes
/// A and B mean anything.
public enum Arm: String, Codable, Sendable, CaseIterable {
    case recognition = "A"   // the gloss is shown
    case retrieval = "B"     // the learner is asked first, gloss revealed after
    case control = "C"       // nothing is shown, the exposure is logged
}

/// The cold-start priors for an item, recorded on the event that first creates
/// it so the log is self-contained.
///
/// Without this the fold would need the 3.7 MB tables to replay, which would tie
/// the analysis in Phase 08 to whatever the data build looked like that day.
public struct ItemFeatures: Codable, Sendable, Equatable {
    public let zipf: Double
    public let cognateMax: Double
    public let falseFriend: Bool
    public let isConstruction: Bool
    public let irregular: Bool
    public let length: Int

    public init(zipf: Double, cognateMax: Double, falseFriend: Bool = false,
                isConstruction: Bool = false, irregular: Bool = false, length: Int = 0) {
        self.zipf = zipf
        self.cognateMax = cognateMax
        self.falseFriend = falseFriend
        self.isConstruction = isConstruction
        self.irregular = irregular
        self.length = length
    }
}

/// One thing that happened, written once and never modified.
public struct Event: Codable, Sendable, Equatable {

    /// Bumped when a field's meaning changes, never when one is added. Readers
    /// skip records from a schema they do not understand rather than guessing.
    public static let currentSchema = 1

    public let schema: Int
    public let id: UUID
    /// Seconds since 1970, from the device clock. See the caveat in PLAN.md: a
    /// manual clock change corrupts intervals and nothing here detects it.
    public let at: TimeInterval
    public let itemKey: String
    public let channel: Channel
    /// nil for ungraded channels. A grade on an exposure would be a bug.
    public let grade: Grade?
    public let arm: Arm
    /// The form actually seen, which is not the lemma: `llegaré`, not `llegar`.
    public let surface: String
    /// Present only on the event that first creates the item.
    public let features: ItemFeatures?
    public let sourceApp: String?
    /// So repeated study of one sentence is detectable without storing the
    /// sentence. The user's own messages are not this app's to keep.
    public let sentenceHash: UInt64

    public init(id: UUID = UUID(), at: TimeInterval, itemKey: String, channel: Channel,
                grade: Grade? = nil, arm: Arm, surface: String,
                features: ItemFeatures? = nil, sourceApp: String? = nil,
                sentenceHash: UInt64 = 0) {
        self.schema = Event.currentSchema
        self.id = id
        self.at = at
        self.itemKey = itemKey
        self.channel = channel
        self.grade = grade
        self.arm = arm
        self.surface = surface
        self.features = features
        self.sourceApp = sourceApp
        self.sentenceHash = sentenceHash
    }
}
