import Foundation

/// Append-only probe log, shared by the host app and the keyboard extension.
///
/// Every observation is one line in the contract shape:
///     PROBE <id> | <key> | <value> | <note>
///
/// The keyboard extension is deliberately killed by jetsam during P2, so console
/// output dies with it. Every write is flushed immediately. A probe whose result
/// you cannot read after a kill has not run.
enum ProbeLog {

    // MARK: - Container resolution

    /// App Group identifier, read from Info.plist rather than hardcoded.
    ///
    /// Free-tier sideloaders rewrite group IDs to append the Team ID
    /// (`group.foo` -> `group.foo.ABCDE12345`) and inject the rewritten list into
    /// Info.plist as `ALTAppGroups`. Hardcoding the string breaks the container
    /// lookup after sideloading.
    static var appGroupID: String? {
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
           let first = groups.first {
            return first
        }
        return Bundle.main.object(forInfoDictionaryKey: "ProbeAppGroup") as? String
    }

    /// Where the log actually lives.
    ///
    /// Prefers the shared container so the host app can read what the keyboard
    /// wrote. Falls back to the process's own container, which is what happens
    /// without Full Access: Apple documents the sandbox as preventing writes to
    /// the shared group container (reads are permitted). That fallback is itself
    /// a finding, and `containerKind` records which one we got.
    static let (logURL, containerKind): (URL, String) = {
        if let group = appGroupID,
           let shared = FileManager.default
               .containerURL(forSecurityApplicationGroupIdentifier: group) {
            let candidate = shared.appendingPathComponent("probe-log.txt")
            if isWritable(candidate) { return (candidate, "appgroup") }
        }
        let local = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("probe-log.txt")
        return (local, "local")
    }()

    private static func isWritable(_ url: URL) -> Bool {
        do {
            let probe = url.deletingLastPathComponent()
                .appendingPathComponent(".writetest")
            try Data().write(to: probe)
            try? FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Writing

    private static let queue = DispatchQueue(label: "probe.log")
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f
    }()

    /// Record one observation. Flushes before returning.
    static func write(_ probe: String, _ key: String, _ value: String, _ note: String = "-") {
        let clean = { (s: String) in
            s.replacingOccurrences(of: "|", with: "/")
             .replacingOccurrences(of: "\n", with: " ")
        }
        let line = "\(stamp.string(from: Date())) PROBE \(probe) | \(clean(key)) | \(clean(value)) | \(clean(note))\n"
        queue.sync {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.synchronize()   // survive the jetsam kill
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
        NSLog("%@", line.trimmingCharacters(in: .newlines))
    }

    /// Record a thrown error with its concrete type, which is the part that
    /// distinguishes "pack not installed" from "sandbox refused".
    static func writeError(_ probe: String, _ key: String, _ error: Error) {
        write(probe, key, "\(type(of: error)): \(error)", "threw")
    }

    static func read() -> String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? "(no log yet at \(logURL.path))"
    }

    static func reset() {
        queue.sync { try? FileManager.default.removeItem(at: logURL) }
    }
}
