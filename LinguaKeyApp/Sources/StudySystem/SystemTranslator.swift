import Foundation
import Translation
import StudyKit

/// The only file in the product that imports `Translation`.
///
/// Enforced by `tools/check_invariants.py`, not by review. Everything above this
/// boundary sees an `any Translator` and cannot tell whether the framework
/// exists, which is what lets the whole study surface be tested on a machine
/// where it does not.
public struct SystemTranslator: Translator {

    public static let source = Locale.Language(identifier: "es")
    public static let target = Locale.Language(identifier: "en")

    public let isAvailable: Bool

    private init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }

    /// Asks the system whether the pack is installed.
    ///
    /// `.installed` is the only status this returns true for. `.supported` means
    /// the pack could be downloaded but has not been, and on an iPhone 13 that is
    /// the state the device is in until the host app has asked for it: packs are
    /// not pre-staged the way they are on an Apple Intelligence device.
    public static func current() async -> SystemTranslator {
        let status = await LanguageAvailability().status(from: source, to: target)
        // A switch rather than an equality test, so a status added in a later
        // iOS is a compile error here rather than a silent "not installed".
        switch status {
        case .installed: return SystemTranslator(isAvailable: true)
        case .supported, .unsupported: return SystemTranslator(isAvailable: false)
        @unknown default: return SystemTranslator(isAvailable: false)
        }
    }

    public func translate(_ text: String) async throws -> String {
        guard isAvailable else {
            throw TranslatorError.unavailable("Spanish language pack not downloaded yet")
        }
        // Headless. No SwiftUI, no `.translationTask`, which is why this works
        // from inside an extension at all. Downloading a pack still requires the
        // host app, and that is what SetupView is for.
        let session = TranslationSession(installedSource: SystemTranslator.source,
                                         target: SystemTranslator.target)
        return try await session.translate(text).targetText
    }

    /// What to use when the pack is not there. Kept here so callers never have to
    /// import `StudyKit` just to name the fallback.
    public static func unavailable(_ reason: String) -> any Translator {
        UnavailableTranslator(reason: reason)
    }
}
