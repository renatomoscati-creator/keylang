# keylang

A Spanish learning layer for an iPhone 13, built around the observation that
teaching happens best in the sentences you were writing anyway.

Two tracks share one engine: a **study surface** that reads text shared from any
app, and a **keyboard** that teaches while you type. The study surface is built.
The keyboard is gated on a measurement that needs the physical device.

## What is here

| Path | What it is |
| --- | --- |
| `docs/PRD.md` | The original product brief, committed unmodified |
| `docs/research/` | Ten verbatim research reports, every claim tagged CONFIRMED, LIKELY or UNVERIFIED |
| `docs/STRESS-TEST.md` | The synthesis, including the four blockers the brief does not mention |
| `.planning/` | Phases, locked decisions and the running log |
| `tools/build-data/` | Builds the morphology and lexicon tables from open corpora |
| `tools/engine/` | The reference implementation, in Python, where the model was designed |
| `LinguaKeyCore/` | The Swift engine: memory model, table reader, focus selection |
| `LinguaKeyApp/` | The study surface: store, experiment, shared UI, app, share extension |
| `Probe/` | The throwaway on-device harness for the phase 01 measurements |
| `LinguaKey.xcodeproj` | The app and the share extension |

## Getting it onto a phone

```sh
./setup.sh          # builds the tables, stages them, creates Local.xcconfig
open LinguaKey.xcodeproj
```

Then edit `LinguaKeyApp/Local.xcconfig` with your Team ID, pick the `LinguaKey`
scheme and your iPhone, and Run.

Requires Xcode 27 beta if your phone is on an iOS 27 beta: Xcode cannot install
onto a device running an OS newer than its SDK. Deployment target is iOS 26.0.

### Two things about a free personal team

**The build expires after 7 days** and dies mid-sentence with no warning.
Reinstall from Xcode before then.

**Do not delete the app to reinstall it.** Deleting it destroys the App Group
container and every event in it. The event log is the only thing in this project
worth more than the build that reads it. Setup has an export button; use it if
you are unsure.

## Verifying it

```sh
./check.sh
```

One command, 187 assertions, no Xcode and no device:

| Suite | What it proves |
| --- | --- |
| morphology table | 18 assertions over 130,196 surfaces |
| lexicon tables | 21 assertions over 4,655 lemmas |
| memory model | 34 properties, including that 100 exposures alone never suppress an item |
| focus selection | 26 behaviours against the real tables |
| arm assignment | 12 properties, including the published FNV-1a vectors |
| swift invariants | 22 claims no compiler here can make |
| xcode project | 71 structural checks on the hand-written project file |
| golden vectors | 4 files, regenerated and compared byte for byte |

The Swift itself is verified by golden vectors rather than by having been run,
because no Swift toolchain is reachable from the machine it was written on. The
model was designed and property-tested in Python first, and the Swift asserts
336 scalars, 8 scenario replays, 40 arm assignments, and a 45-event log folding
to 8 items against that reference. See `LinguaKeyCore/README.md` for why.

The invariants are the checks that catch things which look like working code:
the `Translation` boundary holding in both directions, `mastery` never becoming a
stored property, the arm hash never becoming `Hasher` (which is seeded per
process and would silently reassign arms on every launch), one App Group
identifier across four files, and every `Channel` and `Grade` value agreeing
between the Swift and the reference. Each was proven by introducing the violation
it catches.

## The shape of the thing

The engine is deliberately boring and entirely offline. 3.9 MB of `mmap`'d
tables, binary-searched in place, nothing decoded into a dictionary ever, because
a keyboard extension's memory ceiling is somewhere around 25 to 40 MB and is
enforced by silent jetsam with no crash log.

What it teaches is chosen by a scoring function, not a threshold ladder and not a
model:

```
value = 0.45 gain + 0.25 need + 0.20 novelty + 0.10 readiness + trap - intrusion
```

At most one vocabulary note and one grammar note per sentence, and below 0.85 it
says nothing at all. A bar that is quiet most of the time is what buys attention
when it does speak.

Every item is assigned to one of three arms, deterministically and for life:
**A** shows the gloss, **B** asks first, **C** shows nothing and logs the
exposure. C will feel broken. It is a third of the data and it is the only thing
that makes A and B mean anything.

## Data and licences

The tables are built from UniMorph `spa`, doozan's `spanish_data` and hermitdave's
FrequencyWords, all CC BY-SA. `tools/build-data/README.md` has the details.
`data/interference.json` is 48 hand-curated false friends and is the authority on
what a false friend is. The orthographic cognate score is not, and must never be
used as one: 90% of common Spanish lemmas look Italian.
