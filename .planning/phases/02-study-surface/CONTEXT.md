# CONTEXT — Phase 02: Study surface

Locked planning decisions for this phase. The planner treats these as fixed.

Inputs: `docs/STRESS-TEST.md`, `docs/research/01` through `10` with `10-iphone-13-constraints.md`
controlling, `.planning/phases/01-ground-truth/{CONTEXT,PLAN}.md`, and the built engine
(`LinguaKeyCore/`, `tools/engine/`, `tools/build-data/`).

## Goal (from ROADMAP)
The SwiftUI app plus Share Sheet extension. On-device translation and teaching over selected text
in any app, peninsular Spanish, with the event log and item-level A/B/C arm randomisation wired in
from the first commit. Read-only teaching, no insertion. This is the live pedagogy experiment and
it starts collecting data immediately.

## Locked decisions

### D1 — Phase 02 does not wait for Phase 01's probes
The roadmap lists 02 as depending on 01, and that dependency is real for exactly one thing: P1
asks whether `TranslationSession` runs **inside a keyboard extension**. A share extension is not
a keyboard extension. It is a normal app extension with a memory allowance around 120 MB, no
`RequestsOpenAccess` gate, no jetsam-on-sight ceiling, and no Full Access requirement for App
Group writes. None of the three findings that make P1 a gate apply to it.

So the whole of track B is buildable now, and it is the artifact the user can actually hold. If
P1 later fails, the roadmap loses the keyboard and this app becomes the product, which is exactly
the fallback D2 of Phase 01 already names. Building it first makes that fallback free instead of
a restart.

### D2 — The app must be useful with no network and no language pack
Translation is the only system dependency in this phase, and it is the one thing that can be
unavailable: the pack is a separate download, the device is on an iOS 27 beta, and the iPhone 13
is not Apple Intelligence capable so packs are not pre-staged.

Therefore translation is **additive, never load-bearing**. The lexicon carries a gloss for 99.8%
of lemmas and the morphology table carries the full analysis, both offline and both `mmap`'d, so
word-level teaching works with the radio off. A missing pack costs the sentence translation and
nothing else, and the UI says so in one line rather than failing.

This is not a nicety. A study surface that shows an error screen the first time it is opened,
before the 1.4 GB pack has downloaded, is a study surface that never gets opened again.

### D3 — `Translator` is a protocol with a real implementation and a null one
`TranslationSession` cannot be constructed outside SwiftUI's `.translationTask`, cannot be
unit-tested, and cannot run in the Simulator at all. Every one of those is a reason to keep it
behind a boundary rather than a reason to trust it.

One protocol, three conformances: the real one, a null one that reports unavailability (used when
the pack is missing and in the Simulator), and a canned one for tests. Nothing above the boundary
imports `Translation`.

### D4 — The store is an append-only event log, plus state derived by folding it
Not SwiftData, not Core Data. Three reasons, in order of weight:

1. Phase 08 has to fit the exposure efficacy weight from the event log and report whether it is
   distinguishable from zero. That requires every event, with its timestamp and its arm, kept
   forever. A mutable item row cannot answer it, and a schema that stores `mastery` is the exact
   mistake the stress test found in the PRD.
2. Two processes write: the app and the share extension. An append-only file with `O_APPEND`
   writes bounded to a single `write(2)` is atomic across processes. Concurrent SwiftData in an
   extension is a coordination problem with no upside here.
3. It is inspectable. A JSON-lines file can be read with `cat` during a beta with no tooling.

Item state (`[String: Item]`) is a **fold over the log**, cached to a snapshot file for startup
cost and rebuildable from the log at any time. If the snapshot and the log ever disagree, the log
wins, and there is a check that says so.

### D5 — Item-level A/B/C arm assignment, deterministic, from the first commit
Assignment is `hash(installSalt + itemKey) % 3`, decided once per item and recorded in the event.
Deterministic so it survives a reinstall of the app with the same salt, item-level so one user
generates all three arms, and recorded in the event rather than looked up later so a change to
the assignment function cannot retroactively rewrite history.

Arms are the presentation of the same selected focus, never a different focus:
- **A — recognition.** The gloss is shown.
- **B — retrieval.** The learner is asked first, gloss revealed after.
- **C — control.** Nothing is shown, the exposure is logged.

C is a third of the data and it is the only thing that makes A and B mean anything. It is also
the arm that will feel broken. It stays.

### D6 — Read-only. No insertion, no writing back into the host app
Kept from the roadmap and from the stress test's finding that the insert-into-a-live-message
interaction is unsupported by both the UX walkthrough and the acquisition literature. The share
extension reads the selection and teaches; it never returns modified text.

### D7 — Peninsular es-ES, and the interference lexicon is Italian-and-English
Locked with the user. `vosotros` is a form, not a curiosity. The false-friend list is the
authority on traps and the orthographic cognate score is never used as one.

### D8 — iOS 26.0 deployment target, Xcode 27 beta toolchain, free personal team
Inherited from Phase 01 D6 as amended: the phone is on an iOS 27 beta so Xcode 26 cannot install
onto it at all, and the App Store SDK floor does not bind a device that is never submitted.
Consequences that this phase must design around, not discover:
- the build expires after **7 days** and dies mid-sentence with no warning
- three app-extension slots total, so the share extension and the keyboard compete
- no TestFlight, no App Store, the phone is the only deployment target

### D9 — The Xcode project is committed, and uses file-system synchronized groups
`objectVersion 77` with `PBXFileSystemSynchronizedRootGroup`, so a new Swift file appears in the
build with no project-file edit and no merge conflict in a 4000-line pbxproj. Team ID and bundle
prefix come from a gitignored `Local.xcconfig` with a committed example, because a free personal
team's identifiers are per-developer and must not be in the repository.

### D10 — The tables are staged, not bundled twice
`tools/stage-data.sh` assembles `build/LinguaKeyData`, which is added to the project as a folder
reference and copied into the app bundle, then copied once into the App Group container on first
launch so the extension can `mmap` it without a second copy in its own bundle. Settled in the
`LinguaKeyCore` commit and restated here because it is the thing most likely to be undone by
someone adding a resource the easy way.

## Gray areas left open

- **G1 — does `TranslationSession` work in a share extension on this iOS 27 beta?**
  Expected yes, and D2 makes a no survivable rather than fatal. Answered by running it, and the
  answer is written back into `docs/research/` the same way Phase 01's probes are.
- **G2 — how much text does the share sheet actually deliver from each host?**
  Safari gives the selection, Messages gives the message, some hosts give a URL and no text at
  all. The set is host-dependent and undocumented, exactly like `documentContextBeforeInput`.
  Handle the shapes that arrive, log the ones that do not.
- **G3 — retrieval-first presentation timing in arm B.**
  How long the learner is given before the gloss reveals, and whether the reveal is on tap or on
  a timer. Left to the build because it is a feel decision and both are cheap to change.
