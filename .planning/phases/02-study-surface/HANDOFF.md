# HANDOFF — Phase 02: Study surface

Everything buildable without hardware is built and committed. What is left is
T5 through T8 of `PLAN.md`, which are the first build, the first run, and the
answers to gray areas G1 and G2. This is the runbook for the machine that can do
that: a MacBook Pro M4 Pro on Xcode 27 beta, and the iPhone 13 on iOS 27 beta.

## Before anything else

```sh
./setup.sh
```

Builds the tables (downloads roughly 200 MB of corpora the first time), stages
them into `build/LinguaKeyData`, creates `LinguaKeyApp/Local.xcconfig`, and runs
every check. Then edit `Local.xcconfig`:

```
DEVELOPMENT_TEAM = <your ten-character Team ID>
BUNDLE_PREFIX    = <a reverse-DNS prefix you control>
```

Signing fails until both are set, and the failure reads as a project problem
rather than a config one, which is why this is step one and not step five.

## T5 — first build

```sh
open LinguaKey.xcodeproj
xcodebuild -scheme LinguaKey -destination generic/platform=iOS build
```

`tools/check_project.py` makes 71 structural claims about the project file and
all of them pass, but the project was hand-written on a machine with no Xcode.
**Assume the first open needs a fix.** The likely candidates, in the order they
are worth checking:

1. **The local package does not resolve.** `LinguaKeyApp` is referenced as an
   `XCLocalSwiftPackageReference` and it in turn depends on `../LinguaKeyCore`.
   If Xcode complains, File > Packages > Reset Package Caches first.
2. **`build/LinguaKeyData` shows red.** It is gitignored and produced by
   `tools/stage-data.sh`. Running `setup.sh` creates it. It must stay a **folder
   reference**, blue not yellow: a group flattens the tree and the two
   subdirectories then collide on `manifest.json`.
3. **Duplicate Info.plist.** The synchronized folder groups carry membership
   exceptions for `Info.plist` and the entitlements. If Xcode adds them back,
   remove them from target membership rather than deleting the exception.
4. **Swift 6 concurrency errors in the SwiftUI.** The isolation was reasoned
   about, not compiled. `AppModel.init` is deliberately `nonisolated` and
   `StudyView.start` and `StudyView.record` are deliberately `@MainActor`. If
   more annotations are needed, add them; do not reach for `@preconcurrency`.

Record what actually had to change in `SUMMARY.md`, because the same fixes will
be needed for the keyboard target in Phase 03.

## T6 — the host app on the device

1. Run to the iPhone 13. Trust the certificate under Settings > General >
   VPN & Device Management.
2. Setup should report the staged table size (about 3.9 MB) and a staging
   outcome of `staged`. If it says `missingFromBundle`, the folder reference is
   the problem.
3. Tap **Download the Spanish pack**. The system's own download sheet appears;
   there is no progress UI of our own on purpose.
4. Force-quit and relaunch. The pack status must survive, and Setup's
   "Loaded by" should say `snapshotUsed` rather than a rebuild.
5. Use the paste box on Today to study a sentence. `Quiero un vaso de agua`
   should teach `vaso` as a false friend, or teach nothing if the arm is C.
6. Export the log and confirm it is JSON lines, one object per line.

## T7 — the share extension

From Safari, Messages, Notes and Mail: select Spanish text, Share, LinguaKey.

For each host, record what arrived. The extension logs the item provider's
registered type identifiers into `sourceApp` on every event, and reading them
back out of the exported log is **the answer to gray area G2**. Write it into
`docs/research/` under a `## Device-verified` heading, the same discipline the
Phase 01 probes use.

Two failures to expect and tell apart:

- **"The language tables are not staged yet."** The extension reads the tables
  from the App Group, and the app puts them there. Open the app once first. If
  it persists after that, the two entitlements have drifted apart; only the app
  can see its own container and the extension is looking at a different one.
- **The extension does not appear in the share sheet at all.** The activation
  rule, or the appex not being embedded. `check_project.py` covers the embed;
  it cannot cover the rule.

Then confirm the round trip: study something from Safari, open the app, and the
event count on Today must have gone up. That is the two-process store working,
and it is the single most important thing in this phase.

## T8 — translation, and gray area G1

**G1 is answered by running it.** Does `TranslationSession(installedSource:target:)`
work inside a share extension on this iOS 27 beta? Expected yes, and D2 makes a
no survivable rather than fatal.

Three states, all of which must reach a usable screen:

| State | How to get there | Must show |
| --- | --- | --- |
| pack installed | after T6 step 3 | the sentence translation |
| pack removed | Settings > General > Language & Region > Translation Languages | one line saying to open LinguaKey, and the word teaching still working |
| Simulator | run the app in any iOS 26 simulator | the same one line, never a crash |

The Simulator run is the one that proves D2, because the Simulator cannot
translate at all. If it shows an error screen rather than a study screen, the
"useful with no pack" claim is false and that is a bug, not an environment
limitation.

## T9 — after the device work

Extend `check.sh` with anything the device taught you that a machine can check.
Update `docs/research/` with the G1 and G2 answers as CONFIRMED, add a log entry
to `.planning/STATE.md`, and write `SUMMARY.md` for this phase.

## What is deliberately not done

- **Peninsular correctness is unchecked by machine.** No es-ES verification step
  exists in the data build. It is a review item and it will drift.
- **The event log has no size bound.** At one person's volume this is fine for
  the experiment, and rotation would only add a way to lose data.
- **The device clock is the only clock.** A manual clock change corrupts
  intervals and nothing detects it.
- **Phase 01's probes are still unrun.** P1 gates the keyboard, not this app.
  Nothing here waits on it, but Phase 03 does.
