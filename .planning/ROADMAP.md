# Roadmap: keylang

Phases run in dependency order, not calendar order. Two tracks share one engine: **A** is the
keyboard, **B** is the study surface, **C** is shared. Each phase is a separate
`ton-plan-phase` invocation; no task detail lives in this file.

01. **[C] Ground truth** - Resolve every research UNVERIFIED that gates a design decision,
    before any product code exists. Vendor OpenKeyboardKit and prove it builds under Xcode 26.
    Ship a throwaway on-device probe harness on the actual iPhone 13. Three probes decide the
    architecture and run first: (i) **`TranslationSession(installedSource:target:)` inside a
    keyboard extension** with `RequestsOpenAccess: false` - if this throws a sandbox or XPC
    error the keyboard cannot translate at all and the product becomes the Share Sheet app;
    (ii) the **five-run destructive memory measurement** (allocate 1 MB dirty pages until
    jetsam, inside Messages, WhatsApp, Safari with 20 tabs, after reboot, and after two hours
    of use - the lowest of the five is the real ceiling and the spread is the system-pressure
    effect); (iii) **`LanguageAvailability.status(from:.italian,to:.spanish)`**, whose three
    possible answers imply three different product designs, one of which is dropping Italian
    from V1. Then the cheaper probes: whether `os_proc_available_memory()` returns a real
    number or `0` in an extension; `NLTagger.availableTagSchemes` for en/es/it;
    `UITextChecker.availableLanguages`; `AVSpeechSynthesizer` with Full Access on and off;
    `documentContextBeforeInput` behaviour in Messages, WhatsApp, Safari, Gmail and a
    WKWebView; and a Liquid Glass cost measurement on a keyboard-sized view. Add
    `UIApplicationSceneManifest` and a launch-screen key to the containing app now. Every
    answer is written back into `docs/research/` as CONFIRMED.

02. **[B] Study surface** - The SwiftUI app plus Share Sheet extension. On-device translation
    and teaching over selected text in any app, peninsular Spanish, with the event log and
    item-level A/B/C arm randomisation wired in from the first commit. Read-only teaching, no
    insertion. This is the live pedagogy experiment and it starts collecting data immediately.
    Depends on: 01

03. **[A] Keyboard shell** - A keyboard that is worth using with no learning layer at all.
    Native key geometry per device and orientation, press callouts, long-press secondary
    callouts carrying the EN/IT/ES accent union, shift and caps-lock timing, delete-repeat
    acceleration, space-drag cursor, double-space period, autocapitalisation from
    `UITextInputTraits`, `keyboardType` and `returnKeyType` layouts and labels, globe key,
    VoiceOver with `.isKeyboardKey`, Dynamic Type, landscape, dark mode, height constraint,
    and the memory instrumentation from 01 wired to a persistent local log.
    Depends on: 01

04. **[A] Typing quality** - The phase the PRD omits entirely. Suggestions and autocorrect
    from `UITextChecker` plus a bundled SymSpell frequency dictionary plus `UILexicon`,
    ranked by keyboard-geometry typo priors; and an emoji keyboard with recents and search,
    built against the measured ~10 MB per page cost. Acceptance is subjective and binding:
    the author uses it as their default keyboard for a week and does not want to switch back.
    Depends on: 03

05. **[C] Learning core and teaching data** - The shared engine, extracted from what 02
    proved, plus the build-time authoring pipeline that replaces the model this device cannot
    run. Engine: item keying (LEM / CELL / PARA / CONS / MWE with split credit), FSRS-6
    dual-trace memory model, efficacy-weighted exposures writing only to the recognition trace,
    cognate-distance cold-start priors, and the append-only event log. `mastery` is derived,
    never stored. Data, authored offline by a frontier model on a Mac and reviewed by a human
    before shipping, then frozen into `mmap`'d binary tables: a ~380k-form Spanish morphology
    table (surface -> lemma, POS, tense, mood, person, number), Wiktionary-derived glosses
    sense-checked by translator alignment, ~200 grammar cards keyed on construction id, a noun
    gender table, an Italian-interference lexicon, and precomputed multiple-choice distractors.
    All behind one `TeachingEngine` protocol so the implementation can be swapped if the target
    device ever changes.
    Depends on: 02

06. **[A] Learning bar** - The teaching layer inside the keyboard. Fires on send, not on
    pause. One vocabulary concept plus at most one grammar note per sentence. Retrieval-first
    presentation, insert demoted to an escape hatch with zero learning credit and a queued
    recall. Hard suppression in secure, numeric, email and URL fields. Reserved height so the
    bar never changes keyboard geometry. Undo for any destructive edit.
    Depends on: 04, 05

07. **[A+B] Recall and correction** - Mode D and Mode E, the two modes the evidence supports.
    Recall answered by what the user types next in the field, matched accent-insensitively
    within a time window. Spanish correction gated behind three-way EN/IT/ES detection with a
    confidence floor, so correct Spanish is never rewritten. Italian-to-Spanish interference
    traps as high-precision interrupts and as Mode D distractors.
    Depends on: 06

08. **[C] Evaluation and go/no-go** - Read out what 02 through 07 collected. Fit the exposure
    efficacy weight from the event log and report whether it is distinguishable from zero.
    Report suppression accuracy, model calibration against a frequency-plus-recency baseline,
    the bar-blindness index, and self-generated versus inserted Spanish. Decide in writing
    whether the teaching layer earns its place, gets rebuilt, or gets cut.
    Depends on: 05, 07
