# PLAN — Phase 01: Ground truth

Produces three things and no product code:
- a **vendored OpenKeyboardKit** tree that builds under Xcode 26,
- a **throwaway probe harness** (host app + keyboard extension) that runs on the real iPhone 13,
- **written findings** appended to `docs/research/` as CONFIRMED, plus a `STATE.md` entry.

Research source: `docs/STRESS-TEST.md` and `docs/research/01`-`10`, with `10` controlling where
reports disagree. No RESEARCH.md is written for this phase; the corpus is the research.

**Executor note:** every task below runs on macOS with Xcode and a physical iPhone 13. None of it
can be validated in this repo or in CI. Verification steps are therefore written as **exact
expected observations** rather than shell assertions, and each one names what a failure looks like.

---

## Project-wide constraints (apply to every task)

- **Xcode 27 beta, deployment target iOS 26.0.** Amended from Xcode 26 once G2 resolved: the
  phone is on an iOS 27 beta and Xcode 26 cannot deploy to it. The App Store SDK floor that
  favoured Xcode 26 does not bind a free-tier personal device that is never submitted. Do not
  raise the deployment target to 26.4 for `preferredStrategy` (research 10 §2.2: it is a no-op
  on this device).
- **Run every translation probe twice, once from `ProbeApp` in the foreground and once from
  `ProbeKeyboard`,** and log both. On iOS 27 that comparison is the only way to tell the ANE
  background restriction apart from an extension-sandbox refusal.
- **Physical iPhone 13 only.** A Simulator result is not a result (D3).
- **Throwaway code** (D1). No abstractions, no protocols, no dependency injection, no tests
  beyond Task 8's self-check. Ugly is correct here.
- **Log everything to a file, not just the console.** The keyboard extension will be killed
  mid-probe by design in Task 4; console output dies with it. Append to a file in the shared
  container (or, if App Groups are not wired, the extension's own container) and flush after
  every line with `synchronize()` / an unbuffered handle. **A probe whose result you cannot read
  after a jetsam kill has not run.**
- **Never write `UIApplication.shared.connectedScenes.first`** (D8).
- **No em-dashes** in emitted content, comments, or findings.
- Every finding is appended under `## Device-verified YYYY-MM-DD — iPhone 13`, never by editing
  the original UNVERIFIED text (D5).

## Shared logging contract (identical across all probes — do not diverge)

Every probe emits one line per observation, in this exact shape, so the findings can be grepped:

```
PROBE <id> | <key> | <value> | <note>
```

Examples:
```
PROBE P1 | translation.en_es.result | Llegaré sobre las ocho. | ok
PROBE P1 | translation.en_es.error  | -                       | none
PROBE P2 | jetsam.host              | WhatsApp                | run 2 of 5
PROBE P2 | jetsam.last_footprint_mb | 31                      | killed after this
PROBE P4 | nltagger.lemma.es        | unavailable             | schemes: Language,Script,TokenType
```

Write to `probe-log.txt`, append-only, one file for the whole phase. It is the phase deliverable.

---

## Task 1 — Resolve the three gray areas

**Files touched:** none.
**Steps:** record, in `.planning/phases/01-ground-truth/CONTEXT.md` under "Open gray areas",
the answers to G1 (Intel or Apple silicon Mac), G2 (iOS version on the iPhone 13), G3 (free
provisioning or paid membership). Change the heading to `## Gray areas: resolved`.

**Verification:** no `TBD` remains in CONTEXT.md.

---

## Task 2 — Vendor OpenKeyboardKit and build it

**Files touched:** create `Vendor/OpenKeyboardKit/`.
**Depends on:** Task 1 (G1 decides the Xcode you have).

**Steps:**
1. `git clone https://github.com/valomedia/OpenKeyboardKit` into a scratch directory. Confirm the
   fork point is commit `a7e33ac2` (KeyboardKit 9.9.0/9.9.1, the last MIT release) and that
   `LICENSE` reads MIT.
2. Copy the source tree into `Vendor/OpenKeyboardKit/` **as owned source**, not as an SPM
   dependency on a 1-star repo. Preserve the MIT LICENSE file and add a short `PROVENANCE.md`
   recording the upstream URL, the commit SHA, and the date.
3. Delete `Sources/OpenKeyboardKit/_Pro/ProPlaceholders.swift` and every reference to it. It is
   733 lines of stubs that throw "unlocked by KeyboardKit Pro" and it is dead weight.
4. Raise the package's deployment target from `.iOS(.v15)` to `.iOS(.v26)` so availability shims
   can be deleted rather than inherited.
5. Delete the `.lproj` locale bundles you do not need. Keep `en`, `it`, `es`. This is real memory
   against a 25 MB budget.
6. Resolve the three `exact:` pinned dependencies (EmojiKit 1.7.1, GestureButton 0.5.0,
   SwiftLintPlugins 0.65.0). **Research 02's addendum predicts these are the most likely build
   failure, not the 22.7k LOC.** Bump or vendor EmojiKit and GestureButton; drop SwiftLintPlugins
   entirely.
7. Replace the three `UIScreen.main` call sites (`InterfaceOrientation.swift:34`,
   `KeyboardInputViewController+Setup.swift:43`, `CalloutContext.swift:184`) with the input
   view's own bounds or `window.windowScene.screen`.
8. Build.

**Verification:**
- Builds clean under Xcode 26 for an iOS 26.0 device target, with **zero errors**. Warnings are
  acceptable and expected (Swift 6 concurrency diagnostics are warnings at tools-version 5.9).
- `grep -r "ProPlaceholder" Vendor/` returns nothing.
- `grep -rn "UIScreen.main" Vendor/` returns nothing.
- `grep -rn "UIApplication.shared" Vendor/ --include=*.swift` returns nothing (research 02 found
  0 occurrences in Swift; confirm the vendoring did not introduce any).
- `ls Vendor/OpenKeyboardKit/**/*.lproj` lists only `en`, `it`, `es`.

**Failure mode and its meaning:** if this takes more than **one week**, that is the signal to
reconsider the foundation decision — not iOS 27, not licensing. Research 02 budgets 1-2 days.

---

## Task 3 — Probe harness scaffold

**Files touched:** create `Probe/` (host app target + keyboard extension target).
**Depends on:** Task 2.

**Steps:**
1. New Xcode project, two targets: `ProbeApp` (SwiftUI `@main`) and `ProbeKeyboard`
   (`UIInputViewController` subclass). Deployment target iOS 26.0.
2. `ProbeKeyboard/Info.plist`: `RequestsOpenAccess = false` initially. Task 6 flips it.
3. `ProbeApp/Info.plist`: add `UIApplicationSceneManifest` and `UILaunchScreen` (D8). Both are
   free now and mandatory under the iOS 27 SDK later.
4. App Group + Keychain Sharing capability on both targets. Per D7, **read the group identifier
   from `Info.plist` at runtime**, never hardcode it.
5. Implement the shared logging contract: an append-only `probe-log.txt` in the shared container,
   flushed after every line.
6. `ProbeKeyboard` UI: a bare `UIView` with a label and five buttons, one per probe. No key grid,
   no OpenKeyboardKit yet. **This task is deliberately not a keyboard.**
7. Install on the iPhone 13. Enable the keyboard in Settings. Confirm it appears in the globe
   rotation and that tapping a button writes a line to `probe-log.txt` readable from `ProbeApp`.

**Verification:**
- The keyboard appears in Settings > General > Keyboard > Keyboards and can be selected in Notes.
- Tapping a probe button in the keyboard produces a line in `probe-log.txt` that `ProbeApp`
  can read and display.
- **If App Group writes fail here with `RequestsOpenAccess = false`, that is not a bug** — it is
  research 01 §4.2 and research 04 §4.1 confirming themselves. Record it as
  `PROBE P0 | appgroup.write.no_full_access | failed | <error>` and fall back to the extension's
  own container for the log.

---

## Task 4 — P1: `TranslationSession` inside a keyboard extension  ⭐ GO/NO-GO GATE

**Files touched:** `ProbeKeyboard`, `ProbeApp`.
**Depends on:** Task 3.
**This is the single highest-information half hour in the project (D2).**

**Steps:**
1. In `ProbeApp`, a SwiftUI view with `.translationTask(configuration)` calling
   `session.prepareTranslation()` for `en -> es`. Approve the download. Wait for completion by
   polling `await LanguageAvailability().status(from:to:)` until `.installed`.
2. Log from the app: `PROBE P1 | availability.en_es.host | installed | -`.
3. In `ProbeKeyboard`, on a button tap, with `RequestsOpenAccess = false`:
   ```swift
   let session = TranslationSession(
       installedSource: .init(identifier: "en"),
       target: .init(identifier: "es"))
   let response = try await session.translate("I'll arrive around eight")
   ```
4. Log the result, and separately log any thrown error including its full type and description.
5. Sample `task_vm_info.phys_footprint` immediately before constructing the session and
   immediately after the translation returns. Log both.

**Verification — three outcomes, three meanings:**

| Observation | Meaning | Next action |
|---|---|---|
| A Spanish string is logged | **The architecture holds.** The keyboard can translate on-device with no Full Access, no network, no cost | Continue to Task 5 |
| `TranslationError.notInstalled` | The pack did not cross the process boundary, contradicting Apple's "available to all apps on the device" | Re-run after confirming `.installed` from the app in the same session. If it persists, this is a genuine finding and a major one |
| A sandbox, XPC, or crash-on-construct error | **The keyboard cannot translate. STOP.** | Do not run P2 onward. Re-plan the roadmap: the product becomes the Share Sheet app and the keyboard becomes a typing surface only |

- Also log `PROBE P1 | footprint.delta_mb | <n> | translation session` — a large delta would
  contradict research 03's "managed centrally by the OS" expectation and matters for Task 5.
- **Record the outcome in `docs/research/10-iphone-13-constraints.md` §2.5 under a
  `## Device-verified` heading before doing anything else.** This is the finding the whole
  research corpus has been pointing at.

---

## Task 5 — P2: the five-run destructive memory measurement

**Files touched:** `ProbeKeyboard`.
**Depends on:** Task 4 passing.

**Steps:**
1. In `ProbeKeyboard`, a button that enters a loop: allocate and **touch** (write to, so the pages
   are dirty, not merely reserved) 1 MB at a time, logging `task_vm_info.phys_footprint` in MB
   after each allocation, flushing the log every iteration. Do not stop; let jetsam kill it.
2. Run this **five times**, in these five conditions, recording the host each time:
   - inside Messages
   - inside WhatsApp
   - inside Safari with ~20 tabs open
   - immediately after a device reboot
   - after roughly two hours of ordinary phone use
3. After each kill, reopen `ProbeApp` and read the last logged footprint.

**Verification:**
- Five values recorded, each tagged with its host and condition.
- **The lowest of the five is the real ceiling.** Record it as
  `PROBE P2 | ceiling.observed_mb | <n> | lowest of 5`.
- **The spread between highest and lowest is the system-pressure effect**, and on a 4 GB device
  it is the number that actually governs the design. Record it explicitly.
- Update `PROJECT.md`'s memory constraint with the measured numbers, replacing the 25/20/35
  estimate. If the observed ceiling is below 35 MB, the design target drops proportionally.

**Known caveat to acknowledge in the write-up:** this measures *dirty anonymous* pages. It does
**not** establish how `mmap`'d clean file-backed pages are accounted, which is the technique
Phase 05's bundled data depends on. **Add a sixth run**: `mmap` a 20 MB file, touch every page,
and log the footprint before and after. If the footprint barely moves, the mmap strategy is
validated and Phase 05's data budget is real. If it moves by 20 MB, Phase 05 needs redesigning.

---

## Task 6 — P3 and the Full Access probes

**Files touched:** `ProbeKeyboard/Info.plist`, `ProbeKeyboard`.
**Depends on:** Task 4.

**Steps:**
1. **P3, before touching Full Access:** log
   `await LanguageAvailability().status(from: .init(identifier:"it"), to: .init(identifier:"es"))`.
2. Flip `RequestsOpenAccess` to `true`, reinstall, enable Allow Full Access in Settings.
3. Re-run the Task 3 App Group write. Log whether it now succeeds.
4. Attempt `AVSpeechSynthesizer` with `usesApplicationAudioSession = false`, speaking one Spanish
   utterance. Log success or the `OSStatus`. Research 01 flags `OSStatus 561015905` as reported
   even *with* Full Access, so a failure here is an expected-possible outcome, not a mistake.
5. Log `AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("es") }` — count and
   qualities.
6. Read `hasFullAccess` in `viewDidLoad` and again in `viewWillAppear`, and log both. Research 01
   predicts the first is unreliable.

**Verification — P3's three outcomes, three designs:**

| `status(it -> es)` | Meaning |
|---|---|
| `.installed` or `.supported` | IT -> ES works. Italian stays in V1 as planned |
| `.unsupported` | **There is no IT -> ES pair.** Italian would require chaining two sessions through English in your own code, which teaches Spanish through a double-translated intermediate. **Recommend dropping Italian from V1** rather than shipping that |

- `hasFullAccess` differing between `viewDidLoad` and `viewWillAppear` confirms research 01 §1.5
  and locks the "read it on every appearance" rule into Phase 03.
- Whether App Group writes now succeed settles blocker B2 on this device, which the whole
  persistence design in Phase 05 depends on.

---

## Task 7 — P4: the cheap probes battery

**Files touched:** `ProbeKeyboard`.
**Depends on:** Task 6.

One button, one pass, all of these logged:

| Key | Call | Why it matters |
|---|---|---|
| `os_proc_avail.usable` | `os_proc_available_memory()` | Research 10 §6.1: may return `0` in an extension. If it does, `task_vm_info` is the only instrument, permanently |
| `nltagger.lemma.{en,es,it}` | `NLTagger.availableTagSchemes(for: .word, language:)` | **UNVERIFIED across three reports.** If Spanish `.lemma` is absent, Phase 05's bundled morphology table is mandatory rather than merely preferable |
| `nltagger.lemma.sample` | Lemma of `llegaré`, `dármelo`, `salgo` | Even where available, Apple calls `.lemma` a "stem" form. Verify it actually returns `llegar`, not `lleg` |
| `textchecker.languages` | `UITextChecker.availableLanguages` | Whether `es` and `it` are present depends on which system keyboards the *user* has added, not on your app |
| `lexicon.entries` | `requestSupplementaryLexicon` | Free autocorrect substrate, no Full Access. Log the count only, **never the contents** — it carries Address Book names |
| `langrecognizer.en_it` | `NLLanguageRecognizer` with `languageConstraints = [.english, .italian]` over 20 short real sentences | Sets the confidence floor and hysteresis thresholds for Phase 03 |
| `proxy.context.<host>` | `documentContextBeforeInput` in Messages, WhatsApp, Safari, Gmail, a WKWebView | Confirms the shadow-buffer requirement, and measures how much context you actually get per host |

**Verification:** every row above has a logged value. `nltagger.lemma.es` and
`os_proc_avail.usable` are the two that change downstream design; both must be written back to
`docs/research/03-apple-on-device-ai.md` and `10-iphone-13-constraints.md` respectively.

---

## Task 8 — P5, the self-check, and writing findings back

**Files touched:** `docs/research/*`, `.planning/STATE.md`, `.planning/PROJECT.md`,
`Probe/check-probes.sh`.
**Depends on:** Tasks 4-7.

**Steps:**
1. **P5:** render a keyboard-sized view with `.glassEffect` and one without, type 30 characters
   into each, and log frame timings. Research 10 §4.4 predicts GPU rather than CPU is the A15
   constraint and that iOS 26 is reported to lag on this device. If Liquid Glass costs frames,
   Phase 03 designs around it and Reduce Transparency becomes a first-class appearance.
2. **The self-check (ponytail rule).** Write `Probe/check-probes.sh`: parse `probe-log.txt` and
   assert that **every expected `PROBE <id> | <key>` pair is present**, exiting non-zero and
   naming the missing keys otherwise. Smallest thing that fails if a probe silently did not run.
   No framework.
3. Append findings to the research reports per D5, under `## Device-verified YYYY-MM-DD — iPhone 13`.
4. Update `PROJECT.md` only where a measurement contradicts a stated number (expected: the memory
   budget from Task 5; possibly the Italian scope from Task 6).
5. One `STATE.md` log entry summarising what was measured and what changed.

**Verification:**
- `bash Probe/check-probes.sh` exits 0 and prints the count of probes recorded.
- Every `UNVERIFIED` in the research corpus that this phase was scoped to settle is now either
  CONFIRMED with a measured value, or explicitly recorded as still-unresolved with the reason.
- `git log` shows the findings committed.

---

## Self-review — CONTEXT decision coverage

- **D1** measurements not product -> Tasks 3-8 build only a probe harness; Task 2's vendored tree
  is the one intentional survivor.
- **D2** probe ordering with P1 as a gate -> Tasks 4-8 in order; Task 4 states the stop condition
  explicitly in its verification table.
- **D3** real device only -> stated in project-wide constraints and in Task 3's verification.
- **D4** `task_vm_info` not `os_proc_available_memory` -> project-wide constraints; the question
  itself is probed in Task 7.
- **D5** findings written back, originals untouched -> Task 8 steps 3-5.
- **D6** Xcode 26 / iOS 26.0 -> project-wide constraints; the optional iOS 27 ANE probe is left
  out of the task list deliberately, as D6 makes it conditional on a spare device.
- **D7** free-tier acceptable, read the group ID from `Info.plist` -> Task 3 step 4.
- **D8** scene manifest and launch screen, no `connectedScenes.first` -> Task 3 step 3 and
  project-wide constraints.
- **D9** out of scope -> nothing in Tasks 1-8 touches the learning engine, autocorrect, emoji,
  the Share Sheet app, or the `TeachingEngine` protocol.

## Known verification caveats (acknowledge in the write-up, do not paper over)

- **Task 5 measures dirty anonymous pages, not `mmap`'d clean pages.** The sixth run addresses it,
  but the accounting of file-backed pages against `phys_footprint` remains **LIKELY, not
  CONFIRMED**, until that run produces a number. Phase 05's entire data budget rests on it.
- **Task 4 passing on iOS 26 does not guarantee iOS 27.** Research 10 §3 flags an unqualified
  entitlement sentence about background Neural Engine access, and Apple has changed
  keyboard-extension behaviour in a *point* release before, unannounced. **Re-run P1 before ever
  adopting the iOS 27 SDK.**
- **P3 cannot distinguish a direct IT -> ES model from an English pivot.** Apple exposes no API
  for this and it is unresolvable even on-device. Do not build anything that depends on knowing.
- **Task 7's `documentContextBeforeInput` results are per-host and per-OS-version**, and hosts
  change. Treat them as a snapshot that justifies the shadow buffer, not as a contract.
- **A single device is a sample of one.** Every number here is true for this iPhone 13 on this iOS
  build. That is the correct scope for a personal-use product, and it should be stated rather
  than quietly generalised.
