import UIKit
import Translation
import NaturalLanguage
import AVFoundation

/// Every probe body. Ordering matters and is documented in the phase CONTEXT:
/// P1 is a go/no-go gate. If it fails with a sandbox or XPC error, stop and
/// re-plan the roadmap before running anything else.
enum Probes {

    private static let en = Locale.Language(identifier: "en")
    private static let it = Locale.Language(identifier: "it")
    private static let es = Locale.Language(identifier: "es")

    // MARK: - P1: TranslationSession inside a keyboard extension  (THE GATE)

    /// The single highest-information half hour in the project.
    ///
    /// Three outcomes:
    ///   - a Spanish string          -> the architecture holds, continue
    ///   - TranslationError.notInstalled -> the pack did not cross the process
    ///                                  boundary, contradicting Apple's
    ///                                  "available to all apps on the device"
    ///   - sandbox / XPC / crash     -> the keyboard cannot translate. STOP.
    ///                                  The product becomes the Share Sheet app.
    static func p1Translate() async {
        let availability = LanguageAvailability()
        let status = await availability.status(from: en, to: es)
        ProbeLog.write("P1", "availability.en_es", describe(status), "from extension")

        let before = Memory.physFootprintMB()
        ProbeLog.write("P1", "footprint.before", Memory.formatted(before), "MB")

        do {
            let session = TranslationSession(installedSource: en, target: es)
            let response = try await session.translate("I'll arrive around eight")
            ProbeLog.write("P1", "translation.en_es.result", response.targetText, "ok")

            // The gloss-sense trick from research 10: translating the focus word
            // alone in the same session lets you check whether it appears in the
            // sentence translation, which confirms which sense was chosen.
            let word = try await session.translate("arrive")
            let aligned = response.targetText.localizedCaseInsensitiveContains(word.targetText)
            ProbeLog.write("P1", "translation.word_alone", word.targetText,
                           aligned ? "aligns with sentence" : "does not align")
        } catch {
            ProbeLog.writeError("P1", "translation.en_es.result", error)
        }

        let after = Memory.physFootprintMB()
        ProbeLog.write("P1", "footprint.after", Memory.formatted(after), "MB")
        if let before, let after {
            ProbeLog.write("P1", "footprint.delta_mb",
                           String(format: "%.1f", after - before), "translation session")
        }
    }

    // MARK: - P2: destructive memory measurement

    private static var ballast: [UnsafeMutableRawPointer] = []

    /// Allocate and TOUCH 1 MB at a time until jetsam kills the process.
    /// Touching matters: reserved-but-untouched pages are not dirty and are not
    /// what the limit counts. Run this five times, in Messages, WhatsApp, Safari
    /// with ~20 tabs, straight after a reboot, and after two hours of use. The
    /// LOWEST of the five is the real ceiling; the spread is the system-pressure
    /// effect, which on a 4 GB device is the number that actually governs design.
    static func p2AllocateUntilKilled() {
        ProbeLog.write("P2", "jetsam.run_start",
                       Memory.formatted(Memory.physFootprintMB()), "MB at start")

        DispatchQueue.global(qos: .userInitiated).async {
            let oneMB = 1_048_576
            while true {
                guard let block = malloc(oneMB) else {
                    ProbeLog.write("P2", "jetsam.malloc_failed", "nil", "before kill")
                    return
                }
                memset(block, 1, oneMB)          // dirty the pages
                ballast.append(block)
                let footprint = Memory.physFootprintMB()
                ProbeLog.write("P2", "jetsam.last_footprint_mb",
                               Memory.formatted(footprint),
                               "\(ballast.count) MB ballast")
                usleep(40_000)                    // give the log time to flush
            }
        }
    }

    /// Does an mmap'd, clean, file-backed 20 MB blob count against the footprint?
    ///
    /// Phase 05's entire bundled-data budget rests on the answer. If the
    /// footprint barely moves, the mmap strategy is validated. If it moves by
    /// 20 MB, Phase 05 needs redesigning.
    static func p2Mmap() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmap-probe.bin")
        let size = 20 * 1_048_576

        if !FileManager.default.fileExists(atPath: url.path) {
            let chunk = Data(repeating: 0xAB, count: 1_048_576)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            if let handle = try? FileHandle(forWritingTo: url) {
                for _ in 0..<20 { try? handle.write(contentsOf: chunk) }
                try? handle.close()
            }
        }

        ProbeLog.write("P2", "mmap.footprint_before",
                       Memory.formatted(Memory.physFootprintMB()), "MB")

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            ProbeLog.write("P2", "mmap.footprint_after", "failed", "could not map")
            return
        }
        // Touch every page so it is actually resident, not merely mapped.
        var checksum: UInt8 = 0
        data.withUnsafeBytes { raw in
            for offset in stride(from: 0, to: size, by: 4096) {
                checksum = checksum &+ raw[offset]
            }
        }
        ProbeLog.write("P2", "mmap.footprint_after",
                       Memory.formatted(Memory.physFootprintMB()),
                       "20 MB mapped and touched, checksum \(checksum)")
    }

    // MARK: - P3: Italian

    /// Three answers, three product designs. `.unsupported` means IT->ES would
    /// have to chain two sessions through English, which teaches Spanish through
    /// a double-translated intermediate. That is the case for dropping Italian
    /// from V1 rather than shipping it.
    static func p3ItalianAvailability() async {
        let status = await LanguageAvailability().status(from: it, to: es)
        ProbeLog.write("P3", "availability.it_es", describe(status), "from extension")

        guard status != .unsupported else { return }
        do {
            let session = TranslationSession(installedSource: it, target: es)
            let response = try await session.translate("Probabilmente arriverò verso le otto")
            ProbeLog.write("P3", "translation.it_es.result", response.targetText, "ok")
        } catch {
            ProbeLog.writeError("P3", "translation.it_es.result", error)
        }
    }

    // MARK: - P4: cheap probes battery

    static func p4Battery(proxy: UITextDocumentProxy) {
        // Does Apple's headroom API work outside an app? Documented as returning
        // 0 when the caller is not an app. If it returns 0, task_vm_info is the
        // only instrument, permanently.
        let available = Memory.availableMB()
        ProbeLog.write("P4", "os_proc_avail.usable",
                       available > 0 ? String(format: "%.1f MB", available) : "0 (unusable)",
                       "keyboard extension is not an app")

        // Lemmatization. UNVERIFIED across three research passes. If Spanish
        // .lemma is absent, Phase 05's bundled morphology table is mandatory
        // rather than merely preferable.
        for (name, language) in [("en", NLLanguage.english),
                                 ("es", NLLanguage.spanish),
                                 ("it", NLLanguage.italian)] {
            let schemes = NLTagger.availableTagSchemes(for: .word, language: language)
            ProbeLog.write("P4", "nltagger.schemes.\(name)",
                           schemes.map(\.rawValue).joined(separator: ","),
                           schemes.contains(.lemma) ? "lemma available" : "NO LEMMA")
        }

        // Even where available, Apple calls .lemma a "stem" form. Verify it
        // returns llegar rather than lleg.
        for word in ["llegaré", "dármelo", "salgo", "arriverò"] {
            let tagger = NLTagger(tagSchemes: [.lemma])
            tagger.string = word
            let (tag, _) = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma)
            let key = "nltagger.lemma." + word.folding(options: .diacriticInsensitive,
                                                       locale: .current)
            ProbeLog.write("P4", key, tag?.rawValue ?? "nil", "input \(word)")
        }

        // Depends on which system keyboards the USER has added, not on this app.
        let languages = UITextChecker.availableLanguages
        ProbeLog.write("P4", "textchecker.languages",
                       languages.joined(separator: ","),
                       "es=\(languages.contains { $0.hasPrefix("es") }) it=\(languages.contains { $0.hasPrefix("it") })")

        // Language detection with the constraint that research 03 called the
        // single biggest accuracy win available. Sets the confidence floor and
        // hysteresis thresholds for Phase 03.
        let samples = [
            "ok", "sono qui", "on my way", "arrivo tra poco",
            "see you tomorrow", "ci vediamo domani", "sorry im late",
            "va bene", "no problem", "perché no",
        ]
        for sample in samples {
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = [.english, .italian]
            recognizer.processString(sample)
            let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
            let ranked = hypotheses.sorted { $0.value > $1.value }
            let rendered = ranked
                .map { "\($0.key.rawValue):\(String(format: "%.2f", $0.value))" }
                .joined(separator: " ")
            let margin = ranked.count >= 2 ? ranked[0].value - ranked[1].value : 1.0
            ProbeLog.write("P4", "langrecognizer.sample", rendered,
                           "\"\(sample)\" chars=\(sample.count) margin=\(String(format: "%.2f", margin))")
        }

        // How much context does this host actually give us? Per-host and
        // per-OS-version; a snapshot that justifies the shadow buffer, not a
        // contract. Never log the content itself, only its shape.
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        ProbeLog.write("P4", "proxy.context",
                       "before=\(before.count) after=\(after.count)",
                       "hasText=\(proxy.hasText) id=\(proxy.documentIdentifier)")
        ProbeLog.write("P4", "proxy.traits",
                       "keyboardType=\(proxy.keyboardType?.rawValue ?? -1) returnKey=\(proxy.returnKeyType?.rawValue ?? -1)",
                       "secure=\(proxy.isSecureTextEntry) autocap=\(proxy.autocapitalizationType?.rawValue ?? -1)")
    }

    /// UILexicon carries Address Book names. Log the COUNT only, never contents.
    static func lexicon(from controller: UIInputViewController) {
        controller.requestSupplementaryLexicon { lexicon in
            ProbeLog.write("P4", "lexicon.entries", "\(lexicon.entries.count)",
                           "count only, contents are contact names")
        }
    }

    /// Needs Full Access: Apple lists "no access to microphone and speaker" for
    /// keyboards without open access. Research 01 flags OSStatus 561015905 as
    /// reported even WITH Full Access, so a failure here is an expected-possible
    /// outcome rather than a mistake.
    private static let synthesizer = AVSpeechSynthesizer()

    static func p4Speech() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("es") }
        ProbeLog.write("P4", "speech.voices.es", "\(voices.count)",
                       voices.map { "\($0.language)/\($0.quality.rawValue)" }
                           .joined(separator: " "))

        // Let the system manage a separate audio session so speech ducks the
        // host app's audio and restores it, instead of mutating the host's own
        // session from inside its keyboard.
        synthesizer.usesApplicationAudioSession = false

        let utterance = AVSpeechUtterance(string: "Llegaré sobre las ocho")
        utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
        synthesizer.speak(utterance)

        ProbeLog.write("P4", "speech.speak", "requested",
                       "listen: did it actually play? note silent-switch position")
    }

    // MARK: - P5: Liquid Glass cost

    /// GPU rather than CPU is the A15 concern, and iOS 26 is widely reported to
    /// lag on this device with keyboard lag named specifically. If glass costs
    /// frames, Phase 03 designs around it and Reduce Transparency becomes a
    /// first-class appearance rather than an accessibility afterthought.
    static func p5GlassCost(in host: UIView) {
        func timeLayout(_ label: String, _ makeView: () -> UIView) {
            let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
            host.addSubview(container)
            container.isHidden = true
            defer { container.removeFromSuperview() }

            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<30 {
                let view = makeView()
                view.frame = container.bounds
                container.addSubview(view)
                container.setNeedsLayout()
                container.layoutIfNeeded()
                view.removeFromSuperview()
            }
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000 / 30
            ProbeLog.write("P5", "glass.frame_ms", String(format: "%.2f", elapsedMs),
                           "\(label), 60 Hz budget is 16.7 ms")
        }

        timeLayout("plain") { UIView() }
        timeLayout("blur") {
            UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        }
        ProbeLog.write("P5", "reduce_transparency",
                       "\(UIAccessibility.isReduceTransparencyEnabled)", "user setting")
    }

    // MARK: - helpers

    private static func describe(_ status: LanguageAvailability.Status) -> String {
        switch status {
        case .installed:   return "installed"
        case .supported:   return "supported"
        case .unsupported: return "unsupported"
        @unknown default:  return "unknown"
        }
    }
}
