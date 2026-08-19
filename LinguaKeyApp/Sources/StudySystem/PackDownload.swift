import SwiftUI
import Translation

/// The one control that can ask iOS to download a language pack.
///
/// It lives here, next to `SystemTranslator`, because the download prompt only
/// ever appears from a `.translationTask` context: the headless session used
/// everywhere else cannot request it. Keeping this view in `StudySystem` is what
/// lets the app's Setup screen offer the download without importing
/// `Translation` itself, which is the boundary `tools/check_invariants.py`
/// enforces.
public struct PackDownloadButton: View {

    private let title: String
    private let source: Locale.Language
    private let target: Locale.Language
    private let onFinish: @Sendable () async -> Void

    @State private var configuration: TranslationSession.Configuration?

    public init(_ title: String = "Download the Spanish pack",
                source: Locale.Language = SystemTranslator.source,
                target: Locale.Language = SystemTranslator.target,
                onFinish: @escaping @Sendable () async -> Void) {
        self.title = title
        self.source = source
        self.target = target
        self.onFinish = onFinish
    }

    public var body: some View {
        Button(title) {
            // Reassigning the configuration is what re-triggers the task, which
            // is what surfaces the system's download sheet. iOS owns the progress
            // UI from here, which is why there is no spinner of our own: two
            // progress indicators for one download is worse than none.
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
        .translationTask(configuration) { session in
            // Preparing is what downloads. The translation itself happens
            // headlessly, elsewhere, which is what lets it run in the extension.
            try? await session.prepareTranslation()
            await onFinish()
        }
    }
}
