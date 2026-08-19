# Stress Test — LinguaKey PRD v0.1

**Date:** 2026-08-18 · **Method:** seven parallel research agents against primary sources
**Full reports:** [`docs/research/`](research/) — every claim tagged CONFIRMED / LIKELY / UNVERIFIED
**Status of the PRD:** not superseded. This document records what survived and what did not.

---

## Verdict in one paragraph

The PRD is a genuinely good technical brief wrapped around an unvalidated product mechanic. Its platform research (§4), its refusal to ship a provider key in the client (§7), its abstraction-layer instinct (§5), its build-priority ordering (§30) and its anti-branding stance (§25) are all correct and better than most keyboard specs. But three things break it: **four Phase-0 blockers it does not mention**, **an architecture that is backwards for 2026**, and **a core interaction — insert a machine translation into a live message — that neither the UX walkthrough nor the learning-science literature supports.**

The most important asymmetry to internalise: **the research lowered the technical risk a great deal and did not move the product risk at all.**

---

## 1. Blockers — resolve before any code is written

Ordered by how early they bite.

### B1. The paid membership is effectively mandatory, but the reason is the 7-day profile

> **Revised 2026-08-19.** This blocker originally said App Groups and Keychain Sharing require
> the paid program. **That was wrong**, and research 09 corrects it. Apple's own capability
> matrix lists **App groups: yes** and **Keychain sharing: yes** in the free "Apple Developer"
> column, which Apple defines as "No cost is associated with this agreement." Corroborated at
> source level: AltStore's production signing path creates App Group identifiers through the
> portal API for free teams with no gate, and AltStore itself ships an app plus an app extension
> sharing an App Group, installed by millions of users on free Apple IDs. The Apple DTS quote
> research 04 relied on is accurate but was over-read: it says the portal must *mint* the group,
> not that it refuses free teams. What is actually gated is **Xcode's automatic-signing UI**, not
> the entitlement (LIKELY, not confirmed).
>
> **So PRD §12 P0's shared App Group settings, all of §19, and §7's Keychain BYOK are NOT blocked
> by the free tier.** That part of the persistence design can be built and validated without
> paying.

**What actually blocks it is the 7-day provisioning-profile expiry**, re-confirmed on Apple's own pages on 2026-08-19: *"Provisioning profiles will expire 7 days from issuance, which may require you to rebuild and re-install your app to your device after expiration."* No sideloader can extend it — the expiry is enforced server-side at signing time, not by the client.

The failure mode is what decides it. When the profile expires the host app will not launch and iOS refuses to load the extension, **silently, mid-sentence, in whatever app you are typing in.** No warning, no grace period, no notification. Recovery needs a laptop or a working sideloader, which is not something you can do from the message you are currently trying to send. For a product whose success condition is "leave it enabled as the default keyboard for daily messaging," that is a defect, not friction.

Sideloaders (AltStore Classic, SideStore, both actively maintained and both shipping iOS 26.4 fixes in 2026) automate the weekly re-sign and reach ~0 minutes/week in steady state. But expect **2 to 4 multi-day outages per year** keyed to iOS point releases breaking the lockdown/pairing layer. LiveContainer, the usual answer to the 3-app limit, **cannot work at all** — its README states plainly that app extensions are unsupported, and a keyboard must register with SpringBoard.

**EU alternative distribution is not an escape hatch.** AltStore PAL is free for *users* but requires a paid account plus Apple notarization for *developers*. Web Distribution's gate loosened under the 2026-10-01 unified EU terms but still requires one of seven corporate or financial credentials (D&B rating, public listing, named-fund VC money, a $1M standby letter of credit, an audit, nonprofit status, or 1M annual installs) — an Italian sole individual meets none. The Enterprise Program needs 100+ employees. **The DMA opened distribution to third parties, not development to non-members.**

**Revised sequencing:** the $99 is not needed before the first line of code. It is needed **before the first dogfooding milestone** — before this becomes your actual keyboard. That is a few weeks of runway, not a hard gate on Phase 0. *(Research 09; corrects Research 04 §1.3-1.4)*

### B2. Writing to the App Group requires Full Access — §23 and §19 are mutually inconsistent

Apple, verbatim: *"This sandbox's default configuration disallows access to the network **and prevents writing to the containing app's shared group containers** (reading is permitted)."* The failure is silent, **works in the Simulator and fails on device**, and surfaces as `[User Defaults] Couldn't write values for keys (…)`.

So §23's "No Full Access → keyboard remains fully usable" and "Extension restart → reload settings and vocabulary state from shared persistent storage" cannot both be true. Without Full Access the keyboard types fine but **saves no progress at all**.

**Required decision before the persistence layer exists:** a dual store — extension-private store as the keyboard's source of truth, App Group as the sync channel when Full Access is on, host app drains the deltas. Retrofitting this is expensive. *(Research 01 §4, Research 04 §4.1)*

### B3. Memory ceiling ~30–60 MB, enforced by silent jetsam

Apple confirms a limit exists and "varies from model to model" but **publishes no number**. The failure mode is the problem: **no crash dialog, no crash log** — iOS just swaps the user back to their previous keyboard mid-sentence. You will not see this in Xcode.

Emoji is the single largest line item: KeyboardKit measured **~10 MB per emoji page**, with `LazyVGrid` failing to deallocate cells on scroll (their own HIGH-PRIO issue #757).

**Design to 40 MB with an alarm at 30 MB.** Instrument `phys_footprint` via `task_vm_info` on every `viewDidAppear`. An embedded LLM is arithmetically impossible — delete §12 P2's "on-device model experimentation" as a keyboard-side item. *(Research 01 §2)*

### B4. KeyboardKit is closed-source, binary-only, and the autocomplete engine is paywalled

Verified by cloning the repo and unzipping the shipped 10.8.0 XCFramework, not by reading marketing:

- The licence flipped to **Closed Source on 2025-08-31** (commit `6d5757ae`, buried in a commit titled "Update deployment targets"). Last MIT release was **9.9.0/9.9.1**. The README on `main` still says "free, open-source keyboard engine" — **it contradicts the LICENSE file in the same tree.**
- `Sources/` contains **0 files**. It is an SPM manifest pointing at a binary, gated at runtime by LicenseKit.
- The `ProFeature` enum, extracted from the binary's `.swiftinterface`, gates `autocomplete`, `remoteAutocomplete`, `locale(_)`, `inputSets`, `keyboardLayoutTypes`, `dictation`, `themes`, `emojiAddons`, and more. `StandardAutocompleteService.init` **throws** without a licence; the free default is `DisabledAutocompleteService`, which returns nothing.
- LinguaKey needs EN + IT + ES = 3 locales. Basic gives 1. **That lands on Silver, ~$150/mo / ~$1,500/yr, recurring, for a personal-use app with no revenue.**

**So PRD §12 P0's "basic English/Italian suggestions" is behind a paywall in the framework the PRD recommends for exactly that reason.** *(Research 02 §1)*

---

## 2. The architecture is backwards — this is the biggest finding

PRD §8 lists high-quality EN→ES and IT→ES translation, grammar-aware correction, explanation, phrasing, focus selection and recall generation as **Remote operations**, with Apple frameworks as an optional "may later be used."

**Reverse it. In 2026 that list has a credible on-device implementation, and the remote path is the fallback.**

| Capability | PRD says | Reality (2026) | Full Access? |
|---|---|---|---|
| EN→ES / IT→ES translation | Remote | **`TranslationSession(installedSource:target:)` — headless, on-device, iOS 26.0+.** Apple: *"All translations using the `TranslationSession` class are processed on the user's device"* | **No** |
| Focus word, lemma, meaning, one-line explanation | Remote | **Foundation Models `@Generable`** — §15's response schema maps 1:1 onto a Swift type, making "strict structured output, no markdown" a *type-system guarantee* rather than prompt-and-pray | **No** |
| Spanish correction (Mode E) | Remote | `UITextChecker(es)` first pass + Foundation Models | **No** |
| Active-recall generation | Remote | Foundation Models | **No** |
| Pronunciation audio | — | `AVSpeechSynthesizer` | **YES** |
| Writing learning state to the App Group | — | shared container | **YES** |

Two independent confirmations that Foundation Models actually runs in a keyboard extension:
1. `bogdanripa/llm-keyboard` ships a `LanguageModelSession` inside a keyboard extension whose Info.plist has **`RequestsOpenAccess: false`**.
2. KeyboardKit 10.8.0's shipped Mach-O **links `/System/Library/Frameworks/FoundationModels.framework`** and its public `.swiftinterface` imports it. A framework does not link into a keyboard-extension binary that cannot run there.

Apple DTS on the memory question: *"the on-device foundation model and the inference resources are managed centrally by the operating system and shared by all Apple Intelligence system features, so the increase to your app's memory usage will be **very minimal**."*

### What this changes

- **§21's onboarding copy is now wrong in the user's favour.** It should read: *translation and teaching never leave the device; Full Access is required for pronunciation audio and for saving your progress.* That is a far stronger privacy story and a much easier consent ask — and it plausibly supports a **"no data collected"** App Store nutrition label, which no other AI keyboard on the store can claim.
- **§7's entire API-key strategy becomes optional V2 infrastructure**, not V1 critical path. No proxy, no key, no rate limiter, no abuse surface, no per-user cost. Works on a plane.
- **§26 Phase 1 "Translation MVP" should be built on `TranslationSession`, not the remote API. It is less work, not more.**
- The remote LLM survives as a **quality-escalation rung**, reached only on explicit user action:
  `UITextChecker/UILexicon → Translation (on-device) → Foundation Models (on-device) → [opt-in] PCC or your API`
  Only the last rung touches the network, and only for one sentence — which satisfies §21's "smallest useful unit of text" *by construction*.

### The caveats, which are real

- **Device floor: iPhone 15 Pro+ with Apple Intelligence enabled.** `SystemLanguageModel.default.availability` must be a first-class product state alongside "no Full Access" and "no network" in §23.
- **~30 tokens/s** on-device. A 60-token structured response ≈ **2 s**, over §22's 1.5 s target. Requires `prewarm()` and `streamResponse`.
- **`rateLimited` is routine, not exceptional.** Apple: rate limiting applies "when your device is on battery AND when your process is running in the background." Whether a keyboard extension counts as background is **UNVERIFIED** — a Safari extension was throttled after **4 requests at 30-second intervals**. Debounce ≥350 ms, one in-flight request, always handle `rateLimited` by silently suppressing.
- **The one vendor who shipped Foundation Models in a keyboard says it is "noticably slower and less accurate"** than conventional autocomplete. Use it for translation and teaching; **never as the P0 typing engine.**

*(Research 03 throughout; corroborated by Research 02 §3.6)*

---

## 3. Corrections to the PRD, by section

Only defects with a concrete consequence are listed. Full detail in the linked reports.

| § | Defect | Correction |
|---|---|---|
| **4** | "does not receive **unrestricted** network access" | It receives **no network access at all** |
| **4** | Full Access described as gating network only | It also gates **App Group writes**, `UIPasteboard`, **haptics**, and **all speaker access (so `AVSpeechSynthesizer`)**. It does **not** grant microphone |
| **4** | `hasFullAccess` treated as a stable boolean | **Unreliable in `viewDidLoad`**; no change notification (poll on `viewWillAppear`); toggling it terminates the extension and can SIGKILL the containing app |
| **4** | `documentContextBeforeInput` as "limited context" | **Paragraph-truncated, host-dependent, `nil` in Gmail/Mail after paste, only the last ~2 sentences of pasted text in WhatsApp/Signal/Telegram. No documented length guarantee.** The widely repeated "300 character cap" could not be traced to any primary source — treat as folklore. **Maintain a shadow buffer; use the proxy only as a reconciliation hint** |
| **4** | Missing | No microphone even with Full Access · **no way to identify the host app or return to it** (Apple DTS, 2026; killed KeyboardKit's feature) · cannot present modal UI · cannot draw outside your own frame · **iOS 26 draws uncoverable grey margins in Apple's own apps** · launch resize flicker (~390 ms) is an unsolved platform problem · Apple emoji artwork may not be bundled (5.2.5) |
| **5** | "moved away from the fully open-source model" | **Entirely closed-source, binary-only, LicenseKit-gated.** See B4 |
| **7** | Six triggers listed; §17 lists three different ones | **Delete the §7 list.** §17 is the single normative source |
| **7** | "tiny authenticated proxy" | Names no auth mechanism; a shipped app cannot hold a shared secret. **No rate limit, no per-device quota, no spend cap** — with §17's retry behaviour that is an unbounded bill |
| **9** | "use local language recognition first" | Specify **`NLLanguageRecognizer` with `languageConstraints = [.english, .italian]`** — the single biggest accuracy win available, and the PRD omits it. Make the thresholds testable: ≥3 word tokens / ≥12 chars, top hypothesis ≥0.75, margin ≥0.25, two-consecutive-agreement hysteresis |
| **9** | Auto is EN/IT only; §11 Mode E fires "when the user writes directly in Spanish" | **ES is not a representable state.** ES/IT is the highest-confusion pair on short strings — the system will "translate" the user's correct Spanish and teach them it was wrong. **Auto must be three-way {EN, IT, ES}** |
| **10/11** | Insert ES is the headline action | See §5 below. Also: the learning bar replacing the suggestion row (§10) contradicts autocorrect being P0 (§24, §30) |
| **12** | P0/P1 split | **Emoji keyboard, basic autocorrect, accessibility/VoiceOver, Undo, `keyboardType`/`returnKeyType` handling, bad-translation reporting, and secure/numeric-field suppression are all absent or under-prioritised — and the product is unusable without them.** Italian support, auto-detection and the cache are all softer than P0 |
| **13** | Single `mastery` float | **A float does not decay.** No recognition/production split, no difficulty/stability separation, no cold start, no confidence, no sense distinction, and `exposures` feeds mastery directly — which means assistance fades for words the user never learned. See §4 below |
| **14** | Threshold ladder | Gives the **least effective** gloss format to the newest items and reserves the effective format for items already at 0.80+. **Invert it.** "occasionally" and "normally" — the only two rungs with real learning value — are undefined |
| **15** | Request/response schema | No `requestId`/`inputHash`, so §17's "never show a stale translation" and §27's acceptance test are **not implementable**. `knownVocabulary`/`learningVocabulary` are unbounded, vary per request (destroying the cache), and **leak a longitudinal learning profile in violation of §21**. No Spanish variety or register field. No status enum for already-Spanish / incomplete / refused. `confidence` is uncalibrated with no consumer |
| **16** | "always standard Spanish" | **Not a real variety.** `coger` is neutral in es-ES and vulgar across much of es-419; `vosotros`/`ustedes`; `tú` to a boss. Pick one and write it down. Also missing: no rule for already-Spanish input, no anti-injection delimiting, no rule forbidding the model from *answering* the user's message, no profanity-preservation rule (the model will soften the user's own words) |
| **17** | Trigger conditions | **Newline is actively harmful** — in chat apps Return *sends*, so you fire on an empty field having already woken the radio. Character-matching `.`/`?`/`!` is not sentence detection. **No suppression rules at all.** No generation counter |
| **18** | "strip obvious passwords/tokens where detectable" | Undefined and unreliable. **Add a hard suppression list**: `keyboardType` ∈ {numberPad, decimalPad, phonePad, emailAddress, URL}, `textContentType` ∈ oneTimeCode/password/creditCard*, high-entropy patterns. iOS only substitutes the system keyboard for `isSecureTextEntry` — 2FA codes and card numbers frequently are not flagged |
| **19** | App Group as the store | See B2. Also add `schemaVersion` — a keyboard extension that crash-loops on an unmigrated store is unrecoverable without deleting the app |
| **21** | Full Access explanation | Now wrong in the user's favour — see §2 |
| **22** | "<1.5 s remote" | No percentile, no start event, no timeout value. **Realistic p50 1.9–2.4 s, p95 4.5–6 s** for a one-shot JSON LLM response. The ">3 s → suppress" branch would fire on a substantial minority of requests, not as an exception. Also: no memory number, no cold-start budget, no replace-sentence cost |
| **24** | "haptic/audio feedback where allowed" | **Haptics require Full Access; key click sound does not** (adopt `UIInputViewAudioFeedback` + `playInputClick()`). `UILexicon` — free, no Full Access, gives common words + Text Replacement shortcuts + contact names — is never mentioned |
| **26** | Phase plan | No time estimates, no dependencies, and acceptance criteria that cannot be evaluated by a test. Missing an entire phase — see §6 |
| **27** | "Repeated exposure increments local learning state" | **This acceptance test enshrines the bug.** Replace with "suppression accuracy ≥85 %" and "model log loss beats a frequency+recency baseline" |
| **29** | iOS 18+ | **Wrong floor.** Headless `TranslationSession` is iOS 26.0; Foundation Models is iOS 26. iOS 26 was already on **79 % of all iPhones** as of Apple's 2026-06-07 measurement |

---

## 4. The learning engine needs replacing, not tuning

§13's record is `{exposures, successful_recalls, failed_recalls, last_seen_at, next_review_at, mastery, status}`. Ten distinct failure modes are documented in Research 06; three matter most.

**A stored float cannot forget.** `mastery: 0.72` is the same value after 3 days and after 8 months. `last_seen_at` is stored but nothing in §14 reads it. The forgetting curve is the entire subject matter of spaced repetition, and this model has none.

**Exposure is counted as learning, and that error is self-reinforcing.** The meta-analytic correlation between repetition and incidental vocabulary learning is **r = .34**, explaining ~12–17 % of variance. But any monotone `mastery ← f(exposures)` overstates knowledge → §14 suppresses teaching → no further learning **and no further evidence to correct the estimate.** The flagship differentiator ("assistance becomes progressively less explicit") degenerates into "the app stops helping with words you never learned."

**Recognition and production are conflated.** Receptive knowledge systematically exceeds productive. The product's stated goal is *production*. A model tracking only recognition will declare victory silently.

**Recommended replacement:** FSRS-6 as a memory-state *estimator* (not a scheduler — you cannot choose when the user texts someone), with two traces per item (`recognition`, `production`), an efficacy weight η attenuating ungraded exposures (~0.03–0.30 vs 1.0 for a graded recall), exposures writing **only** to the recognition trace, and item-feature cold-start priors from frequency + cognate distance. `mastery` becomes a derived display value, never a decision variable. An append-only `event` log makes the whole model re-fittable later — without it, your first η guess is permanent.

**The cheapest high-value change in the entire document:** cold-start priors driven by cognate distance. On day one, `hotel`, `taxi`, `internet`, `problema`, `importante`, `posible` should start easy so the per-sentence teaching budget is never wasted on them. For an EN+IT bilingual, **cognate distance is a better difficulty feature than CEFR level.** *(Research 06 §2)*

---

## 5. The product risk the research did not resolve

Two agents reached this independently, from different directions.

**The UX walkthrough.** Real scenario, WhatsApp, walking to the bus: debounce (0.5–0.9 s) + network (realistic p50 1.2–2.5 s) means the suggestion arrives **1.7–3.4 s after the user stops typing**. A chat message is composed and sent in 4–8 s. The suggestion arrives during the last beat or after send. §22's own fallback — ">3 s: suppress" — means the system is *specified to give up in the common case*.

**The recipient is never mentioned in 1,147 lines.** The user typed English *because they are writing to an English speaker*. Inserting Spanish makes the message unreadable to them. The only contexts where Insert ES is coherent are (a) messaging an actual Spanish speaker — where the user should be composing in Spanish and using Mode E — and (b) Notes/drafts, where there is no recipient.

**The pedagogy points the same way.** In the gloss meta-analysis (359 effect sizes, N=3,802), **multiple-choice glosses were most effective and in-text glosses least effective** — and Modes A/B are in-text glosses. Under the Involvement Load Hypothesis, an unrequested translation banner has need=0, search=0, evaluation=0, the lowest-involvement intervention the framework describes. And a persistent horizontal strip above the keys, present on every message, whose content is not required to send the message, is **structurally an ad banner** — banner blindness is a design certainty here, not a risk.

**Insert ES is worse than neutral.** The user needs the Spanish, the system supplies it without retrieval, and the log records "user sent a Spanish message" — the product's success metric — while no learning occurred. It also corrupts measurement: "% of characters typed in Spanish" is uninterpretable if some were pasted.

**The closest prior art agrees.** WaitChatter (CHI 2015) taught ~57 words in two weeks inside a chat client — but with **micro-quizzes, not translations**, fired **after sending**, in the dead time. Its follow-up (WaitSuite, TOCHI 2017) found **chat was the lowest-engagement of all the waiting contexts tested**, because of competing demands.

### What follows

Three changes, in descending order of evidence-to-effort:

1. **Fire the learning bar on `send`, not on a mid-sentence pause.** A sentence-final send is a coarse breakpoint; a debounce pause is a fine one, where the user must also reconstruct their position. This is close to a one-line change and it has the best evidence in the entire body of research.
2. **Make the default terminal action a retrieval, not an insert.** Keep the insert button — it is a real usability feature — but log it with `η = 0`, exclude inserted characters from every Spanish-production metric, and queue that item for recall within 24–72 h. Turn the crutch into a scheduling signal.
3. **Promote Mode D (recall) and Mode E (correction) to P0; demote Mode C (code-switch) to a flagged experiment.** Mode C is the most novel-feeling and least-supported mode in the PRD, and for a learner whose documented failure mode is over-transfer between near-identical languages, rehearsing a blended IT-ES-EN register is a plausible way to *manufacture* fossilisation.

**The red team's cheaper experiment, stated plainly:** deploy the endpoint and a ~150-line SwiftUI app with a text field, a Translate button and a speaker — plus a Share Sheet extension so it can be invoked on selected text anywhere. Live with it for a month. It exercises the entire learning engine, the prompt, the API contract and the pedagogy with **none** of the keyboard-extension cost: no Full Access, no App Group, no memory ceiling, no emoji problem, no accessibility surface. *(Research 07 §6, Research 06 §6)*

---

## 6. Effort reality

§26 has no estimates. Honest solo-developer figures (~10–12 h/week, competent iOS dev, first keyboard extension):

| Phase | Real hours | Elapsed |
|---|---|---|
| 0 — Shell (layout, shift/caps timing, delete acceleration, **secondary accent callouts**, autocap, space-scrub, height constraints, `keyboardType`/`returnKeyType`, App Group, provisioning) | 70–110 h | 7–10 wks |
| **0.5 — the phase the PRD omits entirely**: emoji keyboard, autocorrect + dictionary, accessibility | **60–90 h** | 6–8 wks |
| 1 — Translation MVP | 45–70 h | 4–6 wks |
| 2 — Learning engine | 60–100 h | 6–9 wks |
| 3 — Adaptive recall | 70–120 h | 7–12 wks |
| 4 — Polish | 60 h+ | 6 wks+ |

**Total to §31's V1: ~360–550 hours, 8–14 months part-time.** The PRD reads as a 6–8 week project. **Phase 0.5 alone is comparable in size to Phase 1.**

The on-device architecture (§2) reduces Phase 1 meaningfully — no proxy, no key management, no rate limiter — but it does not touch Phase 0 or 0.5, which are the bulk of the work and are pure keyboard mechanics.

---

## 7. What survived intact

Worth stating, because the rewrite should not throw these away:

1. **§4 is unusually well-researched** for a keyboard PRD. The corrections above are refinements to a section that got the shape right.
2. **§7's refusal to ship a provider key in the client** is correct and non-negotiable.
3. **§5's "isolate the framework behind an abstraction layer"** is the best decision in the document, and the KeyboardKit findings make it mandatory rather than prudent.
4. **§30's build-priority ordering** (typing quality → reliability → speed → teaching UI → adaptation) is right and should govern the rewrite. The rest of the PRD violates it; the principle is sound.
5. **§24's opening line** — *"A poor typing experience will kill the product faster than weak AI"* — is the truest sentence in the document.
6. **§25's anti-branding stance** is right and rare.
7. **§14's "least intrusive intervention that still produces useful learning" and the per-sentence budget of one concept** is good pedagogy. Every number in it is a placeholder, but the shape is worth keeping.
8. **§17's cancellation invariant** — never display a stale translation — is correct.
9. **§21's default posture** is a better privacy stance than most shipping keyboards, and the on-device architecture makes it dramatically stronger.
10. **§33's product principle** is a real, falsifiable one-sentence thesis. Every finding above is ultimately an argument that the document does not yet honor it.

---

## 8. Decisions required before Phase 0 can be planned

| # | Decision | Recommendation |
|---|---|---|
| D1 | Pay the $99 Apple Developer Program? | **Yes, but before first dogfooding rather than before first code.** Revised: App Groups and Keychain Sharing are available free, so the persistence design is not blocked. The 7-day profile expiry is what makes the free tier unusable as a daily driver. A sideloader (AltStore/SideStore) is a reasonable Phase-0 convenience, not a shipping configuration |
| D2 | Keyboard foundation | **Vendor OpenKeyboardKit (MIT) into the repo**, after a 2-day throwaway KeyboardKit spike to calibrate the quality bar. First Phase-0 task: get it building under Xcode 26. ~1–2 days remediation expected (stale `exact:` dependency pins are the likely failure, not the 22.7k LOC) |
| D3 | Deployment target | **iOS 26.0**, built with the **iOS 26 SDK (Xcode 26)**. iOS 26 unlocks headless `TranslationSession` and Foundation Models and gives one Liquid Glass visual target. Defer the iOS 27 SDK until ~27.1 — iOS 27 exposes **no new keyboard API whatsoever** (verified four independent ways) |
| D4 | Translation engine | **On-device first** (§2). Remote LLM becomes an opt-in escalation rung, deferred out of V1 |
| D5 | Product shape | **The open question.** Either accept the red team's staged experiment (Share Sheet app first, keyboard only if it survives 30 days of daily use), or proceed to the keyboard with the three §5 corrections applied. This changes the roadmap fundamentally and is the user's call |
| D6 | Spanish variety | Pick **es-ES** or **es-419** and write it into §16 verbatim. Not deferrable — it changes lexis and morphology |
| D7 | EN/IT/ES in one keyboard target | One keyboard with a dynamic `primaryLanguage`, or one target per language (each appearing separately in Settings). §12 P0 implies the former; it is never stated |

**D5 gates the roadmap.** Everything else can be planned around either answer.

---

## Research index

| # | Report | Headline finding |
|---|---|---|
| 01 | [iOS keyboard platform constraints](research/01-ios-keyboard-platform-constraints.md) | Six things that can kill the product; §4 and §22 corrections; iOS 27 addendum |
| 02 | [Keyboard foundation & licensing](research/02-keyboard-foundation-licensing.md) | KeyboardKit closed-source and paywalled; `ProFeature` enum extracted from the binary |
| 03 | [Apple on-device AI stack](research/03-apple-on-device-ai.md) | **Inverts the local/remote split.** Translation + Foundation Models run in a keyboard extension without Full Access |
| 04 | [Provisioning, review, compliance](research/04-provisioning-review-compliance.md) | $99 is a Phase-0 prerequisite; guideline 5.1.2(i) requires a provider-named consent gate |
| 05 | [LLM API latency, cost, contract](research/05-llm-api-latency-cost.md) | 1.5 s p50 is not achievable one-shot; §15's schema makes its own responses uncacheable |
| 06 | [Learning science & engine](research/06-learning-science-engine.md) | The mastery model is not a memory model; exposure ≠ learning; fire on send |
| 07 | [Adversarial red team](research/07-prd-red-team.md) | 75 findings; the kill-shot is that nobody wants to insert Spanish into a message to an English speaker |
| 08 | [iOS 27 SDK floor & behaviour gaps](research/08-ios27-sdk-and-behaviour-gaps.md) | iOS 26 SDK floor CONFIRMED with no iOS 27 deadline; the App Store accepts nothing built with the 27.0 SDK today; host-app identity is permanently `nil` |
| 09 | [Free-tier personal-device paths](research/09-free-tier-personal-device-paths.md) | **Corrects 04**: App Groups and Keychain Sharing are free-tier capabilities. The real blocker is the 7-day profile, which no sideloader and no EU route can extend |
