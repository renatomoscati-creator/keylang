# keylang

## Purpose
Build a system-wide iOS keyboard that teaches the author peninsular Spanish through the
messages they were already going to type, and build it so that the question "is this
actually teaching me anything?" has a real answer rather than a vibe. Two surfaces, one
engine: a Share Sheet study app that tests the pedagogy cheaply, and a keyboard that
delivers it once the pedagogy is proven.

## Why now
Seven parallel research passes on 2026-08-18 (see `docs/research/`, synthesis in
`docs/STRESS-TEST.md`) moved two things in opposite directions, and the gap between them
is the reason to start now and the reason to start differently than the PRD says.

**The technical risk collapsed.** Apple's `TranslationSession(installedSource:target:)`
(iOS 26.0) is a headless, on-device translator, and Foundation Models runs in a keyboard
extension out-of-process, with Apple DTS confirming the memory increase is "very minimal".
Two independent confirmations that this works inside a keyboard extension: a shipping
project runs `LanguageModelSession` with `RequestsOpenAccess: false`, and KeyboardKit's own
shipped Mach-O links `FoundationModels`. PRD section 8 has its local and remote columns
backwards.

**That finding is now half applicable, and the other half resolved into something better.**
The target device was fixed to an iPhone 13, which is not Apple Intelligence capable, so
Foundation Models and PCC are both permanently off the table here. The *translation* half of
the inversion holds intact. The *teaching* half becomes **bundled deterministic data authored
at build time by a frontier model on a Mac**, rather than a model prompted at runtime.

That is not a downgrade, and three of the five teaching capabilities are genuinely better for
it. Focus selection is a ranking problem over one sentence and a scoring function is auditable
where an LLM's choice is not, which is what makes success criteria (b), (c) and (d) answerable
at all. Recall prompts want multiple-choice distractors, which the gloss meta-analysis found to
be the most effective format measured, and those are precomputable and reproducible where
runtime generation would make the A/B randomisation uninterpretable. Grammar explanation is a
deck of roughly 200 hand-authored cards keyed on construction id, which beats a small model at
one-line A1-B1 explanations and can simply say nothing on the long tail rather than guessing.
Glossing needs word-sense disambiguation, mitigated by translating the focus word alone in the
same batch and checking whether it appears in the sentence translation. Only general
grammatical error correction genuinely needs a model, and that is what the escalation rung is
for. The zero-network story survives in full.

**The product risk did not move at all.** The red team and the learning-science pass reached
the same conclusion independently: the PRD's terminal action, inserting a machine
translation into a live message, is something the author will almost never want (their
messages go to English speakers) and it removes the retrieval that does the teaching. In the
gloss meta-analysis (359 effect sizes, N=3,802) in-text glosses were the least effective
format measured and multiple-choice the most; under the Involvement Load Hypothesis an
unrequested translation banner scores need=0, search=0, evaluation=0. A persistent strip
above the keys whose content is not required to send the message is structurally an ad
banner, and banner blindness is a design certainty rather than a risk.

The closest prior art agrees and sharpens it: WaitChatter (CHI 2015) taught ~57 words in two
weeks inside a chat client, but with micro-quizzes rather than translations, fired after
sending rather than mid-composition. Its follow-up found chat was the lowest-engagement
context of all the waiting moments tested.

So: the expensive part (a keyboard that feels native) is unavoidable and is the bulk of the
work. The uncertain part (does any of this teach?) is cheap to test and does not need a
keyboard. Doing them in the wrong order is how this project dies at month nine.

## Chosen approach
Two tracks against one shared engine, run in parallel.

**Track B, the study surface**, ships first and is small: a SwiftUI app plus a Share Sheet
extension that works on selected text in any app. It carries the full learning engine, the
event log, and item-level A/B/C randomisation from day one. It is the live pedagogy
experiment, and it exercises the prompt contract, the item model and the memory model with
none of the keyboard-extension cost: no Full Access, no App Group, no jetsam ceiling, no
emoji problem, no accessibility surface.

**Track A, the keyboard**, is built in parallel because its cost is dominated by mechanics
(key geometry, callouts, delete acceleration, autocorrect, emoji, accessibility) that are
required under any product shape and are independent of the pedagogy question. It gets the
learning UI only after Track B has produced evidence about what that UI should be.

Three corrections from the research are load-bearing and apply to both tracks:
- The learning bar fires on **send**, not on a mid-sentence debounce pause. A sentence-final
  send is a coarse interruption breakpoint; a typing pause is a fine one, where the user
  must also reconstruct their position. Best evidence-to-effort ratio in the entire body of
  research.
- The default terminal action is a **retrieval**, not an insert. Insert survives as an escape
  hatch, logged with zero learning credit and excluded from every Spanish-production metric,
  and it queues that item for recall within 24 to 72 hours. The crutch becomes a scheduling
  signal.
- Mode D (active recall) and Mode E (Spanish correction) are P0. Mode C (code-switching) is a
  flagged experiment: it is the most novel-feeling and least-supported mode in the PRD, and
  for a learner whose documented failure mode is over-transfer between near-identical
  languages, rehearsing a blended Italian-Spanish-English register is a plausible way to
  manufacture fossilisation.

The memory model is FSRS-6 used as an estimator, not a scheduler (the scheduler cannot choose
when the author texts someone), with separate recognition and production traces, an efficacy
weight attenuating ungraded exposures, and cold-start difficulty priors driven by cognate
distance. `mastery` becomes a derived display value and never a decision variable.

## Constraints
- **Target device: iPhone 13, and only iPhone 13.** A15 Bionic, 4 GB RAM, 60 Hz display.
  This is a hard constraint with one large consequence: **the iPhone 13 is not Apple
  Intelligence capable** (that needs A17 Pro or better), so the **Foundation Models framework
  is permanently unavailable**. `SystemLanguageModel.default.availability` returns
  `.unavailable(.deviceNotEligible)`, which is the one `UnavailableReason` case that is
  hardware and never resolves. **Private Cloud Compute does not rescue it**: Apple states in
  three places that PCC is only available on devices that support Apple Intelligence, so the
  server model is gated on the client being eligible hardware. A closed door, not a narrow one.
- **Translation survives fully, and this is confirmed rather than hoped.** Apple's own API
  reference says `.lowLatency` "is the default strategy for devices without Apple Intelligence",
  headless `TranslationSession(installedSource:target:)` is iOS 26.0 with no eligibility
  precondition, and downloaded language packs are a **system-wide store shared with all apps on
  the device**, so the host app downloads and the keyboard consumes. Apple documents the quality
  gap versus `.highFidelity` only as "not as fluent" and **publishes no number for any pair**;
  the expected shape is flatter and more literal rather than wrong, which for a learner is close
  to harmless. `preferredStrategy` (iOS 26.4) is dead code here: whatever you pass, you get
  `.lowLatency`. Do not raise the floor for it.
- **Two upsides:** 60 Hz relaxes the frame budget to 16.7 ms, and a single known device makes
  every measurement in phase 01 exact rather than a range.
- **Target: iOS 26.0, built with the iOS 26 SDK (Xcode 26).** iOS 26 is the floor because
  headless `TranslationSession` and Foundation Models both require it, and because it gives
  one Liquid Glass visual target instead of maintaining pre-26 and 26+ appearances. Do not
  adopt the iOS 27 SDK before ~27.1: iOS 27 exposes no new keyboard-extension API at all,
  verified four independent ways (WWDC26 session catalogue, UIKit updates page, full Beta 6
  release-notes scan, symbol-level `introducedAt` diff).
- **Spanish variety is peninsular (es-ES), decided.** It is a required field in the item model
  and the prompt contract from the first line of code, not a later setting.
- **Keyboard foundation: vendor OpenKeyboardKit (MIT) into the repo as owned source.**
  KeyboardKit went fully closed-source on 2025-08-31 and is distributed as a binary you
  cannot recompile; its autocomplete engine is paywalled and EN+IT+ES lands on a ~$1,500/yr
  tier. Its `hostApplicationBundleId` broke in the iOS 26.4 point release and took ~4 months
  to resolve, with the resolution being deletion of the feature. Adopting an un-recompilable
  binary four weeks before a major OS release is not a risk worth taking.
- **Memory: design to 25 MB resident, alarm at 20 MB, never reach 35 MB.** Lowered from
  40/30 because this is a 4 GB device at the bottom of the supported RAM class, and because on
  4 GB **jetsam also fires on system-wide pressure** — the keyboard can be killed well below its
  own limit simply because the host app grew, which makes the failure intermittent and
  unreproducible. The ceiling is undocumented by Apple and enforced with no crash log and no
  dialog; the user is silently bounced to their previous keyboard mid-sentence. Instrument with
  `task_vm_info.phys_footprint`, **not** `os_proc_available_memory()`, which Apple documents as
  returning `0` when the calling process is not an app. All bundled linguistic data lives in
  `mmap`'d read-only binary blobs with binary search or a perfect hash, never `Data(contentsOf:)`
  and never a decoded in-memory dictionary. An embedded LLM is arithmetically impossible.
- **Never trust the Simulator for anything provisioning-, memory- or Full-Access-related.**
  App Group writes succeed in the Simulator and fail on device. Translation does not run in
  the Simulator. Memory limits are not enforced there.
- **`documentContextBeforeInput` is a hint, not the truth.** It is paragraph-truncated,
  host-dependent, returns nil in Gmail after a paste, and returns only the last ~2 sentences
  of pasted text in WhatsApp. Maintain a shadow buffer of what this keyboard inserted, keyed
  on `documentIdentifier`, and use the proxy to reconcile.
- **Nothing on the keypress path** may touch the network, a database, or synchronous
  inference. Every `UITextDocumentProxy` access is a cross-process round trip. The frame budget
  is **16.7 ms** (60 Hz). Per-frame CPU is not the constraint on an A15; **GPU is** — the
  non-Pro iPhone 13 has a 4-core GPU, Liquid Glass is a per-frame backdrop blur, and iOS 26 is
  widely reported to lag on this device with keyboard lag named specifically. Treat Reduce
  Transparency and Reduce Motion as first-class supported appearances, not accessibility
  afterthoughts.
- **No raw typed text is persisted anywhere**, including local logs, except in an explicitly
  opt-in and independently clearable history store. The event log records item ids and an app
  *class*, never content.
- **Every phase leaves one runnable self-check** that fails if that phase's logic breaks. No
  framework, smallest thing that works.
- **Assertions over assumptions.** Every UNVERIFIED item in `docs/research/` that gates a
  design decision is resolved by measurement on a real device before code depends on it.
- **No em-dashes anywhere in content this project writes.**

## Success criteria
a. The author uses the keyboard as their default for ordinary daily messaging without
   feeling that the learning layer interferes with typing, measured as median compose time
   with the bar shown versus suppressed, within 10 percent.
b. The question "does passive exposure teach this user anything?" is answered with data, not
   opinion: the fitted efficacy weight for ungraded exposure is either distinguishable from
   zero or it is not, and the answer is visible in the repo.
c. Suppression accuracy is at or above 85 percent: of items the model went quiet on, fewer
   than 15 percent are later failed on a recall prompt.
d. The memory model beats a frequency-plus-recency baseline on log loss, or it is deleted.
e. Self-generated Spanish (typed, not inserted) rises while assistance requests per 100
   Spanish words falls. If both rise, this is a translator and not a teacher, and the project
   says so out loud.
f. The keyboard is fully usable with Full Access off and with no network, per App Store
   guideline 4.4.1, whether or not it is ever submitted.

## Scope boundaries
IN: iPhone only. Peninsular Spanish only. English and Italian as source languages. On-device
translation and teaching. A Share Sheet study surface. A keyboard extension. A local learning
engine with an append-only event log. An honest evaluation protocol.

OUT for now: Android, iPad layouts, swipe typing, App Store submission, other language
pairs, accounts or sync, and any device other than the iPhone 13. Mode C code-switching is out
of V1 and enters only as a flagged experiment with a stated success criterion.

RESOLVED, replacing the earlier "under review" note: **the V1 teaching layer is bundled
deterministic data, and no remote call ships in V1.** A remote escalation rung is V1.1, and it
is admitted only as explicit-tap-only, one sentence at a time, never on the keypress path, never
carrying `UILexicon` contact names or the learning profile, and fully optional with the product
complete without it. At single-user volume it is cents per month, so the rate limiting and abuse
surface that made the original design frightening do not apply; the consent gate and the spend
cap still do. The teaching layer is written against a single `TeachingEngine` protocol so that
if the target device ever changes, the implementation swaps and nothing above it does.

OPEN PREREQUISITE: whether the Apple Developer Program membership is purchased. This decides
whether App Groups and Keychain sharing exist, and therefore whether the host app can read
the keyboard's learning state at all. Phase 01 resolves it; the roadmap is sequenced so that
App-Group-dependent work lands late and a keyboard-local store is the default design.
