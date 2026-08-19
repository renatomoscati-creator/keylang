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
    private let onFinish: () async -> Void

    @State private var configuration: TranslationSession.Configuration?
    @State private var working = false

    public init(_ title: String = "Download the Spanish pack",
                source: Locale.Language = SystemTranslator.source,
                target: Locale.Language = SystemTranslator.target,
                onFinish: @escaping () async -> Void) {
        self.title = title
        self.source = source
        self.target = target
        self.onFinish = onFinish
    }

    public var body: some View {
        Button {
            // Reassigning the configuration is what re-triggers the task, which
            // is what surfaces the system's download sheet.
            working = true
            configuration = TranslationSession.Configuration(source: source, target: target)
        } label: {
            HStack {
                Text(title)
                if working { Spacer(); ProgressView().controlSize(.small) }
            }
        }
        .disabled(working)
        .translationTask(configuration) { session in
            // Preparing is what downloads. The translation itself happens
            // headlessly, elsewhere.
            try? await session.prepareTranslation()
            await onFinish()
            working = false
        }
    }
}
