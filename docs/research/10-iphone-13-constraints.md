# Research 10 — iPhone 13 Verification Pass

> Source: research subagent, 2026-08-19. **Device under test:** iPhone 13 (iPhone14,5), A15
> Bionic, 4 GB RAM, 4-core GPU, 16-core ANE, 6.1" 2532x1170 **@60 Hz**, shipped 2021-09-24.
> **Egress blocked:** `support.apple.com`, `www.apple.com`, `machinelearning.apple.com`,
> `en.wikipedia.org`, `macrumors.com`, `9to5mac.com`, `dev.to`, `developer.apple.com/forums`
> (bot-wall). Reachable: `developer.apple.com` docs/videos/release notes via the JSON API,
> `raw.githubusercontent.com`, GitHub code search, WebSearch summaries.

---

## 1. Apple Intelligence eligibility — total and permanent

### 1.1 The requirement

Apple does **not** publish a chip-and-RAM requirement. It publishes a **device list**, and every developer-facing doc points at it:

> "To use Apple Foundation Models, people need **a device that supports Apple Intelligence**."
> — [Foundation Models framework overview](https://developer.apple.com/documentation/foundationmodels). **CONFIRMED**

> "Model availability depends on whether the **device and region** supports Apple Intelligence."
> — [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel). **CONFIRMED**

The device list (from search summaries; the canonical URL is egress-blocked): iPhone 15 Pro, 15 Pro Max, 16e, 16, 16 Plus, 16 Pro, 16 Pro Max, 17e, 17, Air, 17 Pro, 17 Pro Max. iPhone 15/15 Plus and **every iPhone 14, 13, 12, 11 are excluded**. **LIKELY**.

**The "A17 Pro + 8 GB" framing is an inference, not an Apple specification.** It is the smallest correct generalisation over the list (the A16 iPhone 15 has 6 GB and is excluded, which makes RAM rather than chip generation the discriminator). Treat as **LIKELY** and write the *device list* into the project, not the chip/RAM rule.

**iPhone 13: A15, 4 GB. Not on the list, cannot be added.** `UnavailableReason` has exactly three cases: `appleIntelligenceNotEnabled` (user setting), `modelNotReady` (download), `deviceNotEligible` (hardware). **Only the third applies and only the third is unrecoverable.** **CONFIRMED**

### 1.2 PCC does NOT rescue you — the decisive finding

Apple states it three ways in one document:

> "You don't need to handle either when you use PCC. People just need **a device that supports Apple Intelligence** and gets a daily request limit."
> "**PCC is only available on devices that support Apple Intelligence**, so check `availability` before performing your request:"
> ```swift
> let model = PrivateCloudComputeLanguageModel()
> switch model.availability {
> case .unavailable(.deviceNotEligible): // Show an alternative UI.
> ```
> — [Adding server-side intelligence with PCC](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute). **CONFIRMED**

`PrivateCloudComputeLanguageModel` exposes the *same* `.unavailable(.deviceNotEligible)` case. **PCC is a server model whose client is gated on Apple Intelligence hardware.** No entitlement, no opt-in, no Settings toggle changes this. Further: the entitlement is **managed** (Apple must approve), PCC is **iOS 27.0+ beta**, and per research 08 the App Store accepts **no iOS 27-SDK build at all** today.

### 1.3 Is there any path to Foundation Models on an iPhone 13?

**The Apple model: no. Never. On any iOS version.**

**The Foundation Models *API*: yes, on iOS 27, with your own weights.** The one genuinely new thing this pass found:

> "Use other on-device models when you need to: … **Support a range of devices that might not support Apple Intelligence.** … With Core AI, you can deploy AI models within your app and load them into the same language model session API you already use. **Only the model you pass into `init(model:tools:instructions:)` changes.**"
> — [Running a Core AI model in a Foundation Models session](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session). **CONFIRMED**

`LanguageModel` / `LanguageModelExecutor` / `LanguageModelCapabilities` (iOS 27.0, beta) let a custom model back a `LanguageModelSession`, including `@Generable` guided generation. Apple's `coreai-models` package ships an iOS-supported **Qwen3 0.6B** recipe, and the doc recommends "around 0.6B parameters as a good first choice." **CONFIRMED**. But: iOS 27 + Xcode 27, beta, unshippable, and the model runs **in-process** — arithmetically impossible in a keyboard extension. See §5(c).

**Verdict: the entire Foundation Models column of the stress test is dead on this hardware, including the PCC escalation rung, and no iOS update changes that.**

---

## 2. Translation on a non-Apple-Intelligence device — survives, cleanly

### 2.1 Does it work? Yes, and Apple says so explicitly

| Symbol | Introduced |
|---|---|
| `Translation` framework, `translationPresentation` | **iOS 17.4** |
| `TranslationSession`, `LanguageAvailability`, `prepareTranslation()` | **iOS 18.0** |
| `init(installedSource:target:)` (headless) | **iOS 26.0** |
| `Strategy`, `preferredStrategy`, `LanguageAvailability(preferredStrategy:)` | **iOS 26.4** |

All **CONFIRMED**. Nothing carries an Apple Intelligence precondition. The decisive sentence:

> "This is **the default strategy for devices without Apple Intelligence** and apps built with SDKs before iOS 26.4."
> — [`lowLatency`](https://developer.apple.com/documentation/translation/translationsession/strategy/lowlatency). **CONFIRMED**

Apple is stating in its own API reference that devices without Apple Intelligence translate. **On an iPhone 13 the framework is not degraded-with-warnings; it is on its default, documented path.**

### 2.2 `.highFidelity` vs `.lowLatency`

**`.highFidelity`** — "more fluent translations **using Apple Intelligence**. … higher-quality translations and supports additional languages, but may take longer … **On devices without Apple Intelligence, it falls back to the traditional models used by `lowLatency`.**"

**`.lowLatency`** — "fast translations using traditional models. … requires downloading languages before use, but after they are downloaded **they are available to all apps on the device**. … faster and uses less power, though translations are **not as fluent**."

Consequences, all **CONFIRMED**:

1. **`.lowLatency` genuinely works on non-eligible hardware.** It is the only thing that runs there.
2. **`preferredStrategy` is a no-op on an iPhone 13.** Whatever you pass, you get `.lowLatency`. Passing `.highFidelity` is safe (documented fallback) and forward-compatible, but **do not raise the deployment floor to 26.4 for it**. Ship against **iOS 26.0's `init(installedSource:target:)`**.
3. **Apple documents a quality difference and quantifies none.** The only characterisation is *fluent* / *not as fluent*, plus "supports additional languages." **No BLEU, no COMET, no human eval, no per-pair breakdown, nothing on EN->ES or IT->ES** anywhere in the documentation, the WWDC24 session, or the iOS 26/27 release notes. **A hard negative finding. Anyone claiming "highFidelity is N% better on EN->ES" is inventing it.**
4. **Inferable shape of the gap (LIKELY):** `.lowLatency` is the model family powering the Translate app since iOS 14 on A12-class hardware — small, quantised, encoder-decoder NMT, one model per direction. `.highFidelity` is LLM-based from the AFM family. So the gap is **not adequacy but fluency and register**: `.lowLatency` will get the *meaning* of a short chat sentence right and be flatter, more literal, more likely to take the dictionary-default register, worse at idiom, pronoun-drop and clitic placement. For **EN->ES** — the most-resourced pair in machine translation — short-sentence quality should be high.
5. **The pedagogically relevant risk is the opposite of the usual one.** A *stiff but correct* Spanish sentence is close to harmless for a learner, arguably better than a fluent idiomatic one, because it is closer to the compositional mapping the learner is building. The thing to watch is not bad Spanish but **register drift** (a `tú`/`usted` choice you never made), which is invisible to the user and is exactly what the product claims to teach. **Budget a manual eval: 100 held-out sentences the author actually sent, EN->ES and IT->ES, hand-scored for adequacy / register / peninsular-ness. It is the only quality number you will ever have.**

### 2.3 Language-pack download flow — confirmed end to end, packs are system-wide

**The packs are NOT pre-downloaded on this device.** The "already downloaded when Apple Intelligence is enabled" shortcut is precisely what an iPhone 13 does not get.

> "A session created using `.translationTask()` **can always request downloads**, however when it's created directly using `init(installedSource:target:)` **it cannot request downloads**. The system only throws an error when attempting to translate and the languages aren't installed."
> — [`canRequestDownloads`](https://developer.apple.com/documentation/translation/translationsession/canrequestdownloads). **CONFIRMED**

> `TranslationError.notInstalled` — "The device doesn't have the necessary languages downloaded … **and the session can't request the person to download them**." **CONFIRMED**

So: **host app owns the download, keyboard consumes headlessly.**

**Do the packs cross the app boundary? Yes — twice confirmed, and this is load-bearing:**

> "after they are downloaded **they are available to all apps on the device**." — [`lowLatency`](https://developer.apple.com/documentation/translation/translationsession/strategy/lowlatency). **CONFIRMED**

> "`TranslationSession` performs translation using on-device ML models. **These models are shared with all apps on the system, including the Translate app. If the user has already downloaded languages, your app can use them too.** … And these downloads will continue in the background when the user dismisses this sheet, **or even if they leave your app entirely**."
> — Louie, Machine Translation team, [WWDC24 session 10117](https://developer.apple.com/videos/play/wwdc2024/10117/), transcript fetched 2026-08-19. **CONFIRMED**

It is a **system-level asset store**, not per-app.

**The flow to build:**
1. Host app onboarding: SwiftUI view with `.translationTask(configuration)`, `session.prepareTranslation()` for `en->es` and `it->es`. User approves once; downloads continue if they leave the app.
2. Host app polls `await LanguageAvailability().status(from:to:)` until `.installed`, writes that to shared state.
3. Keyboard: `TranslationSession(installedSource:target:)`, translate, catch `TranslationError.notInstalled` -> show a "finish setup in the app" affordance. **Never** let `notInstalled` surface as a silent no-result.
4. **Re-check on every keyboard appearance** — the user can delete downloaded languages in Settings at any time. **This is a first-class product state alongside "no Full Access" and "no network", and it did not exist in the Apple-Intelligence-device plan.**

### 2.4 IT->ES: available, but check at runtime and expect nothing

- Both **Spanish (Spain)** and **Italian (Italy)** are Apple Translate languages (iOS 26 set, 21 languages/accents). **LIKELY** — canonical list is on the blocked `support.apple.com`.
- **Apple explicitly warns not all pairs exist:** "The framework doesn't support every combination of languages." **CONFIRMED** (WWDC24 10117). `TranslationError.unsupportedLanguagePairing` exists. **CONFIRMED**
- **Direct vs EN-pivot is undocumented and unobservable.** No API tells you. **UNVERIFIED and unresolvable** — you cannot settle it even on-device, only infer from output quality (pivot artefacts: English calques, loss of Italian politeness forms, collapse of IT/ES false friends). **Do not build anything that depends on knowing.**
- **What you must do:** `await LanguageAvailability().status(from: .init(identifier:"it"), to: .init(identifier:"es"))` on a real iPhone 13 on day one. Three outcomes, three product designs. **If `.unsupported`, IT->ES means chaining two `TranslationSession`s through English in your own code — at which point you should probably drop Italian from V1 rather than teach Spanish through a double-translated intermediate.**

### 2.5 The one thing that could still kill this

**Does `TranslationSession` work inside a keyboard extension? UNVERIFIED.** What this pass added:

- No `NS_EXTENSION_UNAVAILABLE`, no extension caveat anywhere in the Translation docs. **CONFIRMED** (negative).
- **Two real projects put it in a keyboard target.** `leoyoyofiona/triple-space-translator` calls `TranslationSession(installedSource:target:)` directly in `TripleSpaceKeyboardExtension/KeyboardViewController.swift:190`; `aminbenarieb/translatekb` wires an `AppleTranslationSessionBridge` into `Keyboard/Sources/KeyboardViewController.swift`. **CONFIRMED** (source read). Neither ships on the App Store; the first labels its keyboard "Experimental" and has no `notInstalled` handling — **evidence of intent, not of success.**
- Apple: "these translation APIs **don't function in the Simulator**." **CONFIRMED**. **You cannot pre-flight this.**

**The day-one test, ~30 minutes:** throwaway keyboard extension with `RequestsOpenAccess: false`, real iPhone 13, host app has already downloaded `en->es`. In `viewDidAppear`: log `LanguageAvailability().status` for `en->es` and `it->es`; construct `TranslationSession(installedSource:target:)`; translate `"I'll arrive around eight"`; log result, error, and `task_vm_info.phys_footprint` before and after.

**If this returns Spanish, the entire architecture holds. If it throws a sandbox or XPC error, the keyboard cannot translate at all and the product becomes the Share Sheet app. Nothing else in this brief is worth more than this half hour.**

---

## 3. iOS version support — fine on both, and iOS 27 is irrelevant anyway

| Question | Answer | Confidence |
|---|---|---|
| iPhone 13 runs **iOS 26**? | **Yes.** iOS 26 supports iPhone 11 and later (A13+) | **LIKELY** (canonical list blocked; corroborated across sources) |
| iPhone 13 runs **iOS 27**? | **Yes.** iOS 27 drops **no** devices — same list as iOS 26 | **LIKELY** (same blockage) |
| Planning constraint? | **No.** Supported through at least the iOS 27 cycle, ~autumn 2027 | — |

**But iOS 27 does nothing for you regardless** (research 08): no new keyboard-extension API, and the App Store accepts no iOS 27-SDK build. **Keep iOS 26.0 / Xcode 26.**

**One iOS 27 item research 08 filed as moot that is NOT moot:**

> "The system now **restricts background access to the Neural Engine** … **Access to the Neural engine when your app is in the background requires the new entitlement: `com.apple.developer.background-tasks.continued-processing.inference`.** (179282606)"
> — iOS/iPadOS 27 beta release notes, Core AI section. **CONFIRMED**

The first sentence is scoped to "Apple Intelligence capable devices"; **the entitlement sentence is unqualified.** Apple's `.lowLatency` translation models, `NLTagger` and `NLLanguageRecognizer` all plausibly use the ANE. If iOS 27 treats a keyboard extension as background — the open question research 03 flagged, with Safari extensions as the precedent saying *yes* — then **on-device translation from inside the keyboard could be throttled or refused on iOS 27, on this device, even though none of it is Apple Intelligence.** **UNVERIFIED, high impact.** Test before adopting the iOS 27 SDK, not after.

---

## 4. Memory on a 4 GB device

### 4.1 What Apple says

> "that process has a limit on the amount of memory it may use. **If your keyboard extension exceeds the memory limit the system terminates it.** … **Test your keyboard on various device models. The memory limits vary from model to model.**"
> — [Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard). **CONFIRMED**

That is the whole of Apple's published position. **No number, no per-model table anywhere.** No jetsam-properties plist on GitHub, no technote; the two relevant forum threads are behind the bot-wall.

### 4.2 What the evidence supports

- Community-measured ceilings cluster **~30-60 MB `phys_footprint`**, with a widely-cited **48 MB** figure from [react-native#31910](https://github.com/facebook/react-native/issues/31910). **LIKELY**
- **No measurement anywhere differentiates a 4 GB device from an 8 GB one for a keyboard extension. A genuine gap in the public record. UNVERIFIED**
- The *app* per-process jetsam limit does scale with RAM (4 GB devices report `jetsam mem limit: ActiveHard 2098 MB`). Apple's "vary from model to model" plus that scaling makes it **LIKELY** the extension cap also scales, and **certain** the iPhone 13 is at the bottom of the supported range on RAM class.

### 4.3 Is 40 MB / 30 MB safe? No — lower it

1. **You are on the low-RAM end of the fleet.** Designing to 40 with an alarm at 30 leaves **8 MB of margin against the most-cited hard number**, on the device most likely to be below it. That is a coin flip, not a margin.
2. **On 4 GB the per-process cap is not the only killer.** Jetsam fires on **system-wide** pressure too, and extensions sit in the lowest-priority bands. Your keyboard runs inside WhatsApp or Safari on a 4 GB phone. **It can be killed well below its own limit simply because the host app grew.** Only *being small* reduces how attractive a victim you are.
3. **You cannot reliably measure the cap.** `os_proc_available_memory()`: **"If the calling process isn't an app, or if the process has already exceeded its memory limit, this function returns `0`."** **CONFIRMED**. A keyboard extension is not an app. Whether it returns a real number is **UNVERIFIED** and community reports conflict. **Research 03's day-1 probe list assumes it works; it may not.**

| | Old | New |
|---|---|---|
| Design target (steady state) | 40 MB | **25 MB** |
| Alarm / telemetry breach | 30 MB | **20 MB** |
| Hard "never reach" | — | **35 MB** |

**Measurement protocol, because the above is a guess until replaced:** ship a debug keyboard that allocates 1 MB dirty pages in a loop, logging `task_vm_info.phys_footprint` after each, until it dies. Run **five times** — inside Messages, inside WhatsApp, inside Safari with 20 tabs, immediately after reboot, and after two hours of normal use. **The lowest of the five is your real ceiling; the spread is the system-pressure effect and is the number that actually matters on 4 GB.** Two hours of work, converts the project's largest UNVERIFIED into a number.

**Instrument with `task_vm_info` / `phys_footprint`, not `os_proc_available_memory`.** Treat a `0` return as "unusable", not "out of memory".

**The technique that makes the lower budget affordable:** put all bundled linguistic data in **`mmap`'d, read-only, on-disk binary blobs with binary search or a perfect hash** — never `Data(contentsOf:)`, never decoded JSON/plist, never an in-memory dictionary. Clean file-backed mapped pages are evictable and **not** counted in `phys_footprint` the way dirty anonymous pages are (**LIKELY** — verify with the same probe). This is what makes §5(a) fit in 25 MB when its raw data is 20 MB+. SQLite in WAL/mmap mode is the boring version and is fine.

### 4.4 A15 vs A17/A18 at 60 Hz

**The frame budget genuinely relaxes: 16.7 ms, not 8.3 ms.** With an A15 only ~20-25 % behind A17 Pro single-core (**LIKELY**), **per-frame CPU is a non-issue for a keyboard.** A keyboard's per-frame work is layout and text, not compute. **Do not spend engineering effort on the frame budget.**

**What *is* a real A15 concern, in priority order:**
1. **GPU, not CPU.** iPhone 13 non-Pro has a **4-core** GPU (13 Pro has 5). Liquid Glass is a per-frame backdrop-blur workload, and iOS 26 is widely reported to feel laggy on iPhone 11/12/13 — **with keyboard lag specifically named**. **LIKELY**. If you use `.glassEffect` on a keyboard-sized view that redraws per keystroke, **measure before committing**, and treat **Reduce Transparency** and **Reduce Motion** as first-class supported appearances, not accessibility afterthoughts — many iPhone 13 users have already enabled them to fix exactly this.
2. **Cold start, which the frame budget does not help.** The ~390 ms launch/resize flicker is a fixed cost and is *worse* on A15. Every millisecond of `viewDidLoad` work is paid on every first appearance in every app. Lazy-load everything that is not the key grid.
3. **Your own success criterion is measured against a degraded baseline.** Criterion (a) is "median compose time with the bar shown versus suppressed, within 10 percent." On a device where the *system* keyboard is already reported to lag under iOS 26, the relative comparison is right but the absolute numbers will look bad and will not be your fault. **Log absolute figures too.**

---

## 5. What replaces the on-device teaching layer

### (a) Fully deterministic and bundled

**1. Focus-word selection — FULLY DETERMINISTIC, and this was always the wrong job for an LLM.** A ranking problem over the words in one sentence, with features you already have: frequency rank, cognate distance from EN and IT, the learner's FSRS state, whether the item is due, session novelty, and the one-concept budget. A scoring function does this in microseconds, with zero memory, **and it is auditable** — which matters enormously when success criterion (d) is "the memory model beats a frequency-plus-recency baseline on log loss." **You cannot ablate an LLM's focus choice. You can ablate a scoring function. Losing the LLM here is a net gain.**

**2. Recall-prompt generation — FULLY DETERMINISTIC, and again better.** Research 06's gloss meta-analysis says **multiple-choice was the most effective format measured**. MC needs a stem and three plausible distractors, and both are *precomputable at build time* — distractors chosen offline by semantic neighbourhood, orthographic similarity and shared-lemma-family confusability, then frozen into the bundled table. **Runtime cost: a table lookup. Memory: zero, if mmap'd.** An LLM generating distractors at runtime would be slower, non-reproducible, and **would make your A/B randomisation uninterpretable.**

**3. One-line grammar explanation — DETERMINISTIC WITH A HAND-AUTHORED DECK.** Two halves:
- *Detection* needs Spanish morphology. `NLTagger(.lemma)` for Spanish is **UNVERIFIED** and Apple calls `.lemma` a *"stem"* form, which is not `llegaré -> llegar, future, 1sg`. **Do not depend on it.** Bundle a **full-form -> (lemma, POS, tense, mood, person, number)** table. Spanish inflection is finite and regular; UniMorph `spa` is ~380k inflected forms, and the top 3-5k verbs x ~60 forms covers essentially everything a chat message contains. Front-coded, sorted, mmap'd: **~3-6 MB on disk, ~0 resident.** This *replaces* the LLM's `lemma:` field with something more reliable.
- *Explanation* is a deck of ~150-300 hand-authored cards keyed on construction id (`FUT_SIMPLE_1SG`, `SE_IMPERSONAL`, `POR_VS_PARA_DURATION`, `PRET_VS_IMPERF_BACKGROUND`, `GENDER_AGREEMENT_ADJ`). Coverage of the A1-B1 constructions actually hit: **~80 % with 200 cards, LIKELY.** For the remaining 20 %, **say nothing** rather than guess — which is also the right pedagogy, since a wrong explanation is worse than none.

**4. Glossing — DETERMINISTIC EXCEPT FOR SENSE SELECTION.** The table is solved (research 06 measured a 17.8 MB Wiktionary-derived es->en gloss file and a 25k-lemma frequency list with surface forms; CC BY-SA, attribute in-app). What is not solved is **word-sense disambiguation**: Wiktionary gives N senses for `banco` and nothing says which. Most-frequent-sense is the baseline, ~60-70 % correct on all-words WSD, better on high-frequency lemmas in short sentences (**LIKELY**).

> **A deterministic mitigation that uses the Translation framework as its own disambiguator:** you already have the sentence translation. Translate the **focus word alone** in the same batch (`session.translate(batch:)` — one request for the sentence, one for the word). If the isolated translation appears as a substring of the sentence translation, you have a confirmed alignment and therefore the sense the translator chose. If it does not, the word is context-sensitive and you should **fall back to showing the sentence pair rather than a gloss.** Cost: one extra string per batch, on-device, ~0 ms. This turns a known-weak deterministic step into a self-checking one, and converts translator disagreement into an explicit "don't gloss this" signal — exactly the behaviour research 06 wants.

**5. Spanish error correction (Mode E) — PARTIAL ONLY.** `UITextChecker(es)` catches non-words and gives `guesses` — free, instant, no Full Access. **CONFIRMED.** But a learner's real errors are *well-formed Spanish words in wrong combinations*, which a spell checker cannot see. Deterministically achievable, in descending precision:
- **Determiner/adjective-noun gender and number agreement**, using a bundled noun-gender table (~30k nouns, tiny). **High precision, high recall, high value.** `*la problema` is caught. **Probably the single highest-value correction rule for an EN+IT bilingual.**
- **Italian-interference lexicon**: ~200 Italian words that pass as Spanish or nearly do (`ma`->`pero`, `niente`->`nada`, `sono`, `anche`, `più`, `già`, `perché`). **Very high precision, trivially cheap, targets the author's documented failure mode.**
- **`ser`/`estar`, `por`/`para`, preterite/imperfect**: a closed rule set gives **moderate precision, low recall.** Fire only on high-confidence subsets, stay silent otherwise.
- **General grammatical error correction is NOT achievable deterministically.** Word order, subjunctive triggers, clitic placement, register. Do not pretend otherwise.

**Summary: 3 of 5 fully deterministic, 1 mostly (glossing, with the translator-alignment fix), 1 partially (correction).**

> **The reframe that makes (a) far stronger than it sounds: nothing says the *authoring* has to be deterministic.** Use a frontier LLM **at build time, on your Mac** to write the 200 grammar cards, pick the canonical gloss for the top 10k lemmas, generate and vet the distractor sets, and build the Italian-interference list. You get **frontier-model quality, not 3B quality**, frozen into data. Runtime cost zero, memory ~0 with mmap, network zero, reproducible, ablatable, versionable in git, reviewable by a human before a user ever sees it. **This dominates every runtime-model option on every axis except open-endedness.**

### (b) Remote LLM on explicit user action only

Survives, and should. The honest escalation rung for the 20 % the card deck does not cover and the GEC determinism cannot do.

Costs are real: the proxy, key handling, the guideline 5.1.2(i) provider-named consent gate, a spend cap, and a network dependency in a product whose privacy story was its differentiator.

**But the volume argument has changed completely.** This is a **single-user product on a single device.** Explicit-tap escalations are maybe 5-20/day — **cents per month, not a business.** The rate limiter, per-device quota and abuse surface that made §7 frightening were sized for a public launch. For a personal app the remote rung is a small amount of infrastructure, **provided** it stays strictly (i) explicit-tap-only, (ii) one sentence at a time, (iii) never on the keypress path, (iv) never carrying `UILexicon` contact names or the learning profile, and (v) fully optional, with the product complete without it.

### (c) A small Core ML model in the host app, results via App Group — **No**

- **The host app is not running.** When the user types in WhatsApp the containing app is not in memory, and **there is no supported way for a keyboard extension to wake it.** So (c) can only ever produce **precomputed** results.
- **Precomputed results are exactly what (a) gives you** — at zero runtime cost, zero memory, zero conversion pipeline, and with build-time frontier quality instead of on-device 0.6B quality. **(c) is strictly dominated by (a) + build-time authoring.**
- **The plumbing is worse:** passing results back through the App Group requires **Full Access** for the keyboard to write. You would add a Full Access requirement to get *worse* content than a bundled table.

For completeness: **Qwen3 0.6B** is the credible candidate, officially supported on iOS via `coreai-models`. But iOS 27 + Xcode 27 only (unshippable), **in-process** (~350-450 MB at 4-bit plus KV cache — fine against a 4 GB device's ~2.1 GB app limit, **impossible** in a 25 MB keyboard), and **A15 is the wrong silicon**: Apple's own iOS 27 notes record that palettized weights with quantized non-Float16 values historically fell off the ANE to CPU/GPU (**CONFIRMED**, 176210080), and the iOS 27 ANE improvements are explicitly scoped to Apple Intelligence devices. Expect GPU execution on a 4-core A15 GPU, multi-second load, thermal and battery cost on a five-year-old battery. **LIKELY.** And a 0.6B model's Spanish explanations are *worse than your hand-authored cards*, which is the whole point.

**Reject (c) for V1.** Carry one thing forward: because `LanguageModelSession` accepts any `LanguageModel`, **writing the teaching layer against that API shape today costs nothing** and would let you swap in Apple's model on newer hardware, PCC, a Core AI model, or a remote provider behind one type. **Design the teaching layer's interface as if a model existed; implement it with tables.**

### Recommendation

**(a) with build-time LLM authoring as the V1 teaching layer, (b) as a strictly explicit-tap escalation deferred to V1.1, (c) rejected.**

1. Three of five capabilities are *better* deterministic — focus selection and recall generation because reproducibility is what makes success criteria (b), (c) and (d) answerable at all; grammar explanation because a curated deck beats a 3B model at one-line A1-B1 explanations.
2. The two weaker ones have specific cheap mitigations: translator-alignment for sense, and gender/agreement + IT-interference for the correction classes that actually bite this learner.
3. The runtime cost is a few MB of mmap'd data and microseconds of lookup — the only thing that fits in 25 MB on a 4 GB phone.
4. It preserves the **"no data collected"** privacy label just as completely as the Foundation Models plan would have.
5. **It is less work than the LLM path, not more**, because it deletes the prompt contract, the schema-validation layer, the latency budget, the rate-limit handling and the streaming UI — all of which research 05 identified as the expensive parts.

**The one thing this costs: open-endedness.** "Why is it *me gusta* and not *yo gusto*" gets an answer only if that construction is in the deck. **That is what (b) is for, and it is the correct place to put a network call.**

---

## 6. Things that bite specifically on A15 / 4 GB / 60 Hz

1. **`os_proc_available_memory()` may return `0` in a keyboard extension.** Apple: "If the calling process **isn't an app** … this function returns `0`." **CONFIRMED.** Research 03's probe list treats it as the primary memory instrument; **it may be useless.** Use `task_vm_info.phys_footprint`. Test in the first hour.
2. **Jetsam on a 4 GB device kills you for someone else's memory.** **The single most under-modelled risk on this hardware**, and the reason the budget drops to 25 MB. It also means the failure is **intermittent and unreproducible** — "it only dies in WhatsApp, sometimes" — the worst kind of bug to chase without a crash log.
3. **iOS 27's ANE background restriction may hit Translation on this device.** §3. The entitlement sentence is unqualified. **UNVERIFIED, high impact, and exactly the kind of thing filed as "Apple Intelligence only, doesn't apply to us."**
4. **Language packs must be downloaded, and can be deleted.** On an Apple Intelligence device this state machine does not exist. Here you need an onboarding download step, a completion check, a `notInstalled` path in the keyboard, a re-check every appearance, and a UX for "the user deleted Spanish in Settings last week." **Pack sizes are UNVERIFIED** — Apple publishes none. Budget storage pessimistically.
5. **`preferredStrategy` is dead code on this device.** Do not raise the floor to 26.4, do not branch on it. Ship against 26.0.
6. **Peninsular Spanish is decided for you by the platform, at least until iOS 27.** Apple Translate's iOS 26 set contains **Spanish (Spain)** and no other Spanish variety; **es-MX and es-US arrive in iOS 27**. **LIKELY.** So the es-ES decision is not merely a choice, it is currently the only thing the framework offers — one less thing to defend, and the iOS 27 upgrade will silently offer a variety switch you must decide to ignore.
7. **`NLEmbedding` is off the table in the keyboard on 4 GB.** At a 25 MB budget it is not a judgement call. **Precompute semantic distractors at build time** and never load an embedding at runtime.
8. **Enhanced `es-ES` voices are 100 MB+ manual downloads with no API to trigger them**, and Full Access is required to speak at all. Plan `.default` quality as the shipping experience.
9. **Plenty of CPU, weak GPU relative to the fleet.** Optimise draws, not computation. Support Reduce Transparency as a real appearance.
10. **A five-year-old battery.** Anything continuous costs more here in user-visible terms. A second, independent argument for the deterministic teaching layer.

---

## What the iPhone 13 constraint costs, and what the architecture is now

**It costs exactly one thing, and costs it completely: the on-device teaching model.** Foundation Models is gone, permanently, on every iOS version, and **PCC does not rescue it** — Apple states in three places that PCC is only available on devices that support Apple Intelligence, so the server model is gated on the *client* being eligible hardware. **A closed door, not a narrow one.**

**It costs nothing else.** Every other pillar survives:
- **Translation survives fully.** Not gated; `.lowLatency` is documented as *the default for devices without Apple Intelligence*; headless `init(installedSource:target:)` is iOS 26.0 with no eligibility precondition; packs are a **system-wide store shared with all apps**, so the host app downloads and the keyboard consumes.
- **iOS 26 and iOS 27 both run here**, iOS 27 drops nothing, and iOS 27 is unshippable and useless to a keyboard anyway. The iOS 26.0 / Xcode 26 floor holds.
- **The privacy story survives**, unchanged: nothing leaves the device.
- **The zero-cost story survives.** No proxy, no key, no per-request spend, works on a plane.
- **Phase 0 and 0.5 — the bulk of the work — are untouched.** They were always keyboard mechanics.

The memory ceiling gets **tighter, not different**: 25 MB design / 20 MB alarm, `mmap` everything, five destructive measurements to replace the guess.

**The architecture is now:**

```
INSTANT (per keystroke, no network, no Full Access, microseconds)
  UITextChecker · UILexicon · NLTokenizer · NLLanguageRecognizer(constraints: [en, it, es])

ON-DEVICE TRANSLATION (iOS 26.0, .lowLatency, packs downloaded by the host app)
  TranslationSession(installedSource:target:)   EN->ES, IT->ES

BUNDLED DETERMINISTIC TEACHING (mmap'd, authored at build time by a frontier LLM)
  focus selection      · scoring function over frequency x cognate distance x FSRS state
  surface -> lemma     · ~380k-form Spanish morphology table, ~4 MB on disk, ~0 resident
  gloss                · Wiktionary-derived, sense-checked by translator alignment
  grammar explanation  · ~200 hand-authored cards keyed on construction id
  correction           · gender/number agreement + IT-interference list + UITextChecker(es)
  recall prompts       · precomputed multiple-choice items and distractors

ESCALATION (V1.1, explicit tap only, one sentence, opt-in, consent-gated)
  remote LLM  <- the only rung that touches the network
```

Written against a single `TeachingEngine` protocol so that if the device ever changes, the implementation swaps and nothing above it does.

**The three actions that matter most, in order:**
1. **The 30-minute keyboard-extension translation probe on a real iPhone 13.** If `TranslationSession` cannot run in an extension, the keyboard cannot translate and the product becomes the Share Sheet app. Everything else is downstream.
2. **The five-run memory measurement.** Converts the project's largest UNVERIFIED into a number.
3. **`LanguageAvailability().status(from: it, to: es)`** on the same device, same session. Three outcomes, three designs — one of them is "drop Italian from V1."

**The product thesis is unchanged and the product risk is unchanged.** What changed is that the teaching layer is now **data you author** rather than **a model you prompt** — which is more work up front, less work at runtime, cheaper, faster, more private, and, for the specific job of teaching one adult bilingual peninsular Spanish through their own messages, almost certainly better.
