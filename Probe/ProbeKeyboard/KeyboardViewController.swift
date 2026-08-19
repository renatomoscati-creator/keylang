import UIKit

/// Throwaway probe harness. Deliberately not a keyboard: a stack of buttons,
/// no key grid, no OpenKeyboardKit. Nothing here survives into Phase 02.
final class KeyboardViewController: UIInputViewController {

    private let statusLabel = UILabel()
    private var didRunAppearProbes = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // hasFullAccess is documented as unreliable before the host connection
        // is established. Logging it here and again in viewWillAppear is the
        // probe: a difference between the two confirms research 01 section 1.5
        // and locks the "read it on every appearance" rule into Phase 03.
        ProbeLog.write("P0", "fullaccess.viewDidLoad", "\(hasFullAccess)", "may be wrong here")
        ProbeLog.write("P0", "container.kind", ProbeLog.containerKind,
                       ProbeLog.appGroupID ?? "no group id in Info.plist")

        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !didRunAppearProbes else { return }
        didRunAppearProbes = true

        ProbeLog.write("P0", "fullaccess.viewWillAppear", "\(hasFullAccess)", "trusted value")
        ProbeLog.write("P0", "footprint.launch", Memory.formatted(Memory.physFootprintMB()), "MB")

        // Does the shared container actually accept a write from the extension?
        // Apple documents the sandbox as preventing writes to the group container
        // without Full Access. Whichever way this goes, it settles blocker B2 on
        // this device, and the persistence design in Phase 05 depends on it.
        let wrote = ProbeLog.containerKind == "appgroup"
        ProbeLog.write("P0", "appgroup.write", wrote ? "ok" : "refused",
                       "fullAccess=\(hasFullAccess)")

        Probes.lexicon(from: self)
    }

    // MARK: - UI

    private func buildUI() {
        let buttons: [(String, () -> Void)] = [
            ("P1  Translate en->es  (GATE)", { Task { await Probes.p1Translate() } }),
            ("P2  Memory: allocate until killed", { Probes.p2AllocateUntilKilled() }),
            ("P2b Memory: mmap 20 MB", { Probes.p2Mmap() }),
            ("P3  it->es availability", { Task { await Probes.p3ItalianAvailability() } }),
            ("P4  Cheap probes battery", { [weak self] in
                guard let self else { return }
                Probes.p4Battery(proxy: self.textDocumentProxy)
            }),
            ("P4b Speech (needs Full Access)", { Probes.p4Speech() }),
            ("P5  Liquid Glass frame cost", { [weak self] in
                guard let self else { return }
                Probes.p5GlassCost(in: self.view)
            }),
        ]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (title, action) in buttons {
            var config = UIButton.Configuration.gray()
            config.title = title
            config.titleTextAttributesTransformer = .init { attrs in
                var attrs = attrs
                attrs.font = .systemFont(ofSize: 13, weight: .medium)
                return attrs
            }
            let button = UIButton(configuration: config, primaryAction: UIAction { _ in
                action()
                self.statusLabel.text = "ran: \(title)"
            })
            stack.addArrangedSubview(button)
        }

        statusLabel.text = "ready"
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        stack.addArrangedSubview(statusLabel)

        view.addSubview(stack)

        // Keyboards must set their own height, and only after the primary view
        // first draws. 320 is arbitrary and generous; this is not a keyboard.
        let height = view.heightAnchor.constraint(equalToConstant: 320)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            height,
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
        ])
    }
}
