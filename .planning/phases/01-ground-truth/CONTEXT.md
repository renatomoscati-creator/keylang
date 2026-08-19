# CONTEXT — Phase 01: Ground truth

Locked planning decisions for this phase. The planner treats these as fixed. There is no prior
phase, so the research corpus is the input: `docs/STRESS-TEST.md` for the synthesis and
`docs/research/01` through `10` for the evidence, with `10-iphone-13-constraints.md` as the
controlling document wherever it disagrees with an earlier report.

## Goal (from ROADMAP)
Resolve every research UNVERIFIED that gates a design decision, before any product code exists.
Vendor OpenKeyboardKit and prove it builds under Xcode 26. Ship a throwaway on-device probe
harness on the actual iPhone 13 and write every answer back into `docs/research/` as CONFIRMED.

## Locked decisions

### D1 — This phase produces measurements, not product
Nothing built here survives into Phase 02 or 03 except **numbers, a vendored dependency, and
written findings**. The probe harness is explicitly throwaway: no architecture, no abstractions,
no tests beyond the self-check, no reuse obligation. Anything that looks like product code in
this phase is scope creep and should be deleted.

The one exception is the vendored OpenKeyboardKit tree, which is a deliverable in its own right.

### D2 — Probe ordering is fixed, and P1 is a gate
The probes run in this order because each one can invalidate the ones after it:

1. **P1 — `TranslationSession` inside a keyboard extension.** **This is a go/no-go gate.** If it
   throws a sandbox or XPC error, the keyboard cannot translate, and the product becomes the
   Share Sheet app. Every subsequent phase in the roadmap assumes P1 passes. **If P1 fails, stop,
   do not run P2 onward, and re-plan the roadmap before spending another hour.**
2. **P2 — the five-run destructive memory measurement.** Sets the real budget and therefore
   constrains every design decision in Phases 03 through 06.
3. **P3 — `LanguageAvailability.status(from: it, to: es)`.** Three possible answers imply three
   different product designs, one of which is dropping Italian from V1.
4. **P4 — the cheap probes battery.** Individually small, collectively decisive for Phase 05's
   data design.
5. **P5 — Liquid Glass cost on a keyboard-sized view.** Lowest stakes; can be deferred if time
   runs out, but not skipped silently.

### D3 — Everything is measured on the real iPhone 13, never the Simulator
Non-negotiable and stated in three separate research reports. The Simulator: does not run the
Translation framework at all (Apple, explicit); does not enforce extension memory limits; and
succeeds at App Group writes that fail on device. **A Simulator result is not a result.** Any
finding in this phase recorded without a physical-device run is invalid.

### D4 — Instrument with `task_vm_info.phys_footprint`, not `os_proc_available_memory()`
Apple documents `os_proc_available_memory()` as returning `0` when the calling process is not an
app, and a keyboard extension is not an app. Whether it returns a real number here is itself one
of the P4 probes. Until that probe answers, `task_vm_info.phys_footprint` is the only trusted
instrument, and a `0` from `os_proc_available_memory()` must be read as "unusable", never as
"out of memory".

### D5 — Findings are written back as CONFIRMED, in place, with dates
Each probe's result is appended to the research report it settles, under a clearly marked
heading (`## Device-verified YYYY-MM-DD — iPhone 13`), with the measured value, the raw log line,
and the date. **Do not rewrite the original UNVERIFIED text** — the reports are a provenance
record and the delta between what was inferred and what was measured is itself valuable. The
same discipline the App Group correction already used.

`STATE.md` gets one log entry summarising what changed, and `PROJECT.md` constraints are updated
only where a measurement contradicts a stated number.

### D6 — The build target is Xcode 26 and iOS 26.0, and this phase does not revisit it
Confirmed in research 08: the iOS 26 SDK floor took effect 2026-04-28, there is no iOS 27
deadline anywhere on Apple's Upcoming Requirements page, and the App Store currently accepts no
iOS 27-SDK build at all. iOS 27 exposes no new keyboard-extension API, verified four ways.

**One exception worth a probe if an iOS 27 device is available:** research 10 flagged that iOS
27's Neural Engine background restriction carries an entitlement sentence unqualified by device
class, and Apple's translation models plausibly use the ANE. If on-device translation from inside
a keyboard is throttled on iOS 27, that is a Phase-05-breaking finding and it is cheaper to learn
now. **Optional, and only if a second device or a spare partition exists.** Do not put the
primary phone on an iOS 27 beta to find out.

### D7 — Free-tier provisioning is acceptable for this phase
Research 09 established that App Groups and Keychain Sharing are free-tier capabilities and that
the real blocker is the 7-day profile expiry. A measurement phase does not run for seven days, so
**the paid membership is not required to complete Phase 01.** It is required before the first
dogfooding milestone, which is Phase 04's acceptance criterion.

If a sideloader is used for convenience, note that AltStore rewrites App Group IDs to append the
Team ID, so any probe that touches a shared container must **read the group ID from `Info.plist`
at runtime rather than hardcoding it.**

### D8 — Two zero-cost Info.plist items land in this phase
`UIApplicationSceneManifest` and a launch-screen key on the containing app. Both become mandatory
under the iOS 27 SDK, both are ~30 minutes now, and both are free to do while the project is
empty. Also: never write `UIApplication.shared.connectedScenes.first`, because iOS 27 beta 3
began delivering a second keyboard-input scene to containing apps and Apple states ordering is
not guaranteed.

### D9 — Out of scope for Phase 01
- Any keyboard UI beyond what a probe needs to render a button and a label.
- Any learning-engine code, item model, FSRS implementation, or bundled linguistic data.
- Any autocorrect, suggestion, or emoji work.
- The Share Sheet study app (Phase 02).
- The `TeachingEngine` protocol (Phase 05).
- Buying the Apple Developer Program membership, unless the developer wants to.

## Gray areas: resolved 2026-08-19

- **G1 — Mac: MacBook Pro, M4 Pro (Apple silicon).** Xcode 27 is available; the eventual iOS 27
  SDK move is not a hardware purchase.
- **G2 — iPhone 13 is on an iOS 27 beta.** Two consequences, one of which overrides D6.
- **G3 — Free personal team.** Consistent with D7. Adds one probe: whether Xcode's Signing and
  Capabilities pane will add an App Group for a Personal Team is LIKELY, not confirmed
  (research 09 §0), so Task 3 finds out. A refusal is a finding, not a blocker; the harness falls
  back to the extension's own container and records `container.kind = local`.

### D6 AMENDED by G2 — build with Xcode 27 beta, not Xcode 26

D6 preferred Xcode 26 because research 08 confirmed the App Store accepts no iOS 27-SDK build.
**That constraint does not bind this project**: free tier, personal device, never submitted. And
Xcode cannot install or debug onto a device running an OS newer than its SDK, so **Xcode 26
cannot deploy to a phone on an iOS 27 beta at all.**

- Toolchain: **Xcode 27 beta** (needs macOS 26.4+, Apple silicon; the M4 Pro qualifies)
- Deployment target: **iOS 26.0, unchanged.** Nothing needs 27, and it keeps the option open.
- Revisit if the project ever heads for the App Store, at which point the SDK floor applies again.

### D6's optional ANE probe is now MANDATORY

D6 made the iOS 27 Neural Engine probe conditional on a spare device, and said not to put the
primary phone on an iOS 27 beta to find out. **The phone is already there.**

iOS 27 restricts background Neural Engine access behind a new entitlement, and the sentence
introducing it is **not qualified by device class**, while the surrounding paragraph is scoped to
Apple Intelligence devices. Apple's `.lowLatency` translation models plausibly use the ANE. So P1
is now being run on the riskiest OS rather than the safest, which is better to know early but
changes how a failure must be read:

**If P1 fails, or if translation from the keyboard is markedly slower than the same call from the
host app in the foreground, suspect the ANE background restriction before concluding that
`TranslationSession` is extension-hostile.** The diagnostic is the comparison: run the identical
translation from `ProbeApp` in the foreground and from `ProbeKeyboard`, and log both. Only a
foreground-succeeds / keyboard-fails split points at the background restriction; a both-fail
result points at the extension sandbox.
