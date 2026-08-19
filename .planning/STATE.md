# State: keylang

current phase: 02 - study surface (built, pending on-device verification), with phase 01's
probes still waiting on hardware and phase 05's engine work pulled forward because neither
depends on the probe outcome
status: everything that can be built without the hardware has been built. The linguistic data
build (`tools/build-data/`), the reference engine (`tools/engine/`), the Swift engine
(`LinguaKeyCore/`), the study surface and its store (`LinguaKeyApp/`), the app and share
extension targets, and a hand-written `LinguaKey.xcodeproj`. `./setup.sh` prepares a machine and
`./check.sh` verifies all of it in one command, with no Xcode and no device: 159 assertions
across 8 suites.
What remains needs hardware this session cannot reach, a MacBook Pro M4 Pro on Xcode 27 beta and
the physical iPhone 13 on iOS 27 beta: phase 01's probes (P1 is still the gate for the KEYBOARD,
not for the share extension), and phase 02's tasks T5 through T8, which are the first build, the
first run and the answers to gray areas G1 and G2. All ten research passes are complete.

## Log
- 2026-08-18 project initialized from a seven-agent research pass rather than a brainstorm
  ledger. Source PRD imported unmodified as `docs/PRD.md`; seven verbatim research reports in
  `docs/research/`; synthesis in `docs/STRESS-TEST.md`. Three user decisions locked: product
  shape = both tracks in parallel (keyboard shell and study surface, sharing one engine);
  Spanish variety = peninsular es-ES; and the $99 developer-program question deferred pending
  research into free personal-device paths. Three decisions taken on research evidence without
  needing the user: deployment target iOS 26.0 on the Xcode 26 SDK (iOS 27 adds no
  keyboard-extension API, verified four ways); keyboard foundation = vendor OpenKeyboardKit
  MIT source rather than the now-closed-source KeyboardKit binary; and architecture inverted to
  on-device-first (Apple Translation framework plus Foundation Models, both confirmed to run
  in a keyboard extension without Full Access), which removes the proxy, the API key and the
  per-request cost from V1 entirely.
- 2026-08-18 stress test complete. Four Phase-0 blockers found that the PRD does not mention:
  App Groups and Keychain sharing require the paid developer program; App Group *writes*
  additionally require Full Access, making PRD sections 19 and 23 mutually inconsistent; the
  memory ceiling is ~30-60 MB enforced by silent jetsam; and KeyboardKit's autocomplete engine,
  which the PRD names as the reason to adopt it, is paywalled at roughly $1,500/yr for the
  three locales this product needs. Separately, the learning model was found not to be a memory
  model at all (a stored float cannot decay, and counting exposure as learning is
  self-reinforcing), and the core insert-translation-into-a-live-message interaction was found
  unsupported by both the UX walkthrough and the vocabulary-acquisition literature.
- 2026-08-18 HARD CONSTRAINT added by user: the target device is an **iPhone 13**, and only an
  iPhone 13. This is not a preference, it is the machine the product runs on. Consequence: the
  iPhone 13 is not Apple Intelligence capable (that requires A17 Pro or better), so the
  **Foundation Models framework is permanently unavailable on this device**. Half of the
  architecture inversion recorded in the entry above therefore does not apply. Translation is
  expected to survive because it is not Apple Intelligence gated and iOS 26.4 documents a
  `.lowLatency` strategy as using "traditional models on all devices", but the language packs
  will not be pre-downloaded the way they are on an Apple Intelligence device, so the host app
  must trigger the download explicitly. The teaching layer (focus selection, glossing,
  explanation, correction, recall generation) has lost its planned engine and must be re-sourced
  from bundled deterministic data, a remote call on explicit user action, or both. Research is
  out to verify Translation on non-eligible hardware, iPhone 13 support for iOS 26 and 27, the
  keyboard memory ceiling on a 4 GB device, and what a fully deterministic teaching layer can
  and cannot do. PROJECT.md constraints and scope updated; ROADMAP phase 01 and 05 will need
  revision once that research lands. Two smaller upsides: 60 Hz relaxes the frame budget from
  8.3 ms to 16.7 ms, and a single known target device makes phase 01's measurements exact
  rather than a range across a device matrix.
- 2026-08-19 CORRECTION to a Phase-0 blocker. Research 04 concluded that App Groups and Keychain
  Sharing require the paid Apple Developer Program, and that conclusion propagated into
  STRESS-TEST.md blocker B1 and into PROJECT.md's open prerequisite. It is wrong. Apple's own
  capability matrix lists both as available in the free tier, and AltStore's production signing
  path creates App Group identifiers through the portal API for free teams with no gate, shipping
  an app plus an app extension that share one. The original error was over-reading an accurate
  Apple DTS quote: it says the portal must mint the group, not that it refuses free teams. What
  is actually gated is Xcode's automatic-signing UI, not the entitlement. Consequence for
  planning: the persistence design (PRD section 12 P0, section 19, section 7 keychain BYOK) is
  NOT blocked by the free tier and can be built and validated without paying. The paid membership
  is still effectively mandatory, but for the 7-day provisioning-profile expiry, which no
  sideloader can extend because it is enforced server-side at signing, and whose failure mode is
  a silent mid-sentence death of the keyboard requiring a laptop to recover. Revised sequencing:
  the 99 dollars lands before the first dogfooding milestone rather than before the first line of
  code. Also ruled out: LiveContainer cannot host app extensions at all, and every EU DMA
  distribution route is a superset of the paid membership rather than an alternative to it.
  Correction notice appended to research 04 rather than rewriting it, so the original reasoning
  stays auditable. STRESS-TEST.md B1 and decision D1 revised.
- 2026-08-19 iPhone 13 verification landed and RESOLVES the open question from the constraint
  entry above. Foundation Models is permanently unavailable and **Private Cloud Compute does not
  rescue it**: Apple states in three places that PCC is only available on devices that support
  Apple Intelligence, so the server model is gated on the client being eligible hardware. That is
  a closed door on every iOS version. Translation survives fully and is now CONFIRMED rather than
  hoped: Apple's own API reference says `.lowLatency` "is the default strategy for devices without
  Apple Intelligence", headless `TranslationSession(installedSource:target:)` is iOS 26.0 with no
  eligibility precondition, and downloaded packs are a system-wide store shared with all apps, so
  the host app downloads and the keyboard consumes. Apple documents the quality gap versus
  `.highFidelity` only as "not as fluent" and publishes no number for any pair, so a manual eval
  over 100 sentences the author actually sent is the only quality figure this project will ever
  have. Decision taken on the evidence: **the V1 teaching layer is bundled deterministic data
  authored at build time by a frontier model on a Mac**, not a runtime model. Three of the five
  teaching capabilities are better for it, and it is less work, because it deletes the prompt
  contract, schema validation, latency budget, rate-limit handling and streaming UI. A remote
  escalation rung moves to V1.1, explicit-tap only. Core ML in the host app is rejected outright
  because the host app is not running when the user types in another app and there is no supported
  way to wake it. Memory budget lowered from 40/30 to **25 design / 20 alarm / 35 hard**, because
  4 GB sits at the bottom of the supported RAM class and jetsam there also fires on system-wide
  pressure. Also corrected: the frame budget is 16.7 ms not 8.3 ms (60 Hz), GPU rather than CPU is
  the A15 concern, `os_proc_available_memory()` may return 0 in an extension so instrument with
  `task_vm_info.phys_footprint` instead, and peninsular Spanish turns out to be the only Spanish
  variety Apple Translate offers before iOS 27, so decision D6 is currently made by the platform
  rather than by us. iOS 26 and iOS 27 both run on this device and iOS 27 drops nothing, so the
  iOS 26.0 / Xcode 26 floor holds unchanged. One new high-impact UNVERIFIED: iOS 27's Neural
  Engine background restriction carries an entitlement sentence that is unqualified by device
  class, and Apple's translation models plausibly use the ANE, so on-device translation from
  inside the keyboard could be throttled on iOS 27 even though none of it is Apple Intelligence.
  PROJECT.md constraints, why-now and scope updated; ROADMAP phases 01 and 05 rewritten;
  STRESS-TEST section 2 revised with a preamble rather than a rewrite.
- 2026-08-19 phase 01 gray areas RESOLVED with the user, and one of them amends a locked decision.
  G1 MacBook Pro M4 Pro (Apple silicon). G2 the iPhone 13 is already on an **iOS 27 beta**. G3 free
  personal team. G2 overrides D6: Xcode cannot deploy to a device running an OS newer than its SDK,
  so Xcode 26 cannot install onto this phone at all, and the App Store SDK floor that made Xcode 26
  attractive does not bind a free-tier personal device that is never submitted. Toolchain is now
  **Xcode 27 beta**, deployment target unchanged at iOS 26.0. G2 also promotes D6's optional Neural
  Engine probe to mandatory: iOS 27 restricts background ANE access behind a new entitlement whose
  introducing sentence is not qualified by device class, and Apple's `.lowLatency` translation
  models plausibly use the ANE, so P1 is now being run on the riskiest OS rather than the safest.
  Every translation probe therefore runs twice, once from the host app in the foreground and once
  from the keyboard, because only a foreground-succeeds / keyboard-fails split distinguishes the
  background restriction from an extension-sandbox refusal. Probe harness written and committed
  under `Probe/`: shared append-only logger flushed per line so results survive the deliberate
  jetsam kill, `task_vm_info` instrumentation with `os_proc_available_memory` probed rather than
  trusted, host app for language-pack download via `.translationTask`, keyboard extension carrying
  all seven probes, and a self-check that names any probe which never ran (verified against a
  partial log: 3 found, 19 named missing). Phase 01 is now executable; the remaining work is on
  hardware this session cannot reach.
- 2026-08-19 engine PORTED to Swift and pinned to the reference. `LinguaKeyCore/` now carries the
  memory model, the mmap'd table reader, the false-friend list and the focus selector as a pure
  Foundation SwiftPM package with no UIKit, Translation or SwiftUI dependency, so it compiles and
  tests on the Mac with no device and no provisioning profile. No Swift toolchain is reachable from
  this session, so the port is verified by mechanism rather than by having run it: 336 golden
  scalars and 8 full scenario replays from `tools/engine/golden.py` are compared step by step
  against the Python reference, and the focus behaviours are ported as behaviour tests over the
  same built tables rather than as frozen vectors, because freezing selector output would freeze
  the 3.7 MB data build with it and a rebuild would then read as a regression. Porting surfaced
  four real divergences from the reference, all now fixed in the Swift and all four invisible
  until an exact tie or a suppressed word occurred: `max(by:)` keeps the LAST maximal element
  where Python's `max` keeps the first, so ambiguous readings could resolve to different lemmas;
  `Array.sort` is not stable where Python's `list.sort` is, so equal-scoring candidates could
  order differently; the reason ladder had drifted (`readiness < 1.0` instead of `r < 0.85`, and
  a missing "very common" branch); and a suppressed lemma silenced only its vocabulary note and
  not its grammar note, which would have kept annotating the paradigm cell of a word the learner
  had demonstrably mastered. The last one is a genuine behaviour bug, not a porting artifact, and
  it now has a test on both sides. Reference suite is up from 22 to 26 focus behaviours (tokenizer
  digits, NFC decomposed-versus-precomposed accents, and suppression being total). Decision taken
  without the user: the package ships **no** SPM resources. A keyboard extension reads its tables
  from the App Group container, never from `Bundle.module`, so bundling them would put a second
  3.9 MB of identical binary under version control to serve a code path the product never takes;
  `tools/stage-data.sh` assembles the single runtime data root instead, and the tests reach the
  committed copies via `#filePath`.
- 2026-08-19 phase 02 BUILT, minus the on-device verification. The study surface exists as an app
  and a share extension: `LinguaKeyApp/Sources/{StudyKit,StudyUI,StudySystem}` plus the two
  targets and a hand-written `LinguaKey.xcodeproj`. Decisions taken without the user, all in
  CONTEXT: the store is an append-only JSON-lines log with item state as a fold over it (phase 08
  has to fit the exposure efficacy weight from every event ever written, which a mutable item row
  cannot answer); arms are assigned by FNV-1a over an install salt plus the item key, never by
  `Hasher`, which is seeded per process and would reassign arms on every launch while looking like
  working code; and the whole surface is useful with no language pack, because the lexicon carries
  a gloss for 99.8% of lemmas offline and an app that shows an error screen the first time it is
  opened is an app that never gets opened again. G3 resolved during the build: arm B reveals on
  tap, never on a timer, because a timer measures reading speed as much as retrieval.
  The Xcode project is the risk. It was hand-written because there is no Xcode here, so
  `tools/check_project.py` makes 71 structural claims about it: every reference resolves, both
  targets have both configurations, every `INFOPLIST_FILE` and entitlements path exists on disk,
  the appex is embedded into PlugIns and the app depends on it, `Info.plist` and the entitlements
  are excluded from synchronized-folder target membership, every linked package product is one the
  package actually exports, the extension bundles no second copy of the tables, and no Team ID is
  committed. What none of that can catch is whether Xcode likes the result, which needs Xcode.
  It uses `objectVersion 77` with `PBXFileSystemSynchronizedRootGroup`, so adding a Swift file
  never touches the project file and never produces a merge conflict in it.
  `./check.sh` now runs 8 suites and 159 assertions in total. `./setup.sh` builds the tables,
  stages them and creates `Local.xcconfig` in one command.
- 2026-08-19 the store and the fold PINNED to the reference, which closes the last piece of
  load-bearing Swift whose only test could not run here. `tools/engine/store.py` mirrors the
  Event shape, the JSON rules and the fold; `golden_store.py` writes a real 45-event log across
  8 items plus the state it must produce. The Swift test copies that log into a temporary App
  Group, reads it back through the real `EventLog` and folds it through the real `ItemStore`, so
  one pass exercises the field names, the channel raw values, the absent-versus-null rule for
  optionals, the torn-line tolerance, the complete-byte-count arithmetic and every trace scalar.
  The items were chosen so BOTH answers of the suppression rule are pinned rather than only the
  negative one. Two cross-language checks added because golden vectors only cover the channels
  they happen to use: every `Channel` raw value and every `Grade` number must match between the
  Swift and the reference, both proven by introducing the drift they catch.
  `./check.sh` is now 187 assertions across 8 suites. Nothing further can be validated without
  hardware: this session has no macOS, no Xcode, no device, and no reachable Swift toolchain
  (swift.org returns 403 through the proxy and there is no container runtime). The next move is
  `.planning/phases/02-study-surface/HANDOFF.md`, run on the M4 Pro.
