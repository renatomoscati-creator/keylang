import Foundation

/// Read-only reader over the build-time linguistic tables.
///
/// Everything is `mmap`'d and binary-searched in place. Nothing is decoded into
/// a dictionary, ever. Clean file-backed pages are evictable and are not charged
/// to `phys_footprint` the way dirty anonymous pages are, which is the only
/// reason 3.7 MB of morphology is affordable inside a keyboard extension whose
/// ceiling is somewhere around 25 to 40 MB and is enforced by silent jetsam.
///
/// Probe P2b in Phase 01 measures that accounting on the actual device. Until it
/// reports, the headroom is a reasoned expectation rather than a fact.
public struct Reading: Sendable, Equatable {
    public let lemma: String
    public let lemmaID: Int
    public let pos: String
    public let feats: String
    /// Whether this reading carries real morphological features.
    ///
    /// False for readings recovered from the frequency list, which supply a
    /// lemma and a part of speech and nothing else. They exist because UniMorph
    /// omits 45% of the top 100 Spanish lemmas including `tener`, and a reading
    /// without features must not drive a paradigm-cell item.
    public let hasFeatures: Bool
    public let zipf: Double
    public let gloss: String
    public let gender: String
    public let cognateEN: Double
    public let cognateIT: Double
    public let italianLookalike: String

    public var cognateMax: Double { max(cognateEN, cognateIT) }

    public var lemmaKey: String { "LEM:\(lemma)|\(pos)|0" }

    /// The paradigm-cell item, lemma-independent, so meeting `hablaré` gives
    /// partial credit toward `llegaré`.
    public var cellKey: String? {
        guard hasFeatures else { return nil }
        let tags = feats.split(separator: ";").dropFirst().map(String.init)
        guard !tags.isEmpty else { return nil }
        return "CELL:\(pos)|\(tags.joined(separator: ","))"
    }
}

public final class Tables: @unchecked Sendable {

    private let surfacesBlob: Data
    private let surfacesIdx: Data
    private let lemmasBlob: Data
    private let lemmasIdx: Data
    private let featsetsBlob: Data
    private let featsetsIdx: Data
    private let entries: Data
    private let entriesIdx: Data
    private let zipfData: Data

    private let glossBlob: Data
    private let glossIdx: Data
    private let lookBlob: Data
    private let lookIdx: Data
    private let genderData: Data
    private let cognateENData: Data
    private let cognateITData: Data

    public let surfaceCount: Int

    /// 0 unknown, 1 masculine, 2 feminine.
    private static func gender(_ code: UInt8) -> String {
        switch code {
        case 1: return "m"
        case 2: return "f"
        default: return ""
        }
    }

    private static let posNames: [UInt8: String] = [
        1: "V", 2: "N", 3: "ADJ", 10: "ADV", 11: "PRON", 12: "PREP",
        13: "CONJ", 14: "DET", 15: "ART", 16: "NUM", 17: "INTERJ",
        18: "PROP", 19: "CONTR"
    ]

    public enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        public var description: String {
            switch self {
            case .missing(let name): return "missing table file: \(name)"
            }
        }
    }

    /// Load from a directory containing the morphology and lexicon builds.
    public init(morphology: URL, lexicon: URL) throws {
        func map(_ base: URL, _ name: String) throws -> Data {
            let url = base.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                throw LoadError.missing(url.lastPathComponent)
            }
            return data
        }
        surfacesBlob = try map(morphology, "surfaces.blob")
        surfacesIdx = try map(morphology, "surfaces.idx")
        lemmasBlob = try map(morphology, "lemmas.blob")
        lemmasIdx = try map(morphology, "lemmas.idx")
        featsetsBlob = try map(morphology, "featsets.blob")
        featsetsIdx = try map(morphology, "featsets.idx")
        entries = try map(morphology, "entries.bin")
        entriesIdx = try map(morphology, "entries.idx")
        zipfData = try map(morphology, "zipf.bin")

        glossBlob = try map(lexicon, "glosses.blob")
        glossIdx = try map(lexicon, "glosses.idx")
        lookBlob = try map(lexicon, "italian_lookalike.blob")
        lookIdx = try map(lexicon, "italian_lookalike.idx")
        genderData = try map(lexicon, "gender.bin")
        cognateENData = try map(lexicon, "cognate_en.bin")
        cognateITData = try map(lexicon, "cognate_it.bin")

        surfaceCount = surfacesIdx.count / 4 - 1
    }

    /// Load from a data root laid out as `morphology/`, `lexicon/` and
    /// `interference.json`.
    ///
    /// The tables are deliberately NOT SPM resources. A keyboard extension reads
    /// them out of the App Group container or the host app bundle, never out of
    /// `Bundle.module`, and carrying a second copy inside the package would put
    /// 3.9 MB of duplicated binary in the repository to serve a code path the
    /// product never takes. `tools/stage-data.sh` assembles that root.
    public convenience init(root: URL) throws {
        try self.init(morphology: root.appendingPathComponent("morphology"),
                      lexicon: root.appendingPathComponent("lexicon"))
    }

    // MARK: - Primitive reads

    private func u32(_ data: Data, _ index: Int) -> Int {
        Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self) })
    }

    private func f32(_ data: Data, _ index: Int) -> Double {
        Double(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: index * 4, as: Float32.self) })
    }

    private func string(_ blob: Data, _ idx: Data, _ index: Int) -> String {
        let start = u32(idx, index)
        let end = u32(idx, index + 1)
        guard end > start else { return "" }
        return String(decoding: blob[blob.startIndex + start ..< blob.startIndex + end],
                      as: UTF8.self)
    }

    func surface(at index: Int) -> String { string(surfacesBlob, surfacesIdx, index) }

    // MARK: - Lookup

    /// All readings of a surface form. Empty if unknown, which is a valid answer:
    /// silence is better than a wrong guess.
    ///
    /// A surface may carry several readings, and 26.6% of them do. Ambiguity is
    /// represented rather than resolved here, because an ambiguous resolution
    /// must never write a graded learning event, only a low-weight exposure.
    public func lookup(_ word: String) -> [Reading] {
        // NFC is non-negotiable: iOS hands you decomposed and precomposed accents
        // depending on whether text was typed, pasted, or autocorrected, and the
        // two are different bytes for the same word.
        let needle = word.precomposedStringWithCanonicalMapping.lowercased()

        var low = 0
        var high = surfaceCount - 1
        var found = -1
        while low <= high {
            let mid = (low + high) / 2
            let candidate = surface(at: mid)
            if candidate == needle { found = mid; break }
            if candidate < needle { low = mid + 1 } else { high = mid - 1 }
        }
        guard found >= 0 else { return [] }

        var readings: [Reading] = []
        for slot in u32(entriesIdx, found) ..< u32(entriesIdx, found + 1) {
            let offset = slot * 8
            let lemmaID = Int(entries.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            })
            let posCode = entries[entries.startIndex + offset + 4]
            let source = entries[entries.startIndex + offset + 5]
            let featID = Int(entries.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: offset + 6, as: UInt16.self)
            })
            let feats = string(featsetsBlob, featsetsIdx, featID)
            readings.append(Reading(
                lemma: string(lemmasBlob, lemmasIdx, lemmaID),
                lemmaID: lemmaID,
                pos: Tables.posNames[posCode] ?? "P\(posCode)",
                feats: feats,
                hasFeatures: source == 0 && !feats.isEmpty && feats != "_",
                zipf: f32(zipfData, lemmaID),
                gloss: string(glossBlob, glossIdx, lemmaID),
                gender: Tables.gender(genderData[genderData.startIndex + lemmaID]),
                cognateEN: f32(cognateENData, lemmaID),
                cognateIT: f32(cognateITData, lemmaID),
                italianLookalike: string(lookBlob, lookIdx, lemmaID)
            ))
        }
        return readings
    }
}
