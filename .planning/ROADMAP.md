# Roadmap: keylang

Phases run in dependency order, not calendar order. Two tracks share one engine: **A** is the
keyboard, **B** is the study surface, **C** is shared. Each phase is a separate
`ton-plan-phase` invocation; no task detail lives in this file.

01. **[C] Ground truth** - Resolve every research UNVERIFIED that gates a design decision,
    before any product code exists. Vendor OpenKeyboardKit and prove it builds under Xcode 26.
    Ship a throwaway on-device probe harness that measures: `phys_footprint` before and after
    each framework load; `SystemLanguageModel.default.availability` and whether a keyboard
    extension is rate-limited as "background"; `TranslationSession(installedSource:target:)`
    inside an extension target; `LanguageAvailability.status(from:.italian,to:.spanish)`;
    `NLTagger.availableTagSchemes` for en/es/it; `UITextChecker.availableLanguages`;
    `AVSpeechSynthesizer` with Full Access on and off; and `documentContextBeforeInput`
    behaviour in Messages, WhatsApp, Safari, Gmail and a WKWebView. Settle the Apple Developer
    Program question. Every answer is written back into `docs/research/` as CONFIRMED.

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

05. **[C] Learning core** - The shared engine, extracted from what 02 proved. Item keying
    (LEM / CELL / PARA / CONS / MWE with split credit), FSRS-6 dual-trace memory model,
    efficacy-weighted exposures writing only to the recognition trace, cognate-distance cold
    start priors, the bundled Spanish surface-to-lemma table and frequency data, and the
    append-only event log. `mastery` is derived, never stored.
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
