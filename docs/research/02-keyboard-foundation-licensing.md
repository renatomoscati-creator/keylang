# Research 02 — Keyboard UI Foundation & Licensing

> Source: research subagent, 2026-08-18. Facts below were verified by cloning the repos and
> unzipping the shipped 10.8.0 XCFramework, not by reading marketing pages.
> **Egress caveat:** `keyboardkit.com`, `docs.keyboardkit.com`, `gumroad.com`, `web.archive.org`
> were blocked (403 on CONNECT). Pricing figures are LIKELY, not CONFIRMED.

**Headline: PRD §5 is materially wrong.** KeyboardKit is no longer "open source with a paid Pro add-on." Since **2025-08-31** the entire framework is **closed-source**, shipped as a **binary XCFramework**, gated at runtime by **LicenseKit**. There is no free autocomplete/autocorrect engine at all — `autocomplete` is a license-gated `ProFeature` and the constructor literally `throws` without a license.

---

## 1. KeyboardKit — current state

### 1.1 Version, cadence, targets

| Fact | Value | Status |
|---|---|---|
| Latest release | **10.8.0**, tagged **2026-08-17** (yesterday) | CONFIRMED - `git ls-remote`, releases page |
| Cadence | 30 tagged releases in 10.x since 10.0.0 (2025-09-29) -> ~1-3/month, no gap >6 weeks | CONFIRMED |
| Last commit on `main` | `752fe3da` "Update package to 10.8", 2026-08-17 | CONFIRMED |
| Deployment targets | **iOS 16, macOS 13, tvOS 16, watchOS 10, visionOS 1** | CONFIRMED - `Package.swift` @ 10.8.0 |
| Swift / UI | swift-tools 5.9, SwiftUI-first | CONFIRMED |
| Repo stats | ~1.9k stars, 297 forks, 32 open issues | CONFIRMED |
| Major-version history | 8.0 -> 2023-10-30; 9.0.0 -> 2024-12-02; 10.0.0 -> 2025-09-29 | CONFIRMED |

**Public commit counts are no longer a health signal.** The repo dropped from 44 commits (2025-07) to 1-8/month in 2026 **because there is no source in it anymore** — only `Package.swift`, `Demo/`, `LICENSE`, `README.md`, `RELEASE_NOTES.md`. `Sources/` contains **0 files** (CONFIRMED: `git ls-tree -r HEAD -- Sources` -> empty). Maintenance happens in a private repo.

### 1.2 Licensing — the actual situation

**LICENSE on `main` (CONFIRMED, fetched 2026-08-18):**

> Closed Source License
> Copyright (c) 2016-2026 Kankoda Sweden AB
> **KeyboardKit (hereby referred to as "the Software") is closed-source.**
> The Software is free to start using and has commercial pro features that require a valid license to be used.
> …The source code must not be distributed to or used by other individuals, teams or companies… Any attempts to work around these limitations or to circumvent the security mechanisms of the Software, or any attempts to reverse engineer the software, will be considered as an attempt to violate the license agreement…

**Exact date of the license flip (CONFIRMED via `git log -- LICENSE` on a full clone):**

| Commit | Date | License |
|---|---|---|
| `1a825711` | 2023-12-05 | MIT |
| `aa96f4bf` | 2025-04-01 | MIT |
| **`6d5757ae`** | **2025-08-31** | **Closed Source** (buried in a commit titled "Update deployment targets") |
| `22d43505` | 2025-10-12 | Closed Source, copyright reassigned to **Kankoda Sweden AB** |
| `4b6fb690` | 2026-01-06 | Closed Source (2026) |

**Last MIT-licensed release = 9.9.0 / 9.9.1** (commit `a7e33ac2`, 2025-08-23). CONFIRMED.

**Distribution model (CONFIRMED — `Package.swift` @ 10.8.0):**
```swift
.binaryTarget(name: "KeyboardKit",
  url: "https://github.com/KeyboardKit/KeyboardKit-Binaries/releases/download/10.8.0/KeyboardKit.zip",
  checksum: "dcdad4ba..."),
.target(name: "KeyboardKitDependencies", dependencies: ["LicenseKit"], path: "Dependencies")
```
- 9.0 MB zip -> **51 MB xcframework on disk**; device slice (`ios-arm64`) = 18 MB, Mach-O binary **5.3 MB**, plus `Assets.car` and 64 `.lproj` bundles. CONFIRMED (downloaded and unzipped).
- README: *"Since KeyboardKit is a binary framework, it must only be linked to the main app target."* CONFIRMED.
- **10.0 merged KeyboardKit + KeyboardKit Pro into one SDK.** `KeyboardKit/KeyboardKitPro` is **archived**: *"This repository is not used in KeyboardKit 10!… will remain accessible until January 2027 but will receive no new releases."* CONFIRMED.

**README contradicts its own LICENSE.** `README.md` on `main` still says *"KeyboardKit provides a free, open-source keyboard engine"* while carrying a `license-closedsource-red` badge and a closed-source LICENSE in the same tree. Any secondary source repeating "open source" is echoing this stale line.

### 1.3 What is Pro-only — definitive

Extracted from the shipped 10.8.0 binary's `.swiftinterface`
(`KeyboardKit.xcframework/ios-arm64/KeyboardKit.framework/Modules/KeyboardKit.swiftmodule/arm64-apple-ios.swiftinterface`, line 5564). **CONFIRMED, verbatim:**

```swift
public enum ProFeature : LicenseKit.LicenseFeature {
  case autocomplete
  case clipboardAddons
  case dictation
  case emojiAddons
  case externalKeyboard
  case fonts
  case fullDocumentContext
  case hostApplication
  case inputSets
  case keyboardLayoutTypes
  case locale(Foundation.Locale)
  case proPreviews
  case remoteAutocomplete
  case settingsScreens
  case textInput
  case themes
}
```

| Feature | Free? | Evidence |
|---|---|---|
| **Autocomplete** | **NO - Pro** | `ProFeature.autocomplete`; `StandardAutocompleteService.init(...) throws`; free default is `DisabledAutocompleteService` (returns `[]`) |
| **Autocorrect** | **NO - Pro** | Same service. `isAutocorrectEnabled`, `shouldAutocorrect(_:)` exist only on `StandardAutocompleteService` |
| **Remote / AI next-word prediction** | **NO - Pro** | `ProFeature.remoteAutocomplete`; `nextWordPredictionRequest: .claude(...)` / `.openAI(...)` |
| **Emoji keyboard** | Partly | `EmojiKeyboard.init` is non-throwing, but `ProFeature.emojiAddons` gates search/categories/skin-tone extras - LIKELY |
| **Localized layouts** | **NO - Pro** | Every `KeyboardLayout.english(for:)`, `.italian`, `.spanish` `throws`. `ProFeature.locale(Locale)`, `.inputSets`, `.keyboardLayoutTypes` |
| **Localized callouts (accented long-press)** | **NO - Pro** for non-English | 9.9 OSS core documents: *"This open-source function will always return standard English actions. The one in KeyboardKit Pro returns localized versions."* CONFIRMED |
| Dictation / Themes / External keyboard / Full document context / Host app ID / In-keyboard text fields / Settings screens | **NO - Pro** | corresponding `ProFeature` cases |
| Base `KeyboardView`, gestures, `KeyboardLayout.standard(for:)`, `.qwerty`/`.numeric`/`.symbolic` input sets, actions, audio+haptic feedback, proxy extensions, `SpacebarDragGestureHandler`, `endSentence`, repeat timer, App Group settings sync, status detection | **YES - free** | non-throwing APIs |

### 1.4 Answer to the critical question

> **Is a native-feeling autocomplete/autocorrect engine available for free?**
> **No. It is fully paywalled, and there is no partial free path.**

The free tier ships `DisabledAutocompleteService` — a stub whose `autocomplete(_:)` returns nothing. It does not even wire up `UITextChecker` for you. `StandardAutocompleteService` (with `registerLexicon(_ lexicon: UILexicon)`, `learnWord`, `ignoreWord`, `shouldAutocorrect`, emoji-colon search, next-character prediction) throws `License.ValidationError.licenseFeatureOrTierRequired(.autocomplete, tier)` without a valid license. **CONFIRMED from the shipped binary.**

Given PRD §24 ("A poor typing experience will kill the product faster than weak AI") and §12 P0 "basic English/Italian suggestions" — **KeyboardKit-free does not satisfy P0. You would be paying to satisfy your own P0.**

### 1.5 Pricing (LIKELY — verify in a browser before budgeting)

| Tier | Price | Includes | Annual |
|---|---|---|---|
| **Basic** | **$50/mo** | autocomplete & autocorrect, iOS only, **1 language** | ~$498/yr (17% off) |
| **Silver** | **$150/mo** | + **5 languages**, AI support, in-keyboard typing, email support | ~$1,494/yr |
| **Gold** | **$500/mo** | + 75+ languages, all pro features, priority support | ~$4,980/yr |
| Business | custom | required if company >$10M/yr or app >$1M/yr; covers multiple apps | - |

Corroboration: the Black Friday 2025 post advertises *"save up to $2,500 if you sign up for the Yearly Gold Plan"* at 50 % off -> Yearly Gold ~= $5,000, consistent with $500/mo -17 %. CONFIRMED-by-arithmetic.

**Per-app, not per-developer.** The demo license file in the repo (base64 JSON, decoded) proves the model — **CONFIRMED, verbatim fields:**
```json
{"license":{"bundleIds":["com.apple.dt.xctest.tool","com.kankoda.LocaleExplore","com.keyboardkit.demo.*"],
 "featureIds":["fonts"], "tier":{"level":2,"name":"Gold"},
 "expirationDate":"2029-12-31T23:00:00Z", "platforms":[{"iOS":{}}]}, "signature":"..."}
```
Licenses are **bundle-ID-locked, expiring, signed**, with per-feature and per-tier gating.

**Cost for LinguaKey specifically:** you need **EN + IT + ES** (3 locales, PRD §12 P0). Basic gives **1 language**. -> **Silver, ~$150/mo / ~$1,494/yr, recurring, for a personal-use app.** That is the decisive economic fact.

### 1.6 Known issues

| Issue | Detail |
|---|---|
| **Extension memory** | Issue #757 "HIGH PRIO: Emoji keyboard allocates too much memory" — demo went **~20 MB -> ~30 MB** on opening the emoji keyboard; hi-res emoji font ~**10 MB/page**; SwiftUI `LazyVGrid` did not deallocate cells on scroll. Closed 2025-09-21. Issue #814 "iOS 18 memory use". Issue #920 "Memory leak in demo app". All CONFIRMED |
| **Framework weight** | 5.3 MB binary + `Assets.car` + 64 locale bundles inside a process whose ceiling is ~48-60 MB `phys_footprint` |
| **Migration churn** | 8.0 -> 9.0 -> 10.0. 10.0 required: upgrade to 9.9 first -> clear all deprecations -> upgrade -> fix migration warnings, with *"Code that triggers a migration warning will not work as expected"*. Callout/layout/style **services were deleted**, replaced by values + view modifiers; init-injection replaced by environment injection. Legacy shims **removed in 10.1** |
| **License-format break** | 10.0: *"KeyboardKit 10 no longer has binary licenses encoded into the binary. You need a license file or a subscription license key. The license files use a new format, which means old license files no longer work."* |
| **iOS 26 / Liquid Glass** | 10.0.4 fixed Liquid Glass color/shift bugs; on iOS 26+ system and input keys share a color and the primary key uses icons instead of text; iOS wraps custom keyboards in a Liquid Glass bottom view |
| **Vendor concentration** | Single developer/company (Daniel Saidi / Kankoda Sweden AB). Closed binary + expiring signed license + no source escrow outside Enterprise = **you cannot patch, fork, or keep building if the vendor stops** |

---

## 2. OpenKeyboardKit — verified

`https://github.com/valomedia/OpenKeyboardKit` — **it exists and is real.** CONFIRMED (cloned 2026-08-18).

| Fact | Value |
|---|---|
| License | **MIT** ("Copyright (c) 2016-2025 Daniel Saidi") |
| Forks upstream at | **`a7e33ac2`, 2025-08-23 = KeyboardKit tag 9.9.0 / 9.9.1** — the last MIT release, exactly as PRD §5 claims |
| Full source | 235 Swift files, **22,732 LOC**, plus 64 `.lproj`, full 3,745-commit history preserved |
| Last activity | **2026-07-14** (PR #3 merged) |
| Deployment | iOS 15 / macOS 12 / tvOS 16 / watchOS 8 / visionOS 1; swift-tools 5.9 |
| Deps | EmojiKit 1.7.1, GestureButton 0.5.0, SwiftLintPlugins 0.65.0 (all pinned `exact:`) |
| CI | GitHub Actions, `macos-15` + **Xcode 16.4 pinned**, builds all platforms + iOS unit tests |
| **Community** | **1 star, 1 fork, 1 watcher, 1 open issue** |
| Contributors post-fork | Jean-Pierre Höhmann (38), Maarten Trompper (24), "Yatsar (Agent)" — an AI agent (12) |

**Builds against current Xcode/iOS?** CI pins **Xcode 16.4**, not Xcode 26.x — **not verified against the current toolchain.** The maintainer is tracking iOS 26 though: commit `11d0707c` (2025-12-25) *"Drop support for scroll views, since button gestures and scrolling don't work together in iOS 26."* **LIKELY builds; not proven.**

**Critical caveat the PRD misses:** OpenKeyboardKit inherits the **hollowed-out** free core. It still ships `Sources/OpenKeyboardKit/_Pro/ProPlaceholders.swift` — **733 lines of stubs** that render or throw *"This is unlocked by KeyboardKit Pro."* CONFIRMED, verbatim samples:

```swift
class LocalAutocompleteService: Autocomplete.DisabledAutocompleteService { … }  // Pro
class RemoteAutocompleteService: Autocomplete.DisabledAutocompleteService {}     // Pro
static var azerty: Self { get throws { throw ProPlaceholderError.proPlaceholder } }
static func localized(for locale: Locale) throws -> Self { throw ProPlaceholderError.proPlaceholder }
public struct EmojiKeyboard: View { var body: some View { ProPlaceholderError.proPlaceholder } }
public struct KeyboardTheme: KeyboardModel {}   // empty
```

18 stubbed sections: Keyboard, Actions, **Autocomplete**, App, **Callouts**, Dictation, Emojis, Host, Input, **Layout**, Licenses, Localization, Previews, Proxy, Status, Styling, **Themes**.

**Verdict:** a **realistic but narrow** fallback. A legitimate, MIT, buildable, fully-inspectable ~23k-LOC UI/gesture/layout engine with real value (key geometry, callouts, gestures, feedback, proxy utils, English callout actions). **Not abandoned** — but one maintainer + an AI agent, 1 star. And it gives you **exactly zero autocomplete**. Treat it as *"a vendored 23k-LOC starting codebase you now own and maintain,"* not *"a maintained dependency."*

---

## 3. Other options

### 3.1 Open-source iOS keyboard projects

| Project | License | Last commit | Verdict |
|---|---|---|---|
| **OpenKeyboardKit** | MIT | 2026-07-14 | Best OSS starting codebase. See §2 |
| **azooKey/azooKey** | **MIT** | **2026-08-01** | Shipping App Store Japanese keyboard, **301 Swift files**, SwiftUI, own neural kana-kanji engine ("Zenzai", GGUF models in-repo). **The best living reference for a production SwiftUI iOS keyboard.** Not a reusable Latin-script framework |
| **divvun/giellakbd-ios** | **Apache-2.0 OR MIT** | **2026-06-30** | 57 stars, 1,464 commits. **UIKit** reimplementation of Apple's keyboard for minority languages; layouts generated by `kbdgen`; spell/suggest via **DivvunSpell** (Rust/HFST) in a pluggable "Banner" architecture. **The closest thing to an OSS "native iOS keyboard clone"** |
| **archagon/tasty-imitation-keyboard** | BSD-style | 2017-11-27 | The historical "imitate Apple's keyboard in CoreGraphics" project. **Dead.** Still worth reading for key geometry + popup math |
| **Brimizer/Slidden** | (no LICENSE file) | 2019-12-16 | iOS 8-era, abandoned, no license. Ignore |
| **ksaitor/WhisperSource** | **GPL-3.0** | 2026-02-16 | On-device WhisperKit dictation keyboard. GPL-3 is **App Store-incompatible**. Reference only |
| **Fleksy PredictiveTextSDK** | Commercial | - | GitHub repo now 404s; Fleksy sells autocorrect/prediction/swipe in 82 languages. UNVERIFIED |

### 3.2 Google / Mozilla open keyboard work

- **Gboard (iOS)** — closed source. There is **no open-source Google iOS keyboard.** CONFIRMED-by-absence.
- Google's open input work is Android/desktop: **AOSP LatinIME** (Apache-2.0), **mozc**. Java/C++, not portable to `UIInputViewController`.
- **FlorisBoard, HeliBoard, OpenBoard, AnySoftKeyboard** — all **Android-only**.
- **Mozilla has no keyboard project.**
- **There is no cross-platform OSS keyboard engine you can lift. Everything mature lives on Android.**

### 3.3 DIY: build the key grid yourself

| # | Behavior | Native API help? | Real cost |
|---|---|---|---|
| 1 | **Key geometry per device/orientation** | None | High. Row heights, gutters, insets differ per device class, orientation, and now Liquid Glass. Apple warns: *"the width of the keyboard can vary, even while it's currently on screen"* |
| 2 | **Press callouts** | None | Medium. Custom shape, must not clip at screen edges |
| 3 | **Long-press alternate popovers** (á é í ó ú ñ ü ¿ ¡) | None. No system list of alternates | Medium. Own per-key table + directional drag + edge flipping. **Good news:** it's just a dictionary; OpenKeyboardKit's `Callouts+Actions.swift` already ships an English table (`"a": "aàáâäǎæãåāăą"`) to extend for ES/IT |
| 4 | Shift / double-tap caps lock | None | Low |
| 5 | Delete-repeat acceleration | None | Low-Medium |
| 6 | Space-cursor-drag | `adjustTextPosition(byCharacterOffset:)` | Medium. Proxy is async and lossy across app boundaries |
| 7 | Double-space -> ". " | None | Low |
| 8 | **Key click sound** | **`UIDevice.current.playInputClick()`** + conform to **`UIInputViewAudioFeedback`**. *"A click plays only if the user has enabled keyboard clicks in Settings > Sounds…"* **Does NOT require Full Access** | Low. CONFIRMED |
| 9 | **Haptics** | `UIImpactFeedbackGenerator` | Low to write. **But widely reported not to fire in keyboard extensions unless Full Access is on** (Apple forum 63493, 2016, still unanswered). LIKELY, undocumented. Plan a graceful no-haptics path |
| 10 | Autocapitalization | `textDocumentProxy.autocapitalizationType` + `documentContextBeforeInput`. Apple: *"Use `CFStringTokenizer`… to implement autocapitalization."* | Medium. You implement sentence detection yourself |
| 11 | Return-key label | `textDocumentProxy.returnKeyType` | Low, but **localized labels are on you** |
| 12 | Dark mode | `keyboardAppearance`, `UITraitCollection` | Low-Medium. Keyboard appearance != system appearance |
| 13 | Dynamic Type | System font metrics | Low, but key heights must not scale freely |
| 14 | **Accessibility / VoiceOver** | `.accessibilityAddTraits(.isKeyboardKey)` | Medium. `isKeyboardKey` (not `.isButton`) is what makes VoiceOver announce keys correctly — KeyboardKit only fixed this in 10.0.1 |
| 15 | **Globe / next keyboard** | `needsInputModeSwitchKey`, `handleInputModeList(from:with:)` with `.allTouchEvents` | Low, **mandatory**. On Face-ID iPhones iOS draws the globe itself and sets `needsInputModeSwitchKey = false` — do not draw your own |
| 16 | Marked text / composition | `setMarkedText(_:selectedRange:)`, `unmarkText()` | Low. **Useful for LinguaKey:** Apple's doc shows inserting a combining acute as marked text then composing `á`, and using marked text for inline autocompletion |
| 17 | iOS 26 Liquid Glass conformance | None | **Ongoing yearly tax** a framework would absorb for you |
| 18 | **Memory discipline** | Apple: *"If your keyboard extension exceeds the memory limit the system terminates it."* ~48-60 MB, jetsam kills with **no crash log** | Ongoing |

**Realistic DIY effort for items 1-16 at "acceptable for daily messaging" quality: 3-6 focused weeks for a solo dev**, plus a long tail. Items 1, 2, 3, 6, 14 are where hand-rolled keyboards actually feel wrong.

---

## 4. Autocorrect / prediction available to a third-party keyboard

### 4.1 What Apple exposes (CONFIRMED from developer.apple.com)

**`UITextChecker`** — *"An object to check a string… for misspelled words… You may also use a text checker to obtain completions for partially entered words, as well as possible replacements for misspelled words."*
- `rangeOfMisspelledWord(in:range:startingAt:wrap:language:)`
- `guesses(forWordRange:in:language:)`
- `completions(forPartialWordRange:in:language:)` -> *"in the order they should be presented to the user - that is, more probable completions come first"*
- `learnWord` / `unlearnWord` / `hasLearnedWord` / `ignoreWord` / `ignoredWords`
- `class var availableLanguages: [String]` — **includes `en`, `it`, `es`**

**Real limits:**
- **`guesses` ordering is the killer.** On iOS the returned guesses are close to **alphabetical**, not probability-ranked (unlike macOS). LIKELY, widely reported. You must re-rank yourself.
- No keyboard-geometry awareness — no idea "hte" came from adjacent keys.
- **No next-word prediction. None.** `completions` only extends the current partial word.
- No n-gram/context model. No swipe decoding.
- Instantiate **once** and reuse; per-call on a hot keypress path with a long context will cost you.

**`UILexicon`** via `requestSupplementaryLexicon(completion:)`. Apple: *"This method can be called only from a custom keyboard app extension"*, and pointedly: **"Apple intends for you to consider the words in a lexicon object as supplementary to an autocorrection/suggestion lexicon of your own design."** Contents: user Text Replacement shortcuts, some common words, and address-book names. **Not a frequency-ranked dictionary. It is tiny.**

**`UITextInputTraits`** (readable through the proxy): `autocapitalizationType`, `autocorrectionType`, `spellCheckingType`, `returnKeyType`, `keyboardType`, `keyboardAppearance`, `smartQuotesType`, `smartDashesType`, `smartInsertDeleteType`, `inlinePredictionType`, `isSecureTextEntry`. **You must honour `autocorrectionType == .no`** (URL/code fields) or you will corrupt text.

**Not exposed to third-party keyboards:** Apple's own autocorrect engine, its keyboard-geometry touch model, its on-device predictive/transformer language model, Apple Intelligence / Writing Tools inline prediction, and QuickType. CONFIRMED-by-absence.

### 4.2 Open-source options

| Engine | License | iOS viability | Notes |
|---|---|---|---|
| **SymSpell** — `gdetari/SymSpellSwift` | **MIT**, last commit 2026-01-20 | **Best fit.** Pure Swift, SPM, no C++ bridging | Symmetric-delete; needs a frequency dictionary per language. Gives **frequency-ranked** corrections — exactly what `UITextChecker.guesses` fails to do. Memory = dictionary size; tune for the ~50 MB budget |
| **Hunspell** (`aaronSig/Hunspell-iOS`) | LGPL/GPL/MPL tri-license | C++ bridging painful; devs report abandoning it for UITextChecker + custom dictionary. Tri-license needs legal care | Excellent morphology for ES/IT. Validation "tens of ms", suggestions "<1s" — **too slow for the keypress path** |
| **KenLM / n-gram LM** | LGPL (KenLM) | Build your own instead | A 2-3-gram count table over a corpus is small, fast, interpretable, and gives **next-word prediction**, which Apple gives you nothing for |
| **Presage** | GPL-2.0 | **App Store-incompatible in practice** | Historically the go-to library for this problem |
| **DivvunSpell** (giellakbd-ios) | Apache-2.0/MIT | Rust + Swift SDK, FST dictionaries, real shipping iOS integration | Heavy for Latin scripts, but the *architecture* (pluggable "Banner" suggestion plugin above the keys) is a direct model for LinguaKey's learning bar |
| **AOSP LatinIME dictionaries** | Apache-2.0 | Data yes, code no | `.dict` word/bigram data is reusable; the Java/JNI engine is not |

### 4.3 What shipping third-party iOS keyboards actually used

- **Gboard, SwiftKey, Fleksy, Grammarly** — all shipped their **own proprietary engines** ported from Android/desktop, not `UITextChecker`.
- **Fleksy** productised theirs as the commercial PredictiveTextSDK.
- **Indie keyboards** overwhelmingly land on **`UITextChecker` + a custom frequency dictionary**, having tried and abandoned Hunspell/Presage.
- **giellakbd-ios** is the only OSS iOS keyboard with a serious, pluggable spelling engine.

**Practical recipe for LinguaKey (§12 P0 "basic English/Italian suggestions"):**
```
UITextChecker.completions()                     -> candidate generation
SymSpellSwift + EN/IT/ES frequency lists        -> candidate generation + ranking
UILexicon                                       -> merge user Text Replacements & contact names, rank first
keyboard-geometry neighbour weighting           -> typo prior (§24 "Later")
bigram counts                                   -> next-word (§12 P2)
UITextInputTraits.autocorrectionType == .no     -> hard off-switch
UITextChecker.learnWord / local learned store   -> adaptation
```
Roughly **1-2 weeks** for a credible v1, **yours, free, on-device, inspectable** — versus ~$1,500/yr rented.

---

## 5. Recommendation

### 5.1 Decision table

| Option | Licence risk | $/yr | Autocorrect | Native feel OOTB | Vendor risk | To Phase 0 | To §24-acceptable typing |
|---|---|---|---|---|---|---|---|
| **A. KeyboardKit 10 (free)** | Closed binary; reverse-engineering forbidden | $0 | **none** | ***** | **High** | **~3 days** | never - blocked by paywall |
| **B. KeyboardKit + Basic** | same | ~$500 | yes, **1 locale only** | ***** | High | ~3 days | no - EN+IT+ES needs 3 |
| **C. KeyboardKit + Silver** | same | **~$1,500 recurring** | yes, 5 locales | ***** | High (expiring signed license, bundle-ID-locked) | ~3 days | ~1 week |
| **D. OpenKeyboardKit (MIT fork of 9.9)** | **None. MIT. You own it.** | $0 | stubs only | ****  | **None** | **~1 week** | ~2-3 weeks (SymSpell + UITextChecker) |
| **E. Full DIY** | None | $0 | none | ** initially | None | ~2-3 weeks | ~6-10 weeks |
| **F. giellakbd-ios base** | Apache/MIT | $0 | FST-based, wrong shape for ES/IT/EN | *** (UIKit, older idioms) | Low | ~2 weeks | ~4+ weeks |

### 5.2 Recommendation: take D, with A as a 2-day throwaway spike

1. **Days 1-2 — spike on KeyboardKit free.** It genuinely is the fastest path to "a keyboard appears in Messages." Use it to validate extension wiring, App Group, `UITextDocumentProxy` behavior in WhatsApp/Notes, and to *feel* the target quality bar. **Do not build product logic on it.**
2. **Then vendor OpenKeyboardKit into the repo** — not as an SPM dependency on a 1-star repo, but as a directory you own under MIT. Delete `_Pro/ProPlaceholders.swift` and everything referencing it. Retarget and drop the ~40 locales you don't need — that alone buys back a meaningful slice of the ~50 MB budget.
3. **Write the autocomplete layer yourself** per §4.3. This is the piece KeyboardKit charges ~$1,500/yr for, it's ~1-2 weeks, and for a *language-learning* keyboard you need custom ranking anyway (§11 Mode C code-switching and §14 mastery-aware suggestions cannot be expressed through a black-box `AutocompleteService`).
4. **Keep PRD §5's abstraction-layer instruction** — the single best decision in the document.

**Why not C (~$1,500/yr):** you would rent, per-app and per-year, a closed binary from a one-person company, under a licence forbidding inspection, whose licence file format already broke once at 10.0, for a **personal-use app with no revenue** (PRD §3). Every renewal is a hostage payment.

**Why not E:** items 1/2/3/6/14 in §3.3 are where hand-rolled keyboards feel wrong, and OpenKeyboardKit has all of them already written, tested, and MIT.

### 5.3 Switching cost if wrong

| Wrong -> correct | Cost | Why |
|---|---|---|
| D -> C (OSS -> buy) | **Low, ~1 week** | Same lineage, same type names. It's a 9.9->10 migration with a documented upgrade path |
| C -> D (bought -> OSS) | **Medium-High, 2-4 weeks** | You lose autocomplete, localized layouts/callouts, emoji extras, themes, settings screens. Worse: 10.x is a **binary**, so you cannot diff or port anything back |
| D -> E | **Low, incremental** | You already own the source |
| A/C -> E | **High** | Nothing to port from a binary |

**D is the low-regret choice.** The expensive, irreversible direction is C->D. The cheap, reversible direction is D->C. Start on the reversible side.

---

## 6. PRD §5 corrections (drop-in)

| PRD §5 line | Verdict | Correction |
|---|---|---|
| "Repository: github.com/KeyboardKit/KeyboardKit" | correct | Add: the repo contains **no source** — an SPM manifest pointing at a binary in `KeyboardKit-Binaries` |
| "Swift + SwiftUI" | correct | Swift 5.9+, SwiftUI-first, iOS 16+ |
| "native-looking customizable keyboard UI" | correct | Free tier genuinely gives this (English QWERTY, `KeyboardLayout.standard(for:)`) |
| "actions and gestures / proxy abstractions / layout utilities" | correct | All free |
| **"autocomplete/autocorrect infrastructure"** | **misleading** | Rewrite: *"Autocomplete **protocols and toolbar UI** are free; the **engine is a paid Pro feature** (`ProFeature.autocomplete`). The free default is `DisabledAutocompleteService`, which returns no suggestions. LinguaKey must supply its own engine or buy a licence."* |
| "active maintenance as of 2026" | correct | 10.8.0 shipped 2026-08-17. But maintenance happens in a **private** repo — public commit velocity is not observable |
| **"moved away from the historical fully open-source model and includes proprietary/paid functionality"** | **understated / wrong** | Rewrite: *"KeyboardKit is **entirely closed-source** as of 2025-08-31 (v10), distributed as a **binary XCFramework**, validated at runtime by **LicenseKit**. The licence explicitly forbids reverse engineering and redistribution. There is **no free open-source core**. Pro pricing is a **recurring per-app subscription**: Basic ~$50/mo (1 locale), Silver ~$150/mo (5 locales), Gold ~$500/mo. LinguaKey's EN+IT+ES requirement lands on Silver, ~$1,500/yr."* |
| "OpenKeyboardKit is an MIT-licensed fork of the last open-source KeyboardKit version" | **correct and verified** | Forks `a7e33ac2` = KeyboardKit 9.9.0/9.9.1 (2025-08-23). Add: *"but it inherits the hollowed-out free core — a 733-line `ProPlaceholders.swift` stubs out autocomplete, localized layouts/callouts, emoji keyboard, themes and dictation. 1 star, one maintainer, CI pinned to Xcode 16.4."* |
| "less actively maintained than upstream" | correct, soften-to-precise | Last commit 2026-07-14; the maintainer *is* tracking iOS 26. Treat as **a codebase to vendor**, not a dependency to track |
| "Architecture decision: 1. Prototype with KeyboardKit… 2. Isolate behind an abstraction layer…" | **keep — the best part of the PRD** | Amend step 1 to *"time-box the KeyboardKit spike to 2 days, treat as throwaway"*, and add step 0: *"decide the autocomplete strategy before writing keyboard code, because it, not the key grid, determines the foundation."* |
| §32 reference list | incomplete | Add `KeyboardKit-Binaries`, archived `KeyboardKitPro` (sunset Jan 2027), `LicenseKit`, `gdetari/SymSpellSwift`, `divvun/giellakbd-ios`, `azooKey/azooKey`, Apple `UITextChecker` / `UILexicon` / `UIInputViewAudioFeedback` docs |

**Also flag in §22 (Memory):** Apple states plainly that *"that process has a limit on the amount of memory it may use. If your keyboard extension exceeds the memory limit the system terminates it."* Practical ceiling ~48-60 MB `phys_footprint`, killed by jetsam **with no crash log**. KeyboardKit's own high-priority bug #757 showed its emoji keyboard alone costing ~10 MB.

---

## Verification gaps

- Pricing (§1.5) is **LIKELY**, from two agreeing WebSearch reads plus arithmetic corroboration. Vendor site was egress-blocked. Open `https://keyboardkit.com/pricing` in a browser before budgeting.
- Everything about the **licence text, binary distribution, `ProFeature` enum, throwing APIs, framework size, tag dates, fork point, and OpenKeyboardKit contents** was verified directly from the Git repos and the shipped 10.8.0 XCFramework on 2026-08-18 — **CONFIRMED**.
- **Haptics-require-Full-Access** and the **~48-60 MB jetsam ceiling** are widely-reported developer folklore Apple has never documented numerically — **LIKELY**. Validate on-device in Phase 0.

---

# Addendum — iOS 27 / Xcode 27 (same agent, follow-up, 2026-08-18)

> **Beta caveat:** iOS 27 is at **Beta 6**. Everything below is subject to change before GM (~Sept 2026).

## 1. KeyboardKit 10.x vs the iOS 27 SDK

### 1.1 What the last three months shipped

Full-text scan of `RELEASE_NOTES.md` @ 10.8.0 (**CONFIRMED**, local clone):

| Query | Hits |
|---|---|
| `iOS 27` | **1** — in the 10.6 section only |
| `Xcode` (any version) | **0** across the entire document |
| OS-version or beta mentions in 10.7, 10.7.1-.3, 10.8 | **0** |

The single iOS 27 mention, verbatim, from **10.6** (2026-06-22) — **CONFIRMED**:

> *"Finally, since the host application bundle ID keeps returning `nil` in iOS 27, we have deprecated the `KeyboardInputViewController` `hostApplicationBundleId` property, and updated the documentation with alternate ways to handle this."*

**10.5-10.8 shipped exactly one iOS 27-related change, and it is a capitulation, not a fix.** 10.7 and 10.8 contain **zero** iOS 27 hardening.

### 1.2 The `hostApplicationBundleId` regression — the case study that matters

| Date | Event |
|---|---|
| ~2026-02/03 | iOS **26.4 beta** starts returning `nil`; KeyboardKit issue #1014 |
| 10.4 (2026-04-08) | "adjusts the `hostApplicationBundleId` logic to handle that this property becomes `nil` in iOS 26.4 and later" |
| 10.6 (2026-06-22) | Feature removed; property soft-deprecated; **iOS 27 beta did not restore it** |
| 10.6.1 (2026-07-02) | Patch restores a user-picker fallback |

**~4 months from first beta report to resolution, and the resolution was "delete the feature."** It all happened in a **point release** (26.4), not a major. Impact on LinguaKey directly: none (the PRD never needs host-app identification). But it is the cleanest available proxy for *"what happens when Apple breaks something in a keyboard extension."*

### 1.3 Deployment target / toolchain — unchanged

`swift-tools-version` **5.9** (unchanged since 10.0); platforms **iOS 16**+; **no stated minimum Xcode anywhere** (0 "Xcode" hits in README or release notes). **CONFIRMED**

### 1.4 Open issues — no iOS 27 breakage reported

Ten most recently created open issues (newest #1063, 2026-08-08) contain **zero** mentions of iOS 27, Xcode 27, beta, SDK breakage, crashes, or memory. **CONFIRMED.** Read as genuinely reassuring but **weak evidence** — ~1.9k stars with 32 open issues is a small reporting population and the beta window is short.

### 1.5 What the binary distribution means right before a major OS release

**This is the part that should drive the decision. You cannot recompile KeyboardKit.**

1. **No SDK-recompile escape hatch.** If a Swift ABI, SwiftUI, or UIKit change in the iOS 27 GM breaks the prebuilt slice, the normal remedy — rebuild the dependency against the new SDK, patch one line, ship — **does not exist.** You file an issue and wait.
2. **Wait time is empirically ~4 months** (§1.2), from a **single-person vendor**, for a bug that was reproducible and well-understood.
3. **You cannot even diagnose it.** No source; the LICENSE forbids reverse engineering. You get dSYMs — stack frames, not fixes.
4. **Compounding risk window.** iOS 27 GM ships ~4 weeks from now; 10.8.0 was cut **before GM**. No public statement that any 10.x build has been validated against the iOS 27 GM SDK. **UNVERIFIED — and unverifiable from outside.**
5. **The failure mode is worst exactly where it hurts most.** A keyboard extension that breaks is a keyboard that doesn't appear, or jetsams silently with no crash log. For a daily-driver keyboard, an unfixable multi-month outage is a product-ending event.

**Conclusion: adopting a closed binary keyboard framework in the four weeks before a major iOS release is the single worst-timed version of an already-risky dependency.** This *strengthens* recommendation D (vendor OpenKeyboardKit source) — vendored source means an iOS 27 break is a debugging session, not a support ticket.

## 2. OpenKeyboardKit against iOS 27 / Xcode 27

### 2.1 "Stale CI" vs "does the source compile"

**Different questions, and only the second matters for a vendoring plan.** CI pinning Xcode 16.4 tells you the *maintainer* hasn't validated against Xcode 26/27. It tells you **nothing** about whether the source compiles — and once vendored, **their CI is irrelevant; yours is the only CI that exists.** The stale pin is a maintenance signal, not a technical blocker.

### 2.2 Does the source plausibly compile under Xcode 27? — Yes

| Evidence | Finding | Status |
|---|---|---|
| **Manifest format** | KeyboardKit's **own** `Package.swift`, released **2026-08-17**, is still `// swift-tools-version: 5.9`. A commercially-supported package shipping *yesterday* uses the exact same tools version | **CONFIRMED — decisive by example** |
| **SwiftPM policy** | "the previous API version will continue to be available to packages which declare a prior tools version" | CONFIRMED |
| **Language mode** | tools-version 5.9 => Swift 5 language mode. Swift 6 strict-concurrency diagnostics are **warnings, not errors**. Xcode 27 ships Swift 6.4 | LIKELY |
| **Extension-safety** | `UIApplication.shared`: **0 occurrences in Swift code** (all 3 hits are in `.docc` markdown explaining you can't use it). `keyWindow`: 0. `@UIApplicationMain`: 0 | **CONFIRMED** (grep, 235 files) |
| **Deprecated-API surface** | `UIScreen.main`: **3 sites**. Soft-deprecated since iOS 16; **still present in the iOS 27 SDK** => warnings, not errors | CONFIRMED / LIKELY |
| **Scene mandate** | Applies to **apps**, not extensions. The host app is SwiftUI `@main` => already scene-based | CONFIRMED / LIKELY (extension scope) |

### 2.3 The actual risk is the pinned dependencies

```swift
.package(url: ".../EmojiKit.git",      exact: "1.7.1")
.package(url: ".../GestureButton.git", exact: "0.5.0")
.package(url: ".../SwiftLintPlugins",  exact: "0.65.0")
```
`exact:` pins from Dec 2025. **The most likely thing to fail a first build under Xcode 27** — a stale transitive dep, not OpenKeyboardKit's own 22.7k LOC.

### 2.4 Realistic remediation cost

| Task | Estimate |
|---|---|
| First build under Xcode 26/27, triage | 2-4 h |
| Bump/vendor EmojiKit + GestureButton; drop SwiftLintPlugins | 2-4 h |
| Replace 3 x `UIScreen.main` | 1 h |
| Raise deployment target; delete unused locales; delete `_Pro/ProPlaceholders.swift` | 2-3 h |
| Clear Swift 6 concurrency warnings (optional) | 0-8 h |
| **Total** | **~1-2 days, worst case one week** |

**Verdict: NOT a blocker.** UNVERIFIED that it compiles clean (no Xcode in the research environment) — **this should be the very first task of Phase 0.**

## 3. Did iOS 27 give third-party keyboards anything new?

### **No. Nothing.** Checked four independent ways.

**3.1 WWDC26 session catalogue — 115 sessions, zero keyboard sessions.** **CONFIRMED.** No custom-keyboard session, no text-input-extension session, **no "What's new in UIKit" session at all this year.** Closest match — *"Elevate your app's text experience with TextKit"* — is about apps' own text views. It gives the *host* better text, not you better input.

**3.2 Apple's "UIKit updates" page — 4 "keyboard" hits, all irrelevant.** Occurrences of `UIInputViewController`, `UITextChecker`, `UILexicon`, `UITextDocumentProxy`, `autocorrect`, `UITextInputTraits`: **0, 0, 0, 0, 0, 0.** **CONFIRMED**

**3.3 iOS & iPadOS 27 Beta 6 release notes — full-text scan, 59,787 chars.** `keyboard`: 2 hits, both SwiftUI `fullScreenCover` animation bugs. `Keyboard`: 1 hit — Settings > Keyboard > Dictation > "Advanced Dictation Preview", **a system feature for Apple's own keyboard. No API. Not available to extensions.** **CONFIRMED**

**3.4 Symbol-level diff via Apple's documentation index** — every symbol's `introducedAt` checked programmatically. **CONFIRMED:**

| Type | Symbols introduced in iOS 26 or 27 |
|---|---|
| `UIInputViewController` | **NONE** |
| `UITextDocumentProxy` | **NONE** |
| `UITextChecker` | **NONE** |
| `UILexicon` | **NONE** |
| `UITextInputTraits` | **NONE** |

`UIInputViewController`'s complete member list is **unchanged since iOS 8**.

**3.5 Against the checklist**

| Asked | Answer |
|---|---|
| New **emoji** access for extensions? | **No.** You still ship your own emoji grid |
| New **dictation** access? | **No.** iOS 27's "Advanced Dictation Preview" is a Settings toggle for Apple's keyboard |
| New **autocorrect/prediction API**? | **No.** `UITextChecker`/`UILexicon` byte-for-byte unchanged. QuickType, Apple's touch model, inline prediction remain private |
| **Memory ceiling** change? | **No documented change.** No number published, then or now |
| New **`UITextDocumentProxy`** capability? | **No.** Zero new symbols |
| **Apple Intelligence** surface opened to keyboards? | **No new one in iOS 27** — but one was already opened in **iOS 26**. See 3.6 |

### 3.6 The thing that *did* change — and it landed in iOS 26, not 27

**`FoundationModels.framework` is usable from inside a keyboard extension.** Primary evidence from the downloaded binary:

```
$ strings KeyboardKit.xcframework/ios-arm64/KeyboardKit.framework/KeyboardKit | grep Frameworks
/System/Library/Frameworks/FoundationModels.framework/FoundationModels   <- linked
$ head -12 .../arm64-apple-ios.swiftinterface
import FoundationModels
```

**CONFIRMED** — KeyboardKit 10.8.0's shipped Mach-O links `FoundationModels`, and its public `.swiftinterface` imports it. *A framework does not link into a keyboard-extension-targeted binary that cannot run there.* This independently corroborates Research 03.

From **10.3** release notes (2026-02-12) — **CONFIRMED, verbatim**:
> *"This version adds support for on-device next word prediction, using Apple's Foundation Models. This is available on supported platforms (from iPhone 15 Pro & iOS 26.1)."*
> *"Note that this is a very(!) new technology that is noticably slower and less accurate than other autocomplete features."*

And the shipped enum — **CONFIRMED** (`.swiftinterface` line 7061):
```swift
public enum AutocompleteMethod : String, CaseIterable { case local; case claude; case openAI }
```
`.local` is the Foundation Models path and is the **default** since 10.3.

**Does this change the recommendation? Yes — it pushes *harder toward D*, not toward C.** Foundation Models is a **free system framework**. KeyboardKit's `.local` next-word prediction is a thin wrapper around it sitting behind `ProFeature.autocomplete` — i.e. **you would be paying ~$1,500/yr for a wrapper around an API Apple gives you for free.**

**Caveats before anyone gets excited (all must be measured, not assumed):**
- **Device floor: iPhone 15 Pro + Apple Intelligence enabled.** Not universal. LIKELY
- **Session init 200-500 ms**, and creating a session "involves loading the model's weights into the Neural Engine's memory and allocating a buffer for the context window." LIKELY. Against a ~50 MB extension ceiling this needs direct measurement before it is load-bearing
- **The only vendor who has shipped it in a keyboard says it is "noticably slower and less accurate"** than conventional autocomplete. **CONFIRMED.** A strong signal it is **not** ready to be your P0 typing engine

**Recommendation: treat Foundation Models as a translation/teaching engine (§11/§15), never as the P0 autocorrect engine.** Keep SymSpell + `UITextChecker` as the typing-quality foundation. Nothing about iOS 27 justifies buying KeyboardKit.

## 4. Deployment-target recommendation

| Fact | Status |
|---|---|
| Xcode 27 ships **Swift 6.4** + iOS 27 SDKs | LIKELY |
| Xcode 27 is **Apple-silicon only** | LIKELY |
| **App Store submission floor is still the iOS 26 SDK / Xcode 26**, in effect since **2026-04-28**; **no announced deadline** forcing the iOS 27 SDK | LIKELY |
| Building against the **iOS 27 SDK** makes the scene-based life cycle mandatory for **apps** — non-migrated apps fail to launch | CONFIRMED |
| SwiftUI `@main struct App` is already scene-based => mandate is a non-event here | LIKELY |

> **Recommendation: build with the iOS 26 SDK (Xcode 26) through Phase 0-1. Do not adopt the iOS 27 SDK until ~iOS 27.1.**

1. **Nothing in iOS 27 is worth chasing** (§3). Pure risk, zero reward for this product.
2. **No deadline exists.** Submission floor is iOS 26 SDK; LinguaKey is personal-first and sideloaded.
3. **The iOS 27 SDK adds the scene-lifecycle mandate** — low risk given SwiftUI, but a needless variable during Phase 0.
4. **If you take KeyboardKit you have no choice anyway** — its binary predates the iOS 27 GM SDK and you cannot rebuild it.
5. **Ship, then upgrade.** Move to Xcode 27 as a deliberate, isolated task once 27.1 ships.

On the *deployment target* (as distinct from the SDK), this agent initially favoured keeping iOS 18 but lists strong arguments for raising to **iOS 26**: one visual target (Liquid Glass only — you stop maintaining pre-26 and 26+ appearance variants, which KeyboardKit does maintain); unconditional `FoundationModels` availability; and *"this is a personal-use-first app on your own iPhone — you control the device, backward compatibility buys you nothing today."*

Do **not** put `.iOS(.v15)` (OpenKeyboardKit's declared floor) into the vendored package — raise it on day one so you delete availability shims rather than inherit them.

## 5. Net effect on the recommendation

**Unchanged in direction; strengthened in confidence.**

| Input | Effect on D (vendor OpenKeyboardKit) |
|---|---|
| iOS 27 exposes no new keyboard API | Neutral — nothing to gain from waiting or from buying |
| KeyboardKit is a binary you cannot rebuild, 4 weeks before a major OS release, with a 4-month precedent for Apple-side-break turnaround | **Strongly favours D** |
| OpenKeyboardKit's stale CI is a signal, not a blocker; ~1-2 days remediation | **Removes the main objection to D** |
| Foundation Models is a free system framework already reachable from extensions; KeyboardKit charges for a wrapper around it | **Favours D** |
| No iOS 27 issues reported against KeyboardKit | Mildly favours C, from a small reporting population |

**Verdict: proceed with D.** Add one gate to Phase 0: **before writing product code, clone OpenKeyboardKit, vendor it, and get it building under Xcode 26.** If that fails badly (>1 week), that — not iOS 27 — is the signal to reconsider.

### Verification gaps in this addendum

- **Cannot compile anything** (no macOS/Xcode in the research environment). §2.2 is inference from manifest formats, grep, and SwiftPM policy — **UNVERIFIED by build.** The single most important thing to test first.
- Egress-blocked: `ikyle.me`, `mjtsai.com`, `swiftjectivec.com`, `docs.swift.org`, `keyboardkit.com`, `dev.to`, `archive.org`. Apple-sourced iOS 27 findings (§3.2-3.4) came from `developer.apple.com`'s docs JSON API and **are CONFIRMED**; Xcode 27 / Swift 6.4 / App Store floor details rest on search summaries and are **LIKELY**.
- **iOS 27 Beta 6 != GM.** A keyboard-relevant change could still land in Beta 7+ or 27.1. **The `hostApplicationBundleId` case proves Apple changes keyboard-extension behavior in *point* releases with no release-note announcement** — so "nothing in the iOS 27 notes" is not a guarantee of "nothing will break." Re-check at GM.
