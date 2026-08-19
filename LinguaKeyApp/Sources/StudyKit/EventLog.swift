import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The append-only event log.
///
/// One JSON object per line. Two processes write to it, the app and the share
/// extension, and the file is the source of truth for everything else in the
/// package: item state is a fold over it and is rebuildable at any time.
///
/// Append is a single `write(2)` to a descriptor opened `O_APPEND`, which the
/// kernel serialises against other appenders, so interleaved writes from two
/// processes produce whole lines rather than shredded ones. The one failure this
/// cannot prevent is being killed part-way through a write, and on this device
/// that is the expected case rather than an exceptional one, so the reader drops
/// a torn line instead of throwing.
public final class EventLog: @unchecked Sendable {

    public let url: URL

    public enum LogError: Error, CustomStringConvertible {
        case cannotOpen(String, Int32)
        case writeFailed(String, Int32)
        case lineTooLong(Int)

        public var description: String {
            switch self {
            case .cannotOpen(let path, let code):
                return "cannot open \(path): \(String(cString: strerror(code)))"
            case .writeFailed(let path, let code):
                return "write failed on \(path): \(String(cString: strerror(code)))"
            case .lineTooLong(let count):
                return "refusing to append a \(count) byte record; it could not be written atomically"
            }
        }
    }

    /// Above this a single `write(2)` is no longer reliably atomic, so a record
    /// this large would be a way to corrupt the log rather than a large record.
    /// Real events are a few hundred bytes; hitting this means a bug upstream.
    public static let maximumRecordBytes = 8192

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    // MARK: - Writing

    public func append(_ event: Event) throws {
        try appendAll([event])
    }

    /// Appends several events as one `write(2)`, which is what makes a study
    /// session's events all-or-nothing rather than half-written.
    public func appendAll(_ events: [Event]) throws {
        guard !events.isEmpty else { return }
        // A fresh coder per call. JSONEncoder is not Sendable and this class is
        // reachable from both processes and from any thread; sharing one would be
        // a race whose symptom is a corrupted log, which is the one thing here
        // that cannot be recovered.
        let encoder = JSONEncoder()
        var payload = Data()
        for event in events {
            payload.append(try encoder.encode(event))
            payload.append(0x0A)
        }
        guard payload.count <= EventLog.maximumRecordBytes else {
            throw LogError.lineTooLong(payload.count)
        }

        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else { throw LogError.cannotOpen(url.path, errno) }
        defer { close(descriptor) }

        var written = 0
        try payload.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            while written < buffer.count {
                let n = write(descriptor, base.advanced(by: written), buffer.count - written)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw LogError.writeFailed(url.path, errno)
                }
                if n == 0 { break }
                written += n
            }
        }
        guard written == payload.count else { throw LogError.writeFailed(url.path, EIO) }
    }

    // MARK: - Reading

    public struct ReadResult: Sendable {
        public let events: [Event]
        /// Lines that could not be decoded: a torn final line after a kill, or a
        /// record written by a newer schema. Counted rather than thrown, because
        /// one bad line must never cost the other ten thousand.
        public let skipped: Int
        public let byteCount: Int
    }

    public var byteCount: Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    /// Reads from `offset` to the end.
    ///
    /// The file is memory-mapped rather than loaded, so the resident cost is the
    /// pages actually touched and not the whole log. Lines are decoded one at a
    /// time and the array of events is the only thing that grows.
    public func read(from offset: Int = 0) -> ReadResult {
        guard let mapped = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return ReadResult(events: [], skipped: 0, byteCount: 0)
        }
        let total = mapped.count
        guard offset < total else {
            return ReadResult(events: [], skipped: 0, byteCount: total)
        }

        let decoder = JSONDecoder()
        var events: [Event] = []
        var skipped = 0
        var lineStart = mapped.startIndex + offset
        let end = mapped.endIndex

        while lineStart < end {
            let lineEnd = mapped[lineStart..<end].firstIndex(of: 0x0A) ?? end
            if lineEnd > lineStart {
                let line = mapped[lineStart..<lineEnd]
                if let event = try? decoder.decode(Event.self, from: Data(line)),
                   event.schema <= Event.currentSchema {
                    events.append(event)
                } else {
                    skipped += 1
                }
            }
            if lineEnd == end { break }
            lineStart = mapped.index(after: lineEnd)
        }
        return ReadResult(events: events, skipped: skipped, byteCount: total)
    }

    /// The byte offset just past the last complete line.
    ///
    /// A snapshot records this rather than the file size, so a torn tail does not
    /// make the snapshot look stale forever.
    public func completeByteCount() -> Int {
        guard let mapped = try? Data(contentsOf: url, options: .mappedIfSafe),
              !mapped.isEmpty else { return 0 }
        guard let last = mapped.lastIndex(of: 0x0A) else { return 0 }
        return mapped.distance(from: mapped.startIndex, to: last) + 1
    }
}
