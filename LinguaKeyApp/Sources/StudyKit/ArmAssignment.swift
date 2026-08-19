import Foundation

/// Which arm an item belongs to.
///
/// Deterministic, so it survives a reinstall with the same salt; item-level, so
/// one user generates all three arms; and recorded in the event rather than
/// looked up later, so a change to this function cannot retroactively rewrite
/// history.
public struct ArmAssignment: Sendable, Equatable {

    public let salt: String

    public init(salt: String) {
        self.salt = salt
    }

    /// FNV-1a, 64 bit, over UTF-8.
    ///
    /// Not `Hasher`. Swift's `Hasher` is seeded per process, so `hashValue` for
    /// the same string differs between the app and the share extension and
    /// between launches. Using it here would reassign arms constantly while
    /// looking like working code, and would destroy the experiment silently.
    /// This is the single most important line in the file.
    public static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }

    public func arm(for itemKey: String) -> Arm {
        // A separator that cannot occur in either half, so salt "ab" + key "c"
        // and salt "a" + key "bc" are different inputs.
        switch ArmAssignment.fnv1a64("\(salt)\u{1}\(itemKey)") % 3 {
        case 0: return .recognition
        case 1: return .retrieval
        default: return .control
        }
    }

    /// Reads the install salt, creating it once if it is not there.
    ///
    /// Written to the App Group so both processes agree. If it is ever lost the
    /// arms all reshuffle, which is why it is a separate file that nothing else
    /// writes rather than a key in a defaults dictionary something might clear.
    public static func load(_ storage: Storage) throws -> ArmAssignment {
        try storage.createIfNeeded()
        if let existing = try? String(contentsOf: storage.salt, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return ArmAssignment(salt: trimmed) }
        }
        let fresh = UUID().uuidString
        try fresh.write(to: storage.salt, atomically: true, encoding: .utf8)
        return ArmAssignment(salt: fresh)
    }
}
