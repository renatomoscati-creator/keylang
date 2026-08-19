import Foundation

/// Copies the linguistic tables from the app bundle into the App Group container
/// once, so the share extension can `mmap` them without carrying its own copy.
///
/// The extension cannot read the app's bundle, and duplicating 3.9 MB into a
/// second bundle would double the download and mean two copies to keep in step.
/// One copy in the shared container is the only arrangement where the extension
/// and the app are guaranteed to be reading the same tables.
public enum DataStaging {

    public enum Outcome: String, Sendable {
        case alreadyCurrent
        case staged
        case restaged
        case missingFromBundle
        case failed
    }

    public static let folderName = "LinguaKeyData"

    /// Bundled tables are identified by their manifest, not by a version number
    /// someone has to remember to bump. A rebuild of the data changes the
    /// manifest, and that is the whole trigger.
    private static func manifest(_ root: URL) -> Data? {
        try? Data(contentsOf: root.appendingPathComponent("morphology/manifest.json"))
    }

    @discardableResult
    public static func run(into storage: Storage, bundle: Bundle = .main) -> Outcome {
        guard let source = bundle.url(forResource: folderName, withExtension: nil),
              let wanted = manifest(source) else {
            return .missingFromBundle
        }
        let destination = storage.data
        let current = manifest(destination)
        if current == wanted { return .alreadyCurrent }

        do {
            try storage.createIfNeeded()
            let replacing = current != nil
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return replacing ? .restaged : .staged
        } catch {
            return .failed
        }
    }

    /// Bytes on disk, for the setup screen. The number matters: it is most of the
    /// app's footprint and the reason the tables are `mmap`'d rather than loaded.
    public static func stagedByteCount(_ storage: Storage) -> Int {
        guard let walker = FileManager.default.enumerator(
            at: storage.data, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in walker {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        return total
    }
}
