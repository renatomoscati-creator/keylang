import Foundation

/// Where the log and the snapshot live.
///
/// Everything takes a `Storage` rather than reaching for the App Group directly,
/// because the tests must be able to point the whole store at a temporary
/// directory. `Storage.shared` is the only thing in this package that knows an
/// App Group exists.
public struct Storage: Sendable {

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var eventLog: URL { root.appendingPathComponent("events.jsonl") }
    public var snapshot: URL { root.appendingPathComponent("items.snapshot.json") }
    public var salt: URL { root.appendingPathComponent("install-salt.txt") }
    /// Where the app copies the staged tables on first launch, so the extension
    /// can `mmap` them without carrying a second copy in its own bundle.
    public var data: URL { root.appendingPathComponent("LinguaKeyData") }

    public func createIfNeeded() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// The App Group container, or nil when the entitlement is missing.
    ///
    /// The group identifier is read from `Info.plist` rather than hardcoded.
    /// `ALTAppGroups` is checked first because sideloading tools rewrite group
    /// identifiers to append the signing Team ID, and a hardcoded string would
    /// silently resolve to a container nobody else writes to. The same rule the
    /// probe harness uses.
    public static func appGroupIdentifier(_ bundle: Bundle = .main) -> String? {
        if let rewritten = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
           let first = rewritten.first {
            return first
        }
        return bundle.object(forInfoDictionaryKey: "LKAppGroup") as? String
    }

    public static func shared(_ bundle: Bundle = .main) -> Storage? {
        guard let identifier = appGroupIdentifier(bundle),
              let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            return nil
        }
        return Storage(root: container.appendingPathComponent("StudyKit"))
    }
}
