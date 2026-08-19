# PLAN — Phase 02: Study surface

Executes `CONTEXT.md`. Nine tasks. T1 through T4 are the engine-side work and are verifiable on
any machine; T5 onward need Xcode 27 beta on the M4 Pro and the iPhone 13 on iOS 27 beta.

## Project-wide constraints

- **Deployment target iOS 26.0, toolchain Xcode 27 beta, free personal team.** The build expires
  after 7 days. Nothing may depend on the app having been installed longer than that.
- **Memory.** The share extension's allowance is roughly 120 MB, not the keyboard's 25 to 40 MB.
  This phase still holds to the keyboard's discipline (`mmap` everything, decode nothing into a
  dictionary) because Phase 06 reuses this engine inside the keyboard and a habit formed here is
  what survives.
- **No `Translation` import above the `Translator` protocol.** Checked mechanically in T9.
- **No stored `mastery`.** It is derived at read time, always. Checked mechanically in T9.
- **Every user-visible Spanish string is peninsular.**
- **House style.** Comments say why, not what. No em-dashes.

## Shared contract

The store and the engine are one package, `LinguaKeyApp/Sources/StudyKit`, depended on by both
the app and the share extension. Neither target holds logic the other cannot reach.

```
Event            append-only, Codable, one JSON line per record
  id             UUID
  at             TimeInterval, seconds since 1970, device clock
  itemKey        String, "LEM:vaso|N|0" or "CELL:V|IND,FUT,1,SG"
  channel        Channel, from LinguaKeyCore
  grade          Grade?, nil for ungraded channels
  arm            Arm, .recognition / .retrieval / .control
  surface        String, the form actually seen
  sourceApp      String?, the host bundle id if the extension can see it
  sentenceHash   UInt64, so repeated study of one sentence is detectable without storing it

EventLog         append-only file in the App Group container
  append(_:)     single write(2) with O_APPEND, atomic across processes
  events()       streaming read, tolerant of a torn final line

ItemStore        fold over the log
  state          [String: Item], never persisted as the source of truth
  snapshot       cache file, rebuilt from the log when it disagrees
  arm(for:)      deterministic, hash(installSalt + itemKey) % 3

StudySession     one selected text, start to finish
  focus          [Candidate], from LinguaKeyCore.FocusSelector
  translation    String?, nil when no pack
```

## Tasks

### T1 — StudyKit: the event log
Append-only JSON-lines file in the App Group container. `append` opens with `O_APPEND|O_WRONLY`,
writes one line in a single `write(2)`, closes. Read is streaming and drops a torn final line
rather than throwing, because a jetsam kill mid-write is the expected case on this device, not an
exceptional one.

**Verify.** Unit tests: a torn final line is dropped and the rest survives; two writers
interleaving 500 events each produce 1000 intact lines with no partial rows; an unknown `channel`
value in an old record does not fail the whole read.

### T2 — StudyKit: item state as a fold
`ItemStore.rebuild()` replays the log through `Item.observe`. Snapshot to a plist for startup
cost, with the log's byte count and last event id in the header; on mismatch, rebuild and log
that it happened.

**Verify.** Unit tests: fold of a known log equals the state built by applying the same events
directly; a corrupted snapshot rebuilds rather than throwing; the snapshot is never read when the
log has grown past its recorded offset.

### T3 — StudyKit: arm assignment
`hash(installSalt + itemKey) % 3` with a stable hash (FNV-1a, not `Hasher`, which is seeded per
process and would reassign arms on every launch). Salt generated once and stored in the App
Group.

**Verify.** Unit tests: same salt and key give the same arm across processes; 10,000 keys
distribute within 2% of a third each; `Hasher` is not used anywhere in the assignment path.

### T4 — StudyKit: the session
Tokenize, look up, select focus via `LinguaKeyCore.FocusSelector`, attach an arm per candidate,
emit the events. Control arm emits its exposure event and returns nothing to display.

**Verify.** Unit tests over the real tables: a sentence with a false friend produces a trap
candidate in arms A and B and an event but no candidate in arm C; a sentence of function words
produces no candidates and no events; suppressed items produce neither.

### T5 — The Xcode project
`LinguaKeyApp.xcodeproj`, objectVersion 77, three targets: app, share extension, StudyKit package
reference. File-system synchronized groups. `Local.xcconfig` gitignored with a committed example
carrying `DEVELOPMENT_TEAM` and `BUNDLE_PREFIX`. App Group entitlement on both targets.

**Verify.** `xcodebuild -scheme LinguaKey -destination generic/platform=iOS build` succeeds on
the M4 Pro. Both targets appear in the built `.app`. The App Group id in both entitlements files
is identical and matches the one `StudyKit` reads.

### T6 — The host app
Three screens, no more. **Today**: what is due and what was learned, from the fold. **Library**:
every item, its state, and its arm, sortable, because this is how the experiment gets debugged.
**Setup**: language pack download via `.translationTask`, App Group data staging on first launch,
and the log's size and event count with an export button.

**Verify.** On device: fresh install stages the tables and reports their size; pack download
completes and the state persists across a relaunch; export produces a file that round-trips
through `EventLog.events()`.

### T7 — The share extension
`NSExtensionPrincipalClass` with a SwiftUI root. Accepts `public.plain-text` and `public.url`.
Reads the selection, runs a `StudySession`, presents the arm's UI, writes the events, dismisses.
Never returns modified text.

**Verify.** On device, from Safari, Messages, Notes and Mail: the selection arrives, the
extension shows within 1 second, the events land in the log, and the app sees them on next
launch. Log the item-provider type identifiers that arrive from each host, which is G2's answer.

### T8 — Translation, behind the protocol
Real conformance using `.translationTask` in a hosting view, null conformance reporting
unavailability, canned conformance for tests. `LanguageAvailability` checked before offering.

**Verify.** On device with the pack installed, with it removed, and in the Simulator. All three
must reach a usable screen. The Simulator run is the one that proves D2, because it cannot
translate at all.

### T9 — The mechanical checks
Extend `check.sh`: no `import Translation` outside the one file that is allowed it; no stored
`mastery` anywhere; the App Group identifier is the same string in every place it appears; the
staged data root matches `build/` byte for byte.

**Verify.** `./check.sh` passes, and each check is proven by temporarily introducing the
violation it is meant to catch.

## Self-review against CONTEXT

- D1 (no wait on Phase 01): T1 through T4 and T9 are machine-independent; only T5 onward need the
  hardware. Nothing here is gated on P1.
- D2 (useful with no pack): T8's verification requires a usable screen in all three states, and
  the Simulator case cannot be satisfied by accident.
- D3 (protocol boundary): T8 builds it, T9 enforces it mechanically rather than by review.
- D4 (append-only log): T1 and T2. The "log wins" rule is a test in T2, not a comment.
- D5 (arm assignment): T3, including the `Hasher` trap, which is the failure that would look like
  working code and quietly destroy the experiment.
- D6 (read-only): T7 states it and there is no code path that returns text.
- D7 (peninsular, curated traps): T4's false-friend test uses the curated list. Peninsular strings
  are a review item, not a mechanical one, and that is a known gap.
- D8 (7-day expiry): the export button in T6 exists because of it. The log is the only thing worth
  more than the build.
- D9 (project layout): T5.
- D10 (staged tables): T6's first-launch staging and T9's byte-for-byte check.
- G1 (translation in a share extension): answered by T8 on device and written back to
  `docs/research/`.
- G2 (what the share sheet delivers): answered by T7's logging, per host.
- G3 (arm B timing): decided in T7 during the build, and recorded in SUMMARY.

## Known caveats

- **The 7-day expiry is not solved, only survived.** Every seventh day the app must be
  reinstalled from Xcode, and the log in the App Group container survives that only if the app is
  not deleted first. This needs saying out loud in the README, because deleting the app to
  reinstall it destroys the experiment.
- **The event log has no size bound.** At the volume one person generates this is fine for the
  duration of the experiment, and adding rotation now would add a way to lose data for no benefit.
- **Peninsular correctness is unchecked by machine.** The data build has no es-ES verification
  step. It is a review item and it will drift.
- **The device clock is the only clock.** Timestamps are `timeIntervalSince1970` from an
  unsynchronised device. A manual clock change corrupts intervals, and nothing detects it.
