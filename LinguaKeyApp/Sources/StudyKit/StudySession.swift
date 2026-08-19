import Foundation
import LinguaKeyCore

/// One selected text, from arriving in the share sheet to being dismissed.
///
/// The selector runs identically in every arm. The arm decides what the learner
/// sees and which events get written, never which word is chosen, because an arm
/// that changed the selection would be measuring two things at once.
public struct StudySession: Sendable {

    /// One chosen candidate plus the arm it landed in.
    public struct Focus: Sendable, Equatable {
        public let candidate: Candidate
        public let arm: Arm
        /// False in the control arm. The word is still on screen inside the
        /// sentence; what is withheld is the teaching.
        public var isTaught: Bool { arm != .control }
    }

    public let sentence: String
    public let sentenceHash: UInt64
    public let sourceApp: String?
    public let focuses: [Focus]
    public let startedAt: TimeInterval

    /// Which channel each arm writes when the focus is first presented.
    ///
    /// Every arm writes `exposeGlanced`, because in every arm the word really was
    /// on screen inside the sentence, and pretending otherwise would bias the
    /// exposure-efficacy fit that Phase 08 exists to run. Only arm A writes
    /// `exposeDwelled` on top, because only arm A shows the gloss unprompted.
    /// Arm B's evidence arrives later, as a grade.
    static func presentationChannels(_ arm: Arm) -> [Channel] {
        switch arm {
        case .recognition: return [.exposeGlanced, .exposeDwelled]
        case .retrieval: return [.exposeGlanced]
        case .control: return [.exposeGlanced]
        }
    }

    public init(sentence: String, selector: FocusSelector, store: ItemStore,
                assignment: ArmAssignment, now: TimeInterval,
                sourceApp: String? = nil, sessionCounts: [String: Int] = [:]) {
        self.sentence = sentence
        self.sentenceHash = ArmAssignment.fnv1a64(
            sentence.precomposedStringWithCanonicalMapping)
        self.sourceApp = sourceApp
        self.startedAt = now
        let chosen = selector.select(sentence: sentence, state: store.items, now: now,
                                     sessionCounts: sessionCounts)
        self.focuses = chosen.map {
            Focus(candidate: $0, arm: assignment.arm(for: $0.key))
        }
    }

    /// What only the learner needs to see. The control arm gets an empty list and
    /// the UI shows the sentence with no bar at all.
    public var taught: [Focus] {
        focuses.filter(\.isTaught)
    }

    // MARK: - Events

    private func features(_ candidate: Candidate) -> ItemFeatures {
        ItemFeatures(zipf: candidate.zipf,
                     cognateMax: candidate.cognateMax,
                     falseFriend: candidate.trap != nil,
                     isConstruction: candidate.kind == .grammar,
                     irregular: false,
                     length: candidate.lemma.count)
    }

    private func event(_ focus: Focus, _ channel: Channel, grade: Grade?,
                       at: TimeInterval, known: Bool) -> Event {
        Event(at: at,
              itemKey: focus.candidate.key,
              channel: channel,
              grade: grade,
              arm: focus.arm,
              surface: focus.candidate.surface,
              // Priors ride on the event that first creates the item and on no
              // other, so the log stays small and the fold stays exact.
              features: known ? nil : features(focus.candidate),
              sourceApp: sourceApp,
              sentenceHash: sentenceHash)
    }

    /// The events written when the session is shown. Written as one batch so a
    /// kill mid-session leaves either all of them or none.
    public func presentationEvents(store: ItemStore, at: TimeInterval? = nil) -> [Event] {
        let when = at ?? startedAt
        var known = Set(store.items.keys)
        var events: [Event] = []
        for focus in focuses {
            for channel in StudySession.presentationChannels(focus.arm) {
                events.append(event(focus, channel, grade: nil, at: when,
                                    known: known.contains(focus.candidate.key)))
                known.insert(focus.candidate.key)
            }
        }
        return events
    }

    /// Arm B answered. The only graded channel this surface produces.
    public func answerEvent(_ focus: Focus, grade: Grade, at: TimeInterval,
                            store: ItemStore) -> Event {
        event(focus, .recall, grade: grade, at: at,
              known: store.items[focus.candidate.key] != nil)
    }

    /// Arm B gave up and revealed. Weaker than an answer and not a grade, which
    /// is the distinction the whole efficacy weighting rests on.
    public func revealEvent(_ focus: Focus, at: TimeInterval, store: ItemStore) -> Event {
        event(focus, .tapped, grade: nil, at: at,
              known: store.items[focus.candidate.key] != nil)
    }
}
