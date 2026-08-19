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
