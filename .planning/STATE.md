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
