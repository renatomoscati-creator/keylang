import Foundation
import XCTest
@testable import StudyKit
import LinguaKeyCore

enum Fixtures {

    /// `.../LinguaKeyApp/Tests/StudyKitTests/Fixtures.swift` -> repository root.
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // StudyKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // LinguaKeyApp
        .deletingLastPathComponent()   // repository root

    static var armGolden: URL {
        repoRoot.appendingPathComponent("build/golden/arms-golden.json")
    }

    /// A private directory per test, torn down by the caller.
    static func temporaryStorage(_ name: String = UUID().uuidString) throws -> Storage {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StudyKitTests-\(name)")
        let storage = Storage(root: root)
        try? FileManager.default.removeItem(at: root)
        try storage.createIfNeeded()
        return storage
    }

    static func remove(_ storage: Storage) {
        try? FileManager.default.removeItem(at: storage.root)
    }

    static func event(_ key: String, _ channel: Channel, at: TimeInterval,
                      arm: Arm = .recognition, grade: Grade? = nil,
                      features: ItemFeatures? = nil) -> Event {
        Event(at: at, itemKey: key, channel: channel, grade: grade, arm: arm,
              surface: key, features: features)
    }

    static let shared: (tables: Tables, interference: Interference)? = {
        let morphology = repoRoot.appendingPathComponent("build/morphology")
        let lexicon = repoRoot.appendingPathComponent("build/lexicon")
        let list = repoRoot.appendingPathComponent("data/interference.json")
        guard let tables = try? Tables(morphology: morphology, lexicon: lexicon),
              let interference = try? Interference(contentsOf: list) else { return nil }
        return (tables, interference)
    }()

    static func selector() throws -> FocusSelector {
        guard let shared else {
            throw XCTSkip("linguistic tables not built. See LinguaKeyCore/README.md")
        }
        return FocusSelector(tables: shared.tables, interference: shared.interference)
    }
}
