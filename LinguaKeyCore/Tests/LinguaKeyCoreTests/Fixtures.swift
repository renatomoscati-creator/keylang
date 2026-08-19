import Foundation
import XCTest
@testable import LinguaKeyCore

/// Locates the repository's build artifacts from the test source's own path.
///
/// The package deliberately ships no resources (see `Package.swift`), so the
/// tests reach the committed tables and golden vectors directly. `#filePath` is
/// resolved at compile time and is stable regardless of where SwiftPM puts the
/// build directory, which is what makes this work from Xcode and from
/// `swift test` alike.
enum Fixtures {

    /// `.../LinguaKeyCore/Tests/LinguaKeyCoreTests/Fixtures.swift` -> repo root.
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // LinguaKeyCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // LinguaKeyCore
        .deletingLastPathComponent()   // repository root

    static var goldenVectors: URL {
        repoRoot.appendingPathComponent("build/golden/fsrs-golden.json")
    }
    static var morphology: URL { repoRoot.appendingPathComponent("build/morphology") }
    static var lexicon: URL { repoRoot.appendingPathComponent("build/lexicon") }
    static var interferenceList: URL {
        repoRoot.appendingPathComponent("data/interference.json")
    }

    /// Loaded once. `Tables` is read-only and `mmap`-backed, and rebuilding it
    /// per test would remap 3.7 MB seventy times for no benefit.
    static let shared: (tables: Tables, interference: Interference)? = {
        guard let tables = try? Tables(morphology: morphology, lexicon: lexicon),
              let interference = try? Interference(contentsOf: interferenceList) else {
            return nil
        }
        return (tables, interference)
    }()

    /// The selector, or a skip. A missing table is a build step that was not
    /// run, not a broken model, and it should say so rather than fail as if the
    /// code were wrong.
    static func selector(_ file: StaticString = #filePath,
                         _ line: UInt = #line) throws -> FocusSelector {
        guard let shared else {
            throw XCTSkip("""
                linguistic tables not built. Run:
                  tools/build-data/fetch.sh && \\
                  python3 tools/build-data/build_morphology.py && \\
                  python3 tools/build-data/build_lexicon.py
                """, file: file, line: line)
        }
        return FocusSelector(tables: shared.tables, interference: shared.interference)
    }
}
