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

## Open gray areas

Three facts about the developer's own setup change the exact steps and are not yet known. The
planner should write the plan parameterised on them and the executor should fill them in before
starting:

- **G1 — Which Mac, Intel or Apple silicon?** Xcode 26 is universal so either works today.
  Xcode 27 is Apple-silicon-only and needs macOS 26.4+, so on an Intel Mac the eventual iOS 27
  SDK move is a hardware purchase rather than an update. Does not block Phase 01; does change
  what "later, take the 27 SDK" costs.
- **G2 — Which iOS is on the iPhone 13 right now, 26.x or a 27 beta?** Decides whether the
  optional D6 ANE probe can run at all, and whether P1's result generalises to the shipping OS
  or to a beta.
- **G3 — Free provisioning, or is the membership already bought?** Decides whether the probe
  harness is installed from Xcode directly (7-day, fine for this phase) or through a sideloader,
  and therefore whether the `Info.plist` App Group indirection in D7 is needed.
