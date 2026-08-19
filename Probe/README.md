# Phase 01 probe harness

Throwaway. Measures the things only a physical iPhone 13 can answer, writes them to one
append-only log, and gets deleted. Nothing here survives into Phase 02.

Plan: [`.planning/phases/01-ground-truth/PLAN.md`](../.planning/phases/01-ground-truth/PLAN.md)

## Your setup, resolved

| | |
|---|---|
| Mac | MacBook Pro, M4 Pro (Apple silicon) |
| iPhone 13 | **iOS 27 beta** |
| Provisioning | **Free personal team** |

### Use Xcode 27 beta, not Xcode 26

The plan originally said Xcode 26. **That was written before we knew the phone is on iOS 27 beta.**
Xcode cannot install or debug onto a device running an OS newer than its SDK, so Xcode 26 simply
will not deploy here.

The reason the plan preferred Xcode 26 was that the App Store accepts no iOS 27-SDK build
(research 08). **That does not bind you**: free tier, personal device, never submitting. So:

- **Toolchain:** Xcode 27 beta
- **Deployment target:** iOS 26.0 (unchanged — nothing needs 27, and it keeps the option open)
- Xcode 27 needs macOS 26.4 or later, and is Apple-silicon only. Your M4 Pro is fine.

### Free-tier consequences

- **Profiles expire after 7 days.** Fine for a measurement phase. Re-run from Xcode if it lapses.
- **Two App IDs** get consumed (host + extension) out of 10 per rolling week. Roughly 5 reinstalls
  a week before you are locked out; you can hit that during heavy iteration.
- **App Groups are a free-tier capability** (research 09, corrected from research 04). But whether
  Xcode's Signing & Capabilities pane will *add* one for a Personal Team is `LIKELY`, not
  confirmed. **If it refuses, that is a finding, not a blocker** — the log falls back to the
  extension's own container automatically and records `container.kind = local`.

## Setup

1. **New Xcode project** → iOS App → `ProbeApp`, SwiftUI, deployment target **iOS 26.0**.
2. **Add target** → iOS → Custom Keyboard Extension → `ProbeKeyboard`.
3. **Add the files:**
   - `Shared/ProbeLog.swift`, `Shared/Memory.swift` → membership in **both** targets
   - `ProbeApp/*.swift` → ProbeApp only (delete Xcode's generated `ContentView.swift`)
   - `ProbeKeyboard/*.swift` → ProbeKeyboard only (delete the generated `KeyboardViewController.swift`)
4. **App Group** on both targets: Signing & Capabilities → + → App Groups →
   `group.<your-bundle-prefix>.keylang.probe`. If Xcode refuses on a Personal Team, skip it and
   continue; the harness handles it.
5. **Info.plist, ProbeApp** — both become mandatory under the iOS 27 SDK, both are free now:
   - `UIApplicationSceneManifest` (Xcode's SwiftUI template already has this)
   - `UILaunchScreen` = empty dictionary
   - `ProbeAppGroup` = your group string (so `ProbeLog` can find it without hardcoding)
6. **Info.plist, ProbeKeyboard**: same `ProbeAppGroup` key. Under `NSExtension` →
   `NSExtensionAttributes`, leave `RequestsOpenAccess` = **NO** for now. Task 6 flips it.
7. Build to the phone. Settings → General → Keyboard → Keyboards → Add New Keyboard → ProbeKeyboard.

## Running the probes, in order

**Order matters. P1 is a gate.**

### P1 — the gate (do this first, alone)
1. In ProbeApp: **Prepare en → es**, approve the download, wait.
2. **Check availability** → expect `installed`.
3. Open Notes, switch to ProbeKeyboard, tap **P1 Translate en→es**.
4. Back in ProbeApp: **Refresh**.

| What you see | What it means |
|---|---|
| `translation.en_es.result \| Llegaré sobre las ocho.` | **Architecture holds.** Continue to P2 |
| `TranslationError.notInstalled` | Pack did not cross the process boundary. Re-check `.installed` in the app first; if it persists, that is a major finding |
| Sandbox / XPC / crash on construct | **STOP.** The keyboard cannot translate. Do not run P2 onward — re-plan the roadmap. The product becomes the Share Sheet app |

Write the outcome into `docs/research/10-iphone-13-constraints.md` §2.5 under a
`## Device-verified` heading **before doing anything else**.

### P2 — memory (five runs, plus the mmap run)
Tap **P2 Memory: allocate until killed** in each of these, and read the last logged footprint
afterwards. The keyboard will vanish mid-run; that is the point.

1. inside Messages
2. inside WhatsApp
3. inside Safari with ~20 tabs
4. straight after a reboot
5. after ~2 hours of ordinary use

**The lowest of the five is your real ceiling. The spread between them is the system-pressure
effect, and on a 4 GB device that is the number that actually governs the design.**

Then tap **P2b mmap 20 MB** once. If the footprint barely moves, Phase 05's bundled-data budget
is real. If it moves by 20 MB, Phase 05 needs redesigning.

### P3 — Italian
Tap **P3 it→es availability**. `.unsupported` means Italian would need chaining two sessions
through English, which is the case for dropping it from V1.

### P4 — the battery
Tap **P4 Cheap probes battery** in Messages, then repeat in WhatsApp, Safari, Gmail and a
WKWebView so `proxy.context` is captured per host. Then flip `RequestsOpenAccess` to YES,
reinstall, enable **Allow Full Access**, and tap **P4b Speech**.

### P5 — glass
Tap **P5 Liquid Glass frame cost**. Compare `plain` against `blur` against the 16.7 ms budget.

## Finishing

```bash
# export probe-log.txt from ProbeApp, then:
bash Probe/check-probes.sh ~/Downloads/probe-log.txt
```

Exits non-zero and names anything that never ran. Then append findings to the research reports
under `## Device-verified YYYY-MM-DD — iPhone 13`, **without rewriting the original UNVERIFIED
text** — the delta between what was inferred and what was measured is the valuable part.

## One thing to watch that the plan did not anticipate

You are on **iOS 27 beta**, which makes the optional ANE probe mandatory. iOS 27 restricts
background Neural Engine access behind a new entitlement, and the sentence introducing it is
**not qualified by device class**. Apple's `.lowLatency` translation models plausibly use the ANE.

So if P1 fails, or if translation from the keyboard is much slower than from the host app,
**suspect the ANE background restriction before concluding that `TranslationSession` is
extension-hostile**. Compare the same translation called from ProbeApp in the foreground against
the keyboard, and log both. That comparison is the diagnostic.

## Amendment: your stack is entirely on beta

macOS 27 beta, Xcode 27 beta, iOS 27 beta. Two consequences.

### You get MetricKit's extension memory diagnostics, which is a real win

Building against the iOS 27 SDK unlocks `MemoryExceptionDiagnostic`, delivered "when your app or
**app extension** is terminated for exceeding its memory limit". Before iOS 27 a jetsam kill
produced no crash dialog and no crash log — the whole reason blocker B3 was so unpleasant. Now
Apple reports the peak memory directly.

`ProbeApp` subscribes on launch. **Payloads arrive asynchronously, usually within 24 hours.** So:
run the five P2 passes, then come back the next day and tap Refresh. Compare
`metrickit.peak_memory_mb` against the `jetsam.last_footprint_mb` you inferred from each run.
Agreement validates the instrument; disagreement is worth knowing before Phase 03 depends on the
number.

### Every finding is CONFIRMED *on a beta stack*, not CONFIRMED

Record the exact build numbers with your findings — Settings → General → About → Version for the
phone, and Xcode → About for the toolchain.

This matters more than it sounds. Research 08 established that **Apple changes keyboard-extension
behaviour in point releases with no release-note announcement**: the host-app bundle ID started
returning `nil` in iOS 26.4, took a vendor four months to work around, and the workaround was
deleting the feature. A beta is a moving target of the same kind.

**Re-run P1 and P2 at iOS 27 GM** before treating any of this as settled. Everything else can
stand on the beta numbers.
