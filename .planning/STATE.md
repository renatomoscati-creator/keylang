# State: keylang

current phase: 01 - ground truth
status: project INITIALIZED. PROJECT.md, ROADMAP.md (8 phases), config.json written from a
completed research and stress-test pass. No phase planned yet. Two prerequisite questions are
out to research (Apple Developer Program necessity, iOS 27 SDK submission floor) and must land
before phase 01 CONTEXT can lock.

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
