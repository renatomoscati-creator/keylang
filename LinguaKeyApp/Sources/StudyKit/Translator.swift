import Foundation

/// Sentence translation, behind a boundary.
///
/// `TranslationSession` cannot be constructed outside SwiftUI's
/// `.translationTask`, cannot be unit-tested, and does not exist at all in the
/// Simulator. Every one of those is a reason to keep it behind a protocol rather
/// than a reason to trust it. Nothing in this package imports `Translation`; the
/// real conformance lives in the app target and is the only file that does.
public protocol Translator: Sendable {
    /// Whether a translation can be attempted right now. False when the language
    /// pack has not been downloaded, which on an iPhone 13 is the state the app
    /// is in the first time it is opened.
    var isAvailable: Bool { get }
    func translate(_ text: String) async throws -> String
}

public enum TranslatorError: Error, CustomStringConvertible, Equatable {
    case unavailable(String)

    public var description: String {
        switch self {
        case .unavailable(let why): return why
        }
    }
}

/// What the app uses when there is no language pack, and what the Simulator
/// always uses.
///
/// This exists so that "no pack" is a one-line message under the sentence rather
/// than an error screen. Word-level teaching runs entirely offline from the
/// bundled tables, so losing the sentence translation costs the sentence
/// translation and nothing else.
public struct UnavailableTranslator: Translator {
    public let reason: String

    public init(reason: String = "Spanish language pack not downloaded yet") {
        self.reason = reason
    }

    public var isAvailable: Bool { false }

    public func translate(_ text: String) async throws -> String {
        throw TranslatorError.unavailable(reason)
    }
}

/// For tests.
public struct CannedTranslator: Translator {
    private let table: [String: String]

    public init(_ table: [String: String]) {
        self.table = table
    }

    public var isAvailable: Bool { true }

    public func translate(_ text: String) async throws -> String {
        guard let out = table[text] else {
            throw TranslatorError.unavailable("no canned translation for \(text)")
        }
        return out
    }
}
