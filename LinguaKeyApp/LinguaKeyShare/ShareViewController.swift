import UIKit
import SwiftUI
import UniformTypeIdentifiers
import StudyKit
import StudyUI
import StudySystem
import LinguaKeyCore

/// The share extension. Reads the selection, teaches, writes events, dismisses.
///
/// It never returns modified text. `NSExtensionItem` is not touched on the way
/// out and `completeRequest(returningItems:)` is called with an empty array, so
/// there is no code path that could write back into the host app even by
/// accident. That is CONTEXT D6 and it is structural, not a policy.
final class ShareViewController: UIViewController {

    private var storage: Storage?
    private var log: EventLog?

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await load() }
    }

    // MARK: - Input

    /// What actually arrives here is host-dependent and undocumented, exactly
    /// like `documentContextBeforeInput`. Safari gives the selection, Messages
    /// gives the message, some hosts give a URL and no text at all. Every type
    /// identifier that shows up is logged, which is how gray area G2 gets its
    /// answer instead of staying a guess.
    private func selectedText() async -> (text: String, sourceApp: String?)? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        for item in items {
            for provider in item.attachments ?? [] {
                let offered = provider.registeredTypeIdentifiers.joined(separator: ",")
                guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                else { continue }
                let loaded = try? await provider.loadItem(
                    forTypeIdentifier: UTType.plainText.identifier, options: nil)
                // Hosts differ on what they hand over for the same declared type:
                // some give a String, some an NSURL, some Data.
                let text: String?
                switch loaded {
                case let value as String: text = value
                case let value as URL: text = value.absoluteString
                case let value as Data: text = String(data: value, encoding: .utf8)
                default: text = nil
                }
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (text, offered)
                }
            }
            // Some hosts put the selection in the item's own attributed content
            // rather than in an attachment.
            if let text = item.attributedContentText?.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (text, "attributedContentText")
            }
        }
        return nil
    }

    // MARK: - Setup

    private func load() async {
        guard let storage = Storage.shared() else {
            return present(.problem("""
                The share extension cannot reach the App Group container. Check \
                that both targets carry the same App Group entitlement.
                """))
        }
        self.storage = storage

        guard let selection = await selectedText() else {
            return present(.problem("No text came through from that app."))
        }

        do {
            let log = try EventLog(url: storage.eventLog)
            self.log = log
            let tables = try Tables(root: storage.data)
            let interference = try Interference(root: storage.data)
            let selector = FocusSelector(tables: tables, interference: interference)
            let assignment = try ArmAssignment.load(storage)
            let store = ItemStore.load(log: log, storage: storage).store

            let session = StudySession(sentence: selection.text, selector: selector,
                                       store: store,
                                       assignment: assignment,
                                       now: Date().timeIntervalSince1970,
                                       sourceApp: selection.sourceApp)
            let translator = await SystemTranslator.current()
            present(.study(session: session, store: store, translator: translator))
        } catch {
            // The tables live in the App Group and are put there by the app, so
            // this is the first-run-before-opening-the-app case as much as it is
            // a failure.
            present(.problem("""
                The language tables are not staged yet. Open LinguaKey once, then \
                try again.

                \(error)
                """))
        }
    }

    // MARK: - Presentation

    private enum Screen {
        case study(session: StudySession, store: ItemStore, translator: any Translator)
        case problem(String)
    }

    private func present(_ screen: Screen) {
        let root: AnyView
        switch screen {
        case .study(let session, let store, let translator):
            root = AnyView(StudyView(session: session, translator: translator, store: store,
                                     onEvents: { [weak self] events in
                                         try? self?.log?.appendAll(events)
                                     },
                                     onDone: { [weak self] in self?.finish() }))
        case .problem(let message):
            root = AnyView(ProblemView(message: message, onDone: { [weak self] in
                self?.finish()
            }))
        }

        let hosting = UIHostingController(rootView: root)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    private func finish() {
        // Empty, always. Nothing is written back into the host app.
        extensionContext?.completeRequest(returningItems: [])
    }
}

private struct ProblemView: View {
    let message: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView("Nothing to study", systemImage: "text.badge.xmark",
                                   description: Text(message))
            Button("Close", action: onDone).buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
