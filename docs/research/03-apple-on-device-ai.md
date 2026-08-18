# Research 03 — Apple On-Device AI & Language Stack

> Source: research subagent, 2026-08-18. PRD §8, §9, §15, §21 under test.
> Confidence: **[C]** confirmed with URL + date · **[L]** likely (strong indirect evidence) · **[U]** unverified
>
> **This is the most architecturally consequential of the seven reports. It inverts the PRD's
> local/remote split.**

---

## 0. The three gating facts (read these first)

| Fact | Detail | Confidence |
|---|---|---|
| Foundation Models runs **out-of-process** | "The on-device foundation model and the inference resources are managed centrally by the operating system and shared by all Apple Intelligence system features, so the increase to your app's memory usage will be **very minimal**." — Apple DTS, Jul '25 | **[C]** [forums/thread/795044](https://developer.apple.com/forums/thread/795044) |
| A keyboard extension **can** call it with `RequestsOpenAccess: false` | `bogdanripa/llm-keyboard` ships a `LanguageModelSession` inside a `com.apple.keyboard-service` extension whose Info.plist has `RequestsOpenAccess` = `false`. README: "no Full Access, no network, no data collection. Inference runs in Apple's system process, so the model doesn't count against the keyboard extension's memory cap." | **[C]** repo config verified; **[L]** as a runtime guarantee (not device-tested here) |
| Full Access is still required — but for **other** reasons | Apple's current doc, non-open-access keyboards: "**No access to microphone and speaker**" and read-only access to the containing app's shared containers | **[C]** [Configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) |

**Consequence: the PRD's Full-Access justification is wrong in its *reason*.** Full Access is not needed for AI. It is needed for (a) **speaking Spanish out loud** and (b) **writing the learning state to the App Group**. Both are P0 in the PRD. **Network becomes optional.**

---

## 1. Foundation Models framework

### API surface **[C]** (developer.apple.com/documentation/foundationmodels, fetched 2026-08-18)

- `SystemLanguageModel.default` / `SystemLanguageModel(useCase:)` (`.general`, `.contentTagging`)
- `LanguageModelSession` -> `respond(to:)`, `respond(to:generating:options:)`, `streamResponse(to:generating:)`, `prewarm()`, `init(model:tools:transcript:)`
- Guided generation: `@Generable`, `@Guide(description:)`, `.minimum/.maximum/.minimumCount/.maximumCount`, `GenerationSchema`, `DynamicGenerationSchema`
- `Tool` protocol (tool calling), `GenerationOptions(temperature:maximumResponseTokens:)`
- Errors: `assetsUnavailable`, `exceededContextWindowSize`, `guardrailViolation`, `rateLimited`, `refusal`, `concurrentRequests`, `unsupportedLanguageOrLocale`

**iOS 27 (WWDC26, June 8 2026)** — visible in live docs as new/beta topic groups **[C]**:
- **Custom LLM provider**: `LanguageModel`, `LanguageModelExecutor`, `LanguageModelCapabilities` — any provider (cloud, MLX, Core AI) can back a `LanguageModelSession`. Session 339 "Bring an LLM provider to the Foundation Models framework."
- **Multimodal prompts**: `Attachment`, `ImageAttachmentContent`, `ImageReference`
- **Dynamic profiles**: `DynamicProfile`, `DynamicInstructions`, `Profile`
- **PCC**: `PrivateCloudComputeLanguageModel` + `com.apple.developer.private-cloud-compute` managed entitlement
- `GenerationError` **deprecated at 27.0** -> `LanguageModelError`
- **[L]** AFM 3 family: "AFM 3 Core" 3B dense + "AFM 3 Core Advanced" 20B sparse (1-4B active), the latter gated to iPhone Air / 17 Pro / 17 Pro Max (12 GB). Multiple secondary sources; Apple ML Research page was egress-blocked, so the 20B/device mapping is **[L]** not **[C]**.

### Context window

**4096 tokens** total per session (instructions + prompt + tool schemas + `@Generable` schemas + output). **[C]** — [managing-the-context-window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window):

| | `SystemLanguageModel` | `PrivateCloudComputeLanguageModel` |
|---|---|---|
| Works offline | yes | no |
| Usage limits | Unlimited | Limit per day (iCloud+ upgradeable) |
| Reasoning | Not supported | Multiple levels |
| Context size | **4K** | **32K** |

- `SystemLanguageModel.contextSize` (iOS 26.0) and `tokenCount(for:)` (**iOS 26.4**) allow runtime measurement. **[C]**
- 4K is *plentiful* here: one sentence + a ~40-word known-vocab list + a compact `@Generable` schema is ~300-600 tokens.

### Performance

~**30 tokens/s** generation, ~**0.6 ms/prompt-token** TTFT on iPhone 15 Pro (Apple ML Research, pre-speculation). **[L]** (retrieved via search snippet; page egress-blocked).
-> A 60-token structured answer ~= **2 s**, which **misses the PRD's <1.5 s target (§22) unless you stream.** Streaming + `prewarm()` is mandatory.

### Devices

iPhone 15 Pro / 15 Pro Max and all iPhone 16 / 17 series (A17 Pro+, 8 GB). iPhone 15 / 15 Plus and earlier: no. **[L]** Check `SystemLanguageModel.default.availability` -> `.unavailable(.deviceNotEligible / .appleIntelligenceNotEnabled / .modelNotReady)`. **[C]**

### Languages

Apple Intelligence languages include **English, Spanish, Italian**, French, German, Portuguese (BR), Chinese, Japanese, Korean. **[L]**
API: `supportsLocale(_:)` and `.supportedLanguages` (iOS 26.0). **[C]**
Apple's own multilingual guidance **[C]**:
- Put the target language in `Instructions`, using the literal phrase `"The person's locale is \(locale.identifier)."` — "This special phrase comes from the model's training, and reduces the possibility of hallucinations in multilingual situations."
- "You MUST respond in Italian and be mindful of Italian spelling, vocabulary, entities, and other cultural contexts of Italy."
- `@Generable` property **names are model inputs** — name them `spanish`, `lemma`, `meaningItalian`, not `f1`.
- **Guardrails only apply to supported languages**; short mixed-in unsupported-language fragments can slip past both detection and guardrails.

### Rate limiting / foreground — **the trap**

- iOS 26 doc: `rateLimited` "will only happen if your app is running in the **background**." **[C]**
- Apple DTS Jun '25: "rate limiting applies when your device is on battery **AND** when your process is running in the background. Safari extensions run in the background… we recommend **not** streaming the responses… Instead, call `respond`." **[C]** [forums/thread/789788](https://developer.apple.com/forums/thread/789788). A developer reported throttling after **4 requests spaced 30 s apart**.
- iOS 27 `LanguageModelError.rateLimited` drops the background-only wording: "too many requests in a short window… space your requests or reduce system load." **[C]** — i.e. the limit got *broader*, not narrower.
- **Is a keyboard extension "background"?** **[U]**. It is on-screen but is not the foreground app's process. Safari extensions are the closest precedent and they *are* treated as background. Two shipping keyboards do it anyway (azooKey streams; LLM Keys uses non-streaming `respond` with a 350 ms debounce). **Design for it:** debounce >=350 ms, one in-flight request, cancel on keystroke, cache aggressively, always handle `rateLimited` by silently suppressing the suggestion.
- Also: parallel calls **serialize on the ANE** even though multiple sessions are allowed **[C]**; and each session handles one request at a time.

### Real-world proof inside keyboard extensions

| Repo | Evidence | Notes |
|---|---|---|
| `bogdanripa/llm-keyboard` (LLM Keys) | `Keyboard/LLMPredictor.swift` — `@Generable struct TypingAssist`, `GenerationOptions(temperature: 0.3)`, `session.prewarm()`, context clipped to `context.suffix(400)`, session replaced after each request to keep it stateless | `RequestsOpenAccess: false`; EN/ES/FR/DE/IT/PT; deployment target iOS 17 with `-weak_framework FoundationModels` |
| `azooKey/azooKey` (App Store, JP) | `Keyboard/Display/InputManager.swift` — `SystemLanguageModel(useCase: .general)`, `session.streamResponse(to:generating: EmojiSuggestion.self)`, context `leftText.suffix(120)` | `RequestsOpenAccess: true` |

Both are directly relevant patterns. **[C]** (source verified).

---

## 2. Translation framework

| Item | Finding | Conf |
|---|---|---|
| Framework | iOS **17.4**+ (`translationPresentation`), `LanguageAvailability` iOS **18.0**+ | **[C]** |
| **Headless (no UI)** | `TranslationSession.init(installedSource:target:)` — "for contexts where there's **no UI**" — **iOS 26.0+**, *not* 18. Throws if the pair isn't already installed | **[C]** [doc](https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:)) |
| Privacy | "**All translations using the `TranslationSession` class are processed on the user's device.** Apple may collect API usage and performance metrics including the app bundle ID and the original and translated language, but this data does **not** include the original or translated content." | **[C]** |
| Pack download | `prepareTranslation()` (iOS 18) prompts for download — **requires a SwiftUI `.translationTask` context**, so it must run in the **host app**, not the keyboard | **[C]** |
| iOS 26.4 strategy | `init(installedSource:target:preferredStrategy:)` + `LanguageAvailability(preferredStrategy:)`. `.highFidelity` = Apple Intelligence models, `.lowLatency` = traditional models on all devices. Critically: "**When Apple Intelligence is enabled, these models are already downloaded, so translation is immediately available without prompting the person to download languages.**" | **[C]** |
| Availability check | `await LanguageAvailability().status(from:to:)` -> `.installed` / `.supported` / `.unsupported` | **[C]** |
| Extension support | No documented prohibition; no `NS_EXTENSION_UNAVAILABLE`. Same XPC-to-system-daemon shape as Foundation Models | **[U]** — must be smoke-tested in a keyboard target |
| EN->ES | Certain. Both first-tier Apple Translate languages | **[L]** |
| **IT->ES** | Apple Translate supports arbitrary pairs among supported languages, and IT + ES are both supported, so `status(from: it, to: es)` should be `.supported`. Whether it is a **direct** model or an EN pivot is undocumented | **[L]** |

**Verdict: the single most important, most under-rated finding for this PRD.** From iOS 26 you get a **headless, on-device, no-network, no-Full-Access, no-API-key translation engine**. On iOS 26.4+ with Apple Intelligence on, there is not even a download prompt. **This alone deletes the PRD's #1 remote operation.**

---

## 3. Natural Language framework

**Extension safety:** pure in-process C/ML, no XPC, no entitlements. Works in a keyboard, no Full Access. `NLTagger`/`NLLanguageRecognizer` are small; `NLEmbedding` is **not**. **[L]**

### `NLLanguageRecognizer` — EN vs IT on a partial sentence

- API: `processString(_:)` -> `dominantLanguage`, `languageHypotheses(withMaximum:)`, plus `languageConstraints` and `languageHints`. **[C]**
- Apple's doc explains the two-stage method: dominant *script* first, then language — and EN/IT share Latin script, so all the work falls on stage 2. **[C]**
- **No published accuracy numbers exist for Apple's recognizer.** None found from Apple or any credible benchmark. **[U]**
- Reasoning + community reports **[L]**: reliability is poor at 1-2 tokens, acceptable from ~3-5 content words. EN/IT is a comparatively *easy* pair (Italian's high-frequency function words — `il/la/di/che/non/per/sono/una` — and vowel-final morphology are strong cheap signals), much easier than ES/IT or ES/PT.

**Concrete recommendation, replacing PRD §9's vague "reasonable minimum amount of text":**
1. Always set `recognizer.languageConstraints = [.english, .italian]` — converts an open-set problem (~50 languages) into a binary one and **is the single biggest accuracy win available. PRD §9 does not mention it.**
2. Use `languageHypotheses(withMaximum: 2)`; require the winner's probability **>= 0.75** *and* a **>= 0.25 margin** over the runner-up.
3. Require **>= 3 word tokens / >= 12 characters** before the state may change at all.
4. Add **hysteresis**: two consecutive agreeing evaluations to flip; never flip mid-word.
5. Seed `languageHints` from recent history (e.g. `[.italian: 0.6, .english: 0.4]`).
6. Cheap deterministic override: a ~200-entry Italian function-word/diacritic list (`perché`, `già`, `più`, `è`, `gli`, `sono`, `anche`) — one hit is worth more than the classifier on 3 words.

### `NLTagger` lemmatization

- `.lemma` scheme exists since iOS 12; support is **per-language and per-device**, queried with `NLTagger.availableTagSchemes(for: .word, language:)`. **[C]**
- **English confirmed**: reported schemes for English include `Lemma`. Japanese returns only `Language, Script, TokenType`. **[L]**
- **Spanish and Italian: UNVERIFIED.** **[U]** No authoritative list found. They are inherited from `NSLinguisticTagger`, whose lemma support historically covered the major Latin-script European languages, so they are probable — but this is exactly the sort of thing that silently returns `nil`.
  - **Action: a 5-minute empirical test.** Log `NLTagger.availableTagSchemes(for: .word, language: .spanish/.italian/.english)` on a real device on day one and gate the design on the result.
  - **Note:** the doc calls `.lemma` a "**stem** form" ("the stem of 'reading' is 'read'"). Even where present, do not assume clean dictionary citation forms for Spanish verb morphology (`llegaré` -> `llegar`). For a Spanish SRS keyed on lemmas this matters a lot. **Foundation Models with a `@Generable` `lemma: String` field is far more reliable for Spanish conjugation**, and is what the PRD's §15 response schema already implies.

### `NLEmbedding`

- Built-in **word** embeddings for exactly **7 languages: English, Spanish, French, Italian, German, Portuguese, Simplified Chinese** — all three of yours. **[L]** (WWDC19 session 232)
- API: `NLEmbedding.wordEmbedding(for: .spanish)`, `neighbors(for:maximumCount:distanceType:)`, `distance(between:and:)`, `vocabularySize`, `dimension`. **[C]**
- **Memory risk in a keyboard.** These are real embedding tables (hundreds of thousands of vectors); loading one materially moves an extension that has only tens of MB. **[U]** on exact resident cost — **measure with `os_proc_available_memory()` before and after** and be ready to move it into the host app.
- Useful for: "is this Spanish word near one the user already knows" (difficulty scoring), semantic distractors for recall exercises. Not for translation.

### Tokenization

`NLTokenizer(unit: .word / .sentence)` — locale-correct sentence splitting for §17's trigger engine, negligible cost. Prefer it over regex on punctuation. **[C]**

---

## 4. Speech synthesis from a keyboard extension

| Question | Answer | Conf |
|---|---|---|
| Does it work in a keyboard extension? | **Yes.** `yuetyam/jyutping` (App Store, Cantonese) has `Keyboard/Speech/Speech.swift` using `AVSpeechSynthesizer` directly in the keyboard target, guarded with `#available(iOSApplicationExtension 26.0, *)` | **[C]** source verified |
| **Does it need Full Access?** | **Yes.** Apple's open-access doc lists, for keyboards *without* open access: "**No access to microphone and speaker**." And jyutping's `Keyboard/Info.plist` sets `RequestsOpenAccess` = `true` | **[C]** doc + config |
| AVAudioSession category needed? | Not necessarily. jyutping configures **none**. The recommended keyboard-safe move is `synthesizer.usesApplicationAudioSession = false`, which makes "the system create a **separate** audio session to automatically manage speech, interruptions, and mixing and **ducking** the speech with other audio sources" | **[C]** [doc](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/usesapplicationaudiosession) |
| Does it duck/interrupt the host app? | With `usesApplicationAudioSession = false`, the system ducks other audio and restores it — correct for a keyboard. With the default `true`, you are mutating the **host app's** session from inside its keyboard, which is user-hostile and has a long tail of bugs (notably: AVSpeechSynthesizer activates the session but historically did **not** deactivate it, leaving other audio permanently ducked). **Set it to `false`** | **[C]** doc / **[L]** bug history |
| Silent mode | Behaviour follows the session category. A system-managed speech session is generally not silenced by the Ring/Silent switch (long-standing complaint). **Assume it will speak in silent mode**, and add your own "respect silent switch" setting — a keyboard that blurts Spanish in a meeting is an uninstall | **[L]** |
| Enhanced / Premium voices | `speechVoices()` returns only voices **actually downloaded**. Preinstalled = `.default` quality. `.enhanced`/`.premium` are 100 MB+ each and must be pulled manually via **Settings > Accessibility > Live Speech > Voices**. **No API to trigger the download** (open radar) | **[L]** |
| Personal Voice | `requestPersonalVoiceAuthorization`. Irrelevant — Personal Voice clones the *user's* voice; you want a native `es-ES`/`es-MX` speaker | **[C]** |
| Fine control | `AVSpeechSynthesisIPANotationAttribute` on an `NSAttributedString` forces exact pronunciation — jyutping uses this. Handy for teaching a specific Spanish phoneme | **[C]** |

**Design consequence:** onboarding must (a) request Full Access *and* (b) deep-link the user to Settings to download an enhanced `es-ES` voice, then check `speechVoices().filter { $0.language.hasPrefix("es") }` and fall back to `.default` with a nudge.

---

## 5. `UITextChecker` / `UILexicon`

Both are **available without Full Access** and are the correct instant tier under any LLM. **[C]**

- `UILexicon` via `requestSupplementaryLexicon(completion:)` — "can be called **only** from a custom keyboard app extension." Contains: unpaired first/last names from the **Address Book**, the user's **Settings > General > Keyboard > Text Replacement** shortcuts, and a **common words dictionary**. Entries are `userInput` -> `documentText` pairs (`"iphone"` -> `"iPhone"`). Apple: treat as *supplementary* to your own lexicon. **[C]**
  - Apple explicitly lists "Access to a common words lexicon" and "Access to the text shortcuts list" as available **with `RequestsOpenAccess = false`**. **[C]**
  - **Privacy:** it carries contact names. Fine locally; **it must never be included in anything sent to a remote API. PRD §21 should say so.**
- `UITextChecker.completions(forPartialWordRange:in:language:)` — returns completions ordered most-probable-first; `UITextChecker.availableLanguages` returns the installed set **in user-preference order**. **[C]**
  - **Quality is dictionary-lookup, not a language model.** Prefix-matched wordlist: no context, no next-word prediction, no grammar. Fine for `esp` -> `español`; useless for "what word comes next." **[L]**
  - Coverage for `es`/`it` depends on which system keyboards/dictionaries the *user* has installed — **not** on your keyboard. Check at runtime and degrade. **[L]**
  - Also use `rangeOfMisspelledWord(...)` + `guesses(forWordRange:...)` for Mode E as a free, instant first pass before invoking any model.
- `LLM Keys` uses exactly this two-tier shape: `UITextChecker`/`UILexicon` per keystroke, `LanguageModelSession` on a 350 ms debounce. **Adopt it.** **[C]**

---

## 6. Writing Tools / Apple Intelligence surfaces

- Writing Tools is a **consumer-side** API: `writingToolsBehavior` on `UITextView`/`UITextField`/`UITextInputTraits`, and `UIWritingToolsCoordinator` (public since iOS 18.2) for custom text engines. **[L]**
- **A third-party keyboard gets nothing.** The keyboard does not own the host app's text view; it holds only a `UITextDocumentProxy`. There is no API to invoke Writing Tools on the host's field, and no keyboard-facing Apple Intelligence surface. **[L]**
- Genmoji, Image Playground, Smart Reply are likewise app-side.
- **The keyboard's Apple Intelligence access is Foundation Models and Translation. That's the whole list.**

---

## 7. Core ML / MLX on-device NMT — don't

| Option | Size | Verdict |
|---|---|---|
| **Bergamot / Firefox Translations** tiny student (Marian, int8, + lexical shortlist) | **~15 MB per direction**; en-es **BLEU 35.0** | The only family that could physically fit **[L]** |
| Helsinki-NLP OPUS-MT bilingual (Marian) | ~**298 MB** fp32; a converted Core ML *encoder alone* measured **209 MB**; ~75-80 MB at int8 | Too big for a keyboard **[L]** |
| NLLB-200-distilled-600M | ~2.4 GB fp32; ~600-700 MB int8 | Not remotely viable **[L]** |

**IT->ES caveat:** Firefox Translations ships **English-pivot** pairs only (`xx<->en`). There is no direct `it-es` model — you would run `it->en->es`: **two** models, ~30 MB, two decoder passes, compounding error. **[L]**

**Why it fails in a keyboard extension anyway:**
- Core ML weights load **into your process** and count fully against the jetsam limit. A developer reported jetsam killing a Network Extension over a **400 KB** Core ML model. **[L]** ([forums/thread/680453](https://developer.apple.com/forums/thread/680453))
- The keyboard ceiling is **undocumented by Apple**; community-reported at **~48-60 MB `phys_footprint`**. **[L]/[U]**. The failure mode is the problem: **jetsam kills silently — no crash log, no signal — and iOS switches the user back to their previous keyboard.**
- `com.apple.developer.kernel.increased-memory-limit` is documented for **apps**, not extensions, and cannot raise a keyboard's ceiling. **[C]**
- MLX on iOS is app-scale. Irrelevant to a keyboard. **[L]**

**The host-app + App Group variant** is technically possible, practically bad: the host app is **not running** while the user types in WhatsApp; there is no supported way for a keyboard to wake its container app in the background; and without Full Access the keyboard **cannot write** the request into the App Group at all.

**Conclusion: Core ML / MLX NMT is strictly dominated by the Translation framework** — ~0 MB in-process, no download management, no conversion pipeline, Apple-quality output, and a real IT->ES path. Do not build it. **If iOS 27's `LanguageModelExecutor` tempts you to plug a custom model into a `LanguageModelSession`, note it would run *in-process* and reintroduce every memory problem above.**

---

## 8. Capability matrix

| PRD capability | On-device in 2026? | How | Full Access? | Conf |
|---|---|---|---|---|
| Keyboard render, keypress, caps state (§8) | YES | UIKit / KeyboardKit | No | **[C]** |
| Instant completions per keystroke (§24) | YES | `UITextChecker.completions` + `UILexicon` | No | **[C]** |
| Source language detection EN vs IT (§9) | YES | `NLLanguageRecognizer` + `languageConstraints` + hysteresis | No | **[C]** |
| Sentence/phrase segmentation (§17, §18) | YES | `NLTokenizer` | No | **[C]** |
| **EN->ES translation (§8 "remote")** | **YES** | `TranslationSession(installedSource:target:)`, iOS 26+ | **No** | **[C]** API / **[U]** in-extension |
| **IT->ES translation (§8 "remote")** | **YES probable** | same; verify `LanguageAvailability.status(from:.italian,to:.spanish)` | **No** | **[L]** |
| **Focus-word / lemma / meaning / explanation (§15)** | **YES** | Foundation Models `@Generable` | **No** | **[C]** API / **[L]** quality |
| **Alternative natural phrasing (§8)** | YES | Foundation Models | No | **[L]** |
| **Spanish correction, Mode E (§11)** | YES | `UITextChecker(es)` first pass + Foundation Models | No | **[L]** |
| **Active-recall prompt generation (§8)** | YES | Foundation Models | No | **[L]** |
| Difficulty / semantic-neighbour scoring (§14) | YES | `NLEmbedding(.spanish)` — watch memory | No | **[L]** |
| Lemma without an LLM | MAYBE | `NLTagger(.lemma)` — **verify es/it on device** | No | **[U]** |
| **Pronunciation audio (§12 P0)** | YES | `AVSpeechSynthesizer`, `usesApplicationAudioSession = false` | **YES** | **[C]** |
| **Keyboard writes learning state to App Group (§19)** | YES | shared container | **YES** | **[C]** |
| Enhanced `es-ES` voice | MAYBE | user must download in Settings; no API | **YES** | **[L]** |
| Long multi-turn tutoring, >4K context, real reasoning | NO | PCC (32K, entitlement, daily cap, online) or your own API | **YES** | **[C]** |
| Nuanced idiom/register judgement, rare-construction explanation | NO probable | frontier model | **YES** | **[L]** |
| Writing Tools integration | NO | no keyboard-facing API | — | **[L]** |
| Local NMT via Core ML / MLX | NO | dominated by Translation; jetsam | — | **[L]** |

**Genuinely remote-only:** long-context tutoring, cross-session curriculum reasoning, and the top decile of explanation quality. **That is it.** Everything in the PRD's §8 "Remote operations" list has a credible on-device implementation in 2026.

---

## 9. Corrections to PRD §8 and §9

**§8 is the section that is most wrong.**

1. **"Optional Apple frameworks … may *later* be used" — reverse this.** On-device is now the **default path**; remote is the fallback. The framing dates the document.
2. **"Remote operations: high-quality English->Spanish / Italian->Spanish translation" — false as stated.** `TranslationSession(installedSource:target:)` (iOS 26) is headless, fully on-device, needs no network, no API key, no Full Access, and on iOS 26.4 with Apple Intelligence enabled needs no language-pack download either. **Move this to Local.**
3. **"Local translation fallback" — backwards.** Apple's translator is the **primary**; the remote LLM is the fallback for pre-iOS-26 devices, non-Apple-Intelligence devices, and quality escalation.
4. **Grammar explanations / focus selection / recall prompts are not remote-only.** They are exactly what guided generation is for. §15's response schema maps 1:1 onto a `@Generable` struct with `@Guide` descriptions, and the framework gives "strong guarantees that the model generates instances of your type" — making §15's "strict structured output / no markdown / no conversational filler" a *type-system* guarantee rather than prompt-and-pray.
5. **Missing constraint: the 4096-token context window.** §15's `knownVocabulary` array is unbounded. Cap it — ~30-50 lemmas max, or better, send only the lemmas present in *this* sentence.
6. **Missing: `@Generable` property names and `@Guide` text are model input and consume context.** Rename and trim accordingly.
7. **Missing: device eligibility.** Foundation Models needs iPhone 15 Pro+ with Apple Intelligence on. `availability` must be a first-class product state alongside "no Full Access" and "no network" in §23.
8. **Missing: latency reality.** ~30 tok/s means a 60-token structured response ~= 2 s — over §22's 1.5 s budget. Requires `prewarm()` at `viewDidAppear`, `streamResponse` with partial rendering, and a session recycled per request (LLM Keys' pattern) so the transcript never accumulates.
9. **Missing: rate limiting.** `rateLimited` is a routine, expected condition, not an error state. Debounce >=350 ms, one in-flight request, cancel-on-keystroke, cache normalized requests.
10. **§21 is now materially wrong in the user's favour.** The onboarding copy — "iOS requires Full Access for network-backed AI features and this technically permits the keyboard to transmit typed text" — should be rewritten: **translation and teaching never leave the device; Full Access is required for pronunciation audio and for saving your progress to the app.** A much stronger privacy story and a much easier consent ask.
11. **Hidden architectural blocker the PRD does not mention:** without Full Access a keyboard has **read-only** access to the App Group. §19's persistence design and §20's Screen 4 (Review) therefore **cannot work** without Full Access, independent of any AI decision. §23's "No Full Access -> keyboard remains fully usable for typing" is true but understates the loss: **no progress is saved.** Decide now whether the no-Full-Access mode keeps a keyboard-local store that is later migrated, or is genuinely read-only.

**§9 corrections:**
- Rule 1 "use local language recognition first" -> specify `NLLanguageRecognizer` **with `languageConstraints = [.english, .italian]`.** The highest-leverage line missing from the document.
- Rule 2 "a reasonable minimum amount of text" -> make it testable: >=3 word tokens / >=12 chars, top hypothesis >=0.75, margin >=0.25.
- Rule 3 "avoid oscillating on short words" -> two-consecutive-agreeing-evaluations hysteresis plus a diacritic/function-word override list; never re-evaluate mid-word.
- Add: seed `languageHints` from recent per-app history.
- Add: `Locale.preferredLanguages` and the host field's `UITextDocumentProxy.documentInputMode?.primaryLanguage` are free priors.

---

## 10. Privacy and cost implications

**Privacy.** The architecture flips from "minimize what we send" to "**send nothing**." Typed text never leaves the device for translation, teaching, correction, or recall generation. Apple's own note is quotable in onboarding: `TranslationSession` translations "are processed on the user's device… this data does not include the original or translated content." Foundation Models is offline with **unlimited** usage. The App Store privacy nutrition label can plausibly read *no data collected*. **That is a genuine differentiator against every AI keyboard on the store, all of which proxy keystrokes to a server.**

**Cost.** Remote inference goes from a per-user recurring cost to ~zero. On-device: **$0/user, no backend, no key, works on a plane.** §7's whole "API-key strategy" becomes optional infrastructure for a V2 quality-escalation path rather than V1 critical path.

**The trade you are actually making.** You give up frontier-model explanation quality for a 3B model's. For "explain why *llegaré* is future tense of *llegar* in one sentence," a 3B model is fine. For subtle register and idiom coaching, it is not. The right shape is a **quality escalation ladder**, not a local/remote binary:

```
UITextChecker/UILexicon  ->  Translation (on-device)  ->  Foundation Models (on-device, @Generable)
                                                      ->  [optional] user-initiated "explain more"
                                                          -> PCC or your API
```

Only the last rung touches the network, only on explicit user action, and only for one sentence — which satisfies §21's "send the smallest useful unit of text" **by construction**.

---

## 11. Recommended PRD changes (concrete)

1. **Raise the deployment target to iOS 26.0** for the AI feature set (keep iOS 17/18 for a dumb-keyboard fallback via `-weak_framework FoundationModels`, as LLM Keys does). The PRD's "iOS 18+" header is the wrong floor: **headless `TranslationSession` is 26.0.**
2. **Rewrite §8** into three tiers: Instant (UIKit/NL), On-device AI (Translation + Foundation Models), Escalation (remote, opt-in).
3. **Promote on-device AI from "Phase 4 / P2" to Phase 1.** §26 Phase 1 "Translation MVP" should be built on `TranslationSession`, not the remote API. **It is less work, not more.**
4. **Reframe Full Access** in §21/§23 around *audio* and *progress saving*, not network.
5. **Add a day-1 device-probe task** logging, on a real iPhone from within the keyboard target: `os_proc_available_memory()` before/after each framework load; `SystemLanguageModel.default.availability`; `NLTagger.availableTagSchemes(for:.word,language:)` for en/es/it; `await LanguageAvailability().status(from:.italian,to:.spanish)`; `TranslationSession(installedSource:target:)` inside the extension; `UITextChecker.availableLanguages`; `AVSpeechSynthesisVoice.speechVoices()` filtered to `es`. **Every [U] in this report resolves in one afternoon.**
6. **Study the two reference keyboards** before writing code: `bogdanripa/llm-keyboard` for the debounce/prewarm/stateless-session/no-Full-Access pattern, and `azooKey/azooKey` for streaming + `@Generable` inside a shipping App Store keyboard.

---

## Sources

[Foundation Models framework](https://developer.apple.com/documentation/foundationmodels) · [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window) · [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) · [Supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models) · [Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute) · [Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions) (all fetched 2026-08-18)

Forums: [795044](https://developer.apple.com/forums/thread/795044) (memory attribution, Jul '25) · [789788](https://developer.apple.com/forums/thread/789788) (rate limit in app extensions, Jun '25) · [803444](https://developer.apple.com/forums/thread/803444) · [680453](https://developer.apple.com/forums/thread/680453) (Core ML in an extension)

[Translation framework](https://developer.apple.com/documentation/translation) · [TranslationSession](https://developer.apple.com/documentation/translation/translationsession) · [init(installedSource:target:)](https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:)) · [LanguageAvailability](https://developer.apple.com/documentation/translation/languageavailability)

[NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer) · [Identifying the language in text](https://developer.apple.com/documentation/naturallanguage/identifying-the-language-in-text) · [NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding) · [WWDC19 232](https://developer.apple.com/videos/play/wwdc2019/232/)

[AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer) · [usesApplicationAudioSession](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/usesapplicationaudiosession) · [AVSpeechSynthesisVoice](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice)

[Configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) · [Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard) · [UILexicon](https://developer.apple.com/documentation/uikit/uilexicon) · [UITextChecker.completions](https://developer.apple.com/documentation/uikit/uitextchecker/completions(forpartialwordrange:in:language:)) · [increased-memory-limit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit)

[bogdanripa/llm-keyboard](https://github.com/bogdanripa/llm-keyboard) · [azooKey/azooKey](https://github.com/azooKey/azooKey) · [yuetyam/jyutping](https://github.com/yuetyam/jyutping) · [react-native#31910](https://github.com/facebook/react-native/issues/31910)

[Firefox Translations models](https://hacks.mozilla.org/2022/06/training-efficient-neural-network-models-for-firefox-translations/) · [Bergamot, EMNLP 2021](https://aclanthology.org/2021.emnlp-demo.20.pdf) · [Apple on-device and server foundation models](https://machinelearning.apple.com/research/introducing-apple-foundation-models) · [Third generation of Apple's foundation models](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models) · [WWDC26 339: Bring an LLM provider to Foundation Models](https://developer.apple.com/videos/play/wwdc2026/339/)
