# LinguaKeyCore

The part of the product that has to be right: the memory model, the linguistic
tables, and the decision about what to teach in a given sentence.

Pure Foundation. No UIKit, no Translation, no SwiftUI. That is deliberate, and
it is what lets `swift test` run the whole thing on a Mac with no device, no
provisioning profile and no 7-day expiry.

## Layout

| Path | What it is |
| --- | --- |
| `Memory/FSRS.swift` | FSRS-6, 21 parameters, power-law forgetting |
| `Memory/Trace.swift` | Dual-trace items (recognition, production) and the suppression rule |
| `Data/Tables.swift` | `mmap`'d reader over the morphology and lexicon builds |
| `Teaching/Interference.swift` | The curated false-friend list |
| `Teaching/FocusSelector.swift` | What to teach in one sentence, or nothing |

## How it is verified

There was no Swift toolchain available when this was written, so the model was
designed and property-tested in Python first, under `tools/engine/`. That
reference is the authority, and two mechanisms stop the two implementations
drifting apart.

**Golden vectors.** `python3 tools/engine/golden.py` emits 336 scalars and 8
full scenario replays to `build/golden/fsrs-golden.json`.
`GoldenVectorTests` replays every one of them through the Swift and compares
stability, difficulty, reps, lapses, exposures, effective reps, the
last-graded-failed flag and retrievability at each step. A diff in that JSON is
a deliberate model change and needs a line in `.planning/STATE.md`; it is never
noise.

**Behaviour tests.** `FocusTests` ports the behaviours from
`tools/engine/test_focus.py` and runs them against the same 3.7 MB of built
tables. These are not numeric replays on purpose: freezing selector output into
vectors would freeze the data build too, so rebuilding the tables would then
look like a regression in the selector.

Run the reference side with `./check.sh` at the repository root, which runs the
morphology check, the lexicon check, 34 memory-model properties, 26 focus
behaviours, and asserts the golden vectors are current.

## Data

The package ships **no** resources. The tables are committed once at the
repository root and staged into a single directory for the app:

```sh
./tools/stage-data.sh                 # -> build/LinguaKeyData
```

```swift
let tables = try Tables(root: dataRoot)
let interference = try Interference(root: dataRoot)
let selector = FocusSelector(tables: tables, interference: interference)

for candidate in selector.select(sentence: text, state: state, now: Date().timeIntervalSince1970) {
    print(candidate.surface, candidate.kind, candidate.reason)
}
```

Copying the tables in as SPM resources would put a second 3.9 MB of identical
binary under version control to serve a code path the product never takes: a
keyboard extension reads them from the App Group container, not from
`Bundle.module`. The tests reach the committed copies via `#filePath`.

## The memory budget

3.7 MB of morphology is affordable inside a keyboard extension only because it
is `mmap`'d. Clean file-backed pages are evictable and are not charged to
`phys_footprint` the way dirty anonymous pages are. The extension's ceiling is
somewhere around 25 to 40 MB and is enforced by **silent jetsam**, with no crash
log, so getting this wrong looks like the keyboard randomly disappearing rather
than like a bug.

Probe P2b in `Probe/` measures that accounting on the actual device. Until it
reports, the headroom is a reasoned expectation and not a fact. Nothing in this
package decodes a table into a dictionary, ever.
