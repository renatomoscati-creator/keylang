# Research 01 — iOS Keyboard Extension Platform Constraints

> Source: research subagent, 2026-08-18. Confidence: **CONFIRMED** (primary source + URL) /
> **LIKELY** (secondary, corroborated) / **UNVERIFIED**.
> Domains blocked by the sandbox proxy (claims from them marked LIKELY/UNVERIFIED): keyboardkit.com,
> medium.com, dev.to, support.apple.com, support.grammarly.com, openradar.appspot.com, web.archive.org.

## 0. Executive summary — the six things that can kill this product

1. **The keyboard has no reliable read of "the sentence the user just typed."** `documentContextBeforeInput` is a best-effort, host-dependent, paragraph-truncated, sometimes-`nil` string delivered over IPC. Every learning mode in PRD §11 depends on text the platform does not promise to give you.
2. **Memory ceiling is ~30-60 MB, enforced by jetsam with no crash log** — the user is silently bounced back to the Apple keyboard. SwiftUI + KeyboardKit + an emoji grid can consume most of it before product code exists. An embedded LLM is impossible.
3. **Writing to the App Group container requires Full Access.** PRD §19 assumes shared settings/vocabulary writes from the keyboard; without Full Access those writes fail *silently*. Apple's doc: reading is permitted, writing is not.
4. **App Store guideline 4.4.1 requires the keyboard to "remain functional without full network access and without requiring full access."** LinguaKey's entire value prop is gated behind Full Access. Shippable, but the no-Full-Access path must be a genuinely good keyboard.
5. **No microphone, no host-app identity, no return-to-host, no modal UI, no drawing outside your own frame.**
6. **The PRD targets iOS 18+ on 2026-08-18. iOS 27 ships in ~4 weeks.** Two majors stale, and iOS 26 already broke keyboard extension visuals.

---

## 1. `UIInputViewController` lifecycle & `UITextDocumentProxy` reality

### 1.1 What the API actually is

- `UITextDocumentProxy` is a **`@MainActor` protocol inheriting `UIKeyInput` *and* `UITextInputTraits`** — so you can read `keyboardType`, `returnKeyType`, `autocapitalizationType`, `autocorrectionType`, `smartQuotesType`, `smartDashesType`, `spellCheckingType`, `isSecureTextEntry` and (iOS 17+) `inlinePredictionType` off the proxy. **CONFIRMED** — https://developer.apple.com/documentation/uikit/uitextdocumentproxy
  - **This is the single most under-used API for LinguaKey.** Reading traits is how you detect email/URL/number fields, adapt the layout, and suppress the learning bar where translation is nonsense.
- Full member list: `documentContextBeforeInput`, `documentContextAfterInput`, `selectedText`, `documentInputMode`, `documentIdentifier` (UUID), `adjustTextPosition(byCharacterOffset:)`, `setMarkedText(_:selectedRange:)`, `unmarkText()`, plus `insertText`, `deleteBackward`, `hasText`. **CONFIRMED**
- **Apple documents no length guarantee, no nil-conditions, and no consistency guarantee** for the context properties. One-sentence abstracts, no Discussion section. **CONFIRMED** (docs JSON retrieved 2026-08-18). *Everything below is empirical, not contractual.*

### 1.2 `documentContextBeforeInput` / `AfterInput` in practice

| Behaviour | Confidence | Evidence |
|---|---|---|
| Returns **only text near the cursor**, commonly truncated at a **paragraph/newline boundary** — a `\n` stops the proxy returning more | **LIKELY** (universally reported, never contradicted) | KeyboardKit's whole `fullDocumentContext` feature exists to work around it |
| On **paste**, returns only the **last ~2 sentences**, not the pasted body — reproduced in WhatsApp, Signal, Telegram | **LIKELY** | forums/thread/772158 (Jan 2025, unanswered) |
| In **Gmail / Apple Mail**, returns **`nil` after a paste** until the user manually edits; works in Messages | **LIKELY** (Apple DTS engaged, unresolved) | forums/thread/812642 (Jan 2026) |
| The frequently repeated "**300 character cap**" | **UNVERIFIED** — could not be traced to any primary source or reproducible test; **treat as folklore.** Behave as if the cap is "one paragraph, unknown length, possibly zero." | search-snippet propagation only |
| `selectedText` is **truncated for multi-line selections** and frequently disagrees with the visible selection | **LIKELY** | rdar/FB7789012 |
| **WKWebView / Safari**: limited context, spurious leading whitespace; `contenteditable` and JS editors are worst-case | **LIKELY** | forum reports |
| Hosts implementing text input themselves (RN/Flutter/custom `UITextInput`) can return anything, including nothing | **LIKELY** | general |
| **Grammarly does not solve this** — its support docs say the keyboard "checks only the text you type while using it," i.e. it maintains its **own shadow buffer of keystrokes** rather than reading the field | **LIKELY** | Grammarly support article |

> **Architectural consequence:** do **not** treat `documentContextBeforeInput` as the source of truth. Maintain a **local shadow buffer** of what *your* keyboard inserted since the last `documentIdentifier` change / `selectionDidChange`, and use `documentContextBeforeInput` only as a *reconciliation hint* and recovery path. This is what shipping assistive keyboards do.

### 1.3 `textWillChange` / `textDidChange` / `selection*Change` cadence

- `UIInputViewController` conforms to `UITextInputDelegate`; **the argument is always `nil`** because you have no access to the text input object. **CONFIRMED**
- **They are not a text-change notification stream.** Reported behaviour, stable 2016 → at least 2019 and still assumed by KeyboardKit:
  - **NOT** called when *you* call `insertText(_:)` / `deleteBackward()`.
  - **NOT** called when a hardware/external keyboard types.
  - **ARE** called on keyboard show/hide and when the cursor/selection moves — including when *you* call `adjustTextPosition(byCharacterOffset:)`.
  - **LIKELY** — forums/thread/45121 (Apr 2016, still reproducing Jul 2019, no Apple fix).
- The classic hack — `adjustTextPosition(+1)` then `(-1)` to force a refresh — **works but is CPU-expensive in a loop, races with concurrent insertions, and dismisses any open key callout.**
- **Can you observe host-side edits?** Cursor/selection moves: **yes** (`selectionDidChange`). Host autocorrect: **there is none** — autocorrect is the *keyboard's* job (PRD §24 is right to prioritise it). System dictation: **you are not running**; `hasDictationKey` only tells you whether the system key is *disabled*. **CONFIRMED**
- `documentIdentifier` (UUID, iOS 10+) is the **only reliable "user moved to a different text field" signal.** Use it to invalidate the shadow buffer and cancel in-flight requests.

### 1.4 Replacing an already-typed sentence

There is **no batch replace API.** The only mechanism is N x `deleteBackward()` + `insertText(_:)`.

- Apple documents the delete-by-semantic-unit pattern: read `documentContextBeforeInput`, tokenise with `CFStringTokenizer`, delete the right number of characters. **CONFIRMED**
- Costs and hazards (**LIKELY**; no Apple perf guidance exists):
  - Each call is an **IPC round trip to the host process.** A 40-character sentence = 40 round trips. Visible character-by-character "unzipping" in slow hosts.
  - The host's **undo stack** records each deletion; shake-to-undo becomes useless.
  - Hosts with reactive text bindings (React Native, Flutter, SwiftUI `TextField` with a formatter) can fight the deletions and produce corrupted or reordered text.
  - `deleteBackward` past the beginning of the proxy's known context is a no-op in some web views — you can delete fewer characters than intended and insert Spanish into a partial stub.
- **`setMarkedText(_:selectedRange:)` is the under-used alternative** for the "insert Spanish" and code-switch flows: it replaces the marked region atomically on subsequent calls and shows a non-selected portion with a background tint — exactly the affordance §11 Mode B/C wants. Apple documents it for autocompletion ("Anth" -> "Anthony"). **CONFIRMED**. **Risk: UNVERIFIED** how consistently third-party hosts honour marked text; prototype in WhatsApp/Messages/Safari in week 1.
- **Recommendation:** put replace behind a single explicit user action, delete in one tight synchronous burst on the main actor (do **not** interleave `adjustTextPosition`), cap the replaceable span (<=120 chars), and abort + fall back to "insert Spanish after the English" if `documentContextBeforeInput` doesn't match the shadow buffer.

### 1.5 Lifecycle gotchas

- **`needsInputModeSwitchKey`, `hasFullAccess`, and the proxy are not valid in `viewDidLoad`.** Calling them early logs `was called before a connection was established to the host application` and returns a **wrong value**. **LIKELY (strong)** — KeyboardKit issue #83 (May 2020, 44 comments). **Read in `viewWillAppear`/`viewDidAppear` or later, and re-read on every appearance.**
- `viewDidLoad` has been observed **called twice in succession** on first launch. **LIKELY** — openradar 22217008. Make setup idempotent.
- Apple explicitly warns: **"dismissing the keyboard won't necessarily terminate the keyboard extension process. Don't assume the system releases memory your keyboard is using when it's no longer visible."** **CONFIRMED**

### 1.6 Did iOS 18 / 26 / 27 change any of this?

**No API changes.** `UITextDocumentProxy` and `UIInputViewController` have identical member lists to the iOS 8/10 era — no new symbols, no beta flags, no deprecations. **CONFIRMED** (docs JSON, 2026-08-18). See §8 for iOS 26/27 *behavioural* changes, which are real.

---

## 2. Memory and process constraints

### 2.1 What Apple actually says

> "Your custom keyboard code executes in a separate process, and that process has a limit on the amount of memory it may use. If your keyboard extension exceeds the memory limit the system terminates it… **Test your keyboard on various device models. The memory limits vary from model to model.** … Keep in mind that dismissing the keyboard won't necessarily terminate the keyboard extension process."
> **CONFIRMED** — https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard

Apple publishes **no number.** It points to `EXC_CRASH (SIGQUIT)` in crash reports.

### 2.2 The numbers, and how much to trust them

| Figure | Source | Confidence |
|---|---|---|
| ~30 MB crash threshold observed on device | forums/thread/105815 (Jul 2018, 50 PNGs -> ~30 MB -> crash) | LIKELY (old hardware) |
| **48 MB** — React Native keyboard extension could not initialise the RN bridge inside the limit; closed "not planned" | react-native issue #31910 | LIKELY |
| **~30-60 MB `phys_footprint`** on modern iPhones | multiple 2024-2026 practitioner write-ups, converging | LIKELY |
| ">50 MB extension crashes appeared in iOS 16 but not iOS 15" | forum reports | UNVERIFIED |

**Working assumption: a hard budget of 40 MB total resident, alarm at 30 MB.**

### 2.3 Failure mode — the part that matters

Jetsam kills the extension for exceeding the per-process limit. From the user's side there is **no crash dialog** — iOS silently swaps back to the previously used keyboard mid-sentence. **LIKELY (strong).** Consequence: **you will not see this in Xcode**, and users report it as "the keyboard keeps disappearing." Instrument `phys_footprint` via `task_vm_info` and log to the App Group on every `viewDidAppear`.

### 2.4 Where the budget actually goes

- **Emoji rendering is the #1 memory killer.** KeyboardKit measured its emoji keyboard at **~10 MB per page** for hi-res emoji fonts, with `LazyVGrid` **failing to deallocate cells** after scroll-off, so memory climbed monotonically across categories. Baseline went ~20 MB -> "big jump" on tapping the emoji key. Fixed by deferring emoji-keyboard init and shipping low-res styles. **CONFIRMED (as a measured report)** — KeyboardKit issue #757 (2024-07-15, HIGH PRIO).
- CoreText emoji glyph caches are known to retain memory in keyboard extensions. **LIKELY**
- **Implication:** an emoji key is a user expectation, but may cost 30-50 % of the entire budget. Consider deferring emoji to the globe key in V1, or lazily loading a low-res sheet.

### 2.5 What this means for "SwiftUI + embedded LLM/ML + SQLite"

- **Embedded LLM: impossible.** Even a heavily quantised 100M-parameter translation model needs hundreds of MB. **CONFIRMED by arithmetic.** Delete "on-device model experimentation" (§12 P2) as a keyboard-side item; it can only live in the host app.
- **Apple's `SystemLanguageModel` (Foundation Models, iOS 26+) is the exception that changes the calculus:** the model and inference resources are "managed centrally by the operating system and shared by all Apple Intelligence system features, so the increase to your app's memory usage will be very minimal" (model ~1.2 GB, not attributed to you). **LIKELY.** See §7.6 for the catch.
- **SQLite: fine.** A bounded vocabulary DB + LRU cache with WAL and explicit `mmap_size` limits is a few MB. **Avoid Core Data / SwiftData in the extension** — launch cost and object-graph memory are poor value; use raw SQLite (GRDB or C API) and write off the keypress path.
- **Caches must be byte-bounded, not entry-bounded.**

### 2.6 Cold start / latency budget

- Measured system behaviour on keyboard launch (developer repro, iOS 17/18/26.2, all iPhone models): **t=0 view is 0x0 -> t~295 ms iOS sets frame to full-screen (440x956) -> t~373 ms -> 440x452 -> t~390 ms settles at the requested 268 pt.** **CONFIRMED (as a reported measurement)** — forums/thread/813579 (Jan-Jun 2026, unresolved).
- Practical budget: **your view hierarchy must be constructible in <100 ms** or you extend a visible ~400 ms flicker into something users notice on *every* app switch. Zero disk I/O, zero JSON decoding, zero DB opens before first paint.
- **How often does the extension restart?** Apple only guarantees "not necessarily terminated on dismiss." In practice it is re-instantiated per host app and killed aggressively under memory pressure. Design for: *state lives in the App Group, the process is disposable.*

---

## 3. SwiftUI inside a keyboard extension in 2026

- **Viable? Yes, with discipline.** KeyboardKit is **SwiftUI-first**: override `viewWillSetupKeyboardView()` and hand it a SwiftUI view. **CONFIRMED**
- **iOS 26 rebuilt SwiftUI's rendering pipeline** (WWDC25), materially narrowing the gap to UIKit. **LIKELY**
- **The real risks are memory and rebuild storms, not raw frame rate:**
  - `LazyVGrid` **not releasing off-screen cells** in the emoji keyboard was a shipped, measured memory bug. **CONFIRMED**
  - A hierarchy that re-evaluates on **every keystroke** (e.g. an `@ObservableObject` holding the buffer observed by the whole key grid) will burn CPU and can push you over the jetsam line mid-typing.
- **What shipping keyboards do:** Gboard and SwiftKey are long-lived UIKit/C++ codebases (**UNVERIFIED**); newer/indie keyboards are overwhelmingly SwiftUI via KeyboardKit (**LIKELY**).
- **Recommendation:**
  - **Key grid: static SwiftUI, isolated from text state.** The ~30 key views must not depend on any observable that changes per keystroke. Pass shift/layout state as a small `Equatable` value; give every key a stable `id`.
  - **Learning bar: separate SwiftUI subtree** with its own small observable — the only thing that re-renders on text change.
  - Touch handling for keys: consider UIKit gesture recognisers (or `UIGestureRecognizerRepresentable`, iOS 18+) rather than SwiftUI gestures, for repeat-delete and slide-to-select.
  - **120 Hz ProMotion = 8.3 ms frame budget.** Key highlight must be a pre-baked state change, never a re-layout.
- **iOS 27 UIKit is explicitly "a tiny release"** with nothing for text input beyond TextKit 2 tables. **CONFIRMED** — see §8.

---

## 4. Full Access / `RequestsOpenAccess` — precise semantics

### 4.1 Apple's own capability split (primary source)

**With `RequestsOpenAccess = false`, or Full Access not granted**, the system guarantees: normal keyboard duties; access to the **common words lexicon** (`UILexicon` via `requestSupplementaryLexicon(completion:)`) and the **Text Replacement shortcuts list**; **no network access**; **"No access to the file system apart from the keyboard's own sandbox container, and read-only access to the containing app's shared containers"**; **"No access to microphone and speaker"**; no iCloud/Game Center/IAP.

**With Full Access**, additionally: Location Services and Contacts (with permission), a **shared container with the containing app**, and the ability to send keystroke data to your server.

**CONFIRMED** — https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard. Note the sandbox statement: *"This sandbox's default configuration disallows access to the network and prevents writing to the containing app's shared group containers (reading is permitted)."*

### 4.2 The gating matrix

| Capability | Requires Full Access? | Confidence & evidence |
|---|---|---|
| **Network (any `URLSession`)** | **YES** | **CONFIRMED** — sandbox "disallows access to the network" |
| **App Group container — READ** | **NO** | **CONFIRMED** — "reading is permitted" |
| **App Group container — WRITE** (incl. `UserDefaults(suiteName:)` writes, SQLite writes) | **YES** | **CONFIRMED** — Apple doc; corroborated by the exact device-only failure: `[User Defaults] Couldn't write values for keys (…) — setting preferences outside an application's container requires user-preference-write or file-write-data sandbox access`, fixed only by adding `RequestsOpenAccess`. forums/thread/728434. **Works in Simulator, fails on device — you will not catch this in the sim.** |
| **Keychain access group sharing** | **Probably NO** (entitlement-based, not container-based) | **UNVERIFIED for keyboard extensions specifically.** Apple's capability lists never mention Keychain. If BYOK depends on it (§7), **prototype on device first**; also set `kSecUseDataProtectionKeychain` for `kSecAttrAccessGroup` to behave |
| **`UIPasteboard`** | **YES** | **LIKELY (strong)** — the canonical pre-iOS-11 `hasFullAccess` detection trick probed `UIPasteboard.general`. Since iOS 16, pasteboard *reads* also trigger a user paste prompt — do **not** use this as a probe today |
| **Haptics** (`UIImpactFeedbackGenerator`) | **YES** | **LIKELY** — forums/thread/63493 (Sep 2016; never answered by Apple). No Apple doc states it. **UX trap: PRD §24 lists haptic feedback as a V1 typing-quality item, and it is unavailable in the no-Full-Access path** |
| **Key click sound** (`UIDevice.current.playInputClick()`) | **NO** | **LIKELY** — a system service, gated only on Settings > Sounds and on your input view adopting `UIInputViewAudioFeedback` + returning `true` from `enableInputClicksWhenVisible`. **CONFIRMED for the mechanism** |
| **`AVSpeechSynthesizer` / any audio playback** | **YES** (and even then, fragile) | **CONFIRMED blocked without Full Access** ("No access to microphone and speaker"). **UNVERIFIED that it reliably works *with* Full Access:** `AVAudioSession.setActive(true)` in a keyboard extension is reported failing with `OSStatus 561015905` even with Full Access granted, unanswered — forums/thread/709107. **PRD §29 lists AVSpeechSynthesizer as a decision; treat as an unvalidated assumption and spike it in Phase 0, not Phase 2** |
| **Microphone / dictation** | **NO — blocked even WITH Full Access** | **LIKELY (strong).** The industry workaround is opening the containing app to record. Apple DTS: forums/thread/826851 (2026). KeyboardKit implements dictation as keyboard -> `extensionContext.open(URL)` -> container app records -> App Group + Darwin notification -> keyboard inserts |
| **Location / Contacts** | **YES** + user permission | **CONFIRMED** |
| **Presenting a `UIAlertController` / any modal** | **N/A — not possible at all** | **LIKELY (strong)**; archived guide: *"a custom keyboard can draw only within the primary view of its `UIInputViewController` object."* |

### 4.3 When `hasFullAccess` flips, and its reliability

- No Discussion, no caveats documented. **CONFIRMED** (the property exists).
- **Unreliable before the host connection is established** (i.e. in `viewDidLoad`). Read in/after `viewWillAppear` and re-read every appearance. **LIKELY**
- **Toggling Full Access in Settings terminates the extension**, and has been reported to **SIGKILL the containing app** when the user returns right after the first enable. **LIKELY** — forums/thread/751384 (May 2024, unanswered). **PRD §20 Screen 1's Full-Access status + deep link must survive being killed on return.** Persist onboarding state before opening Settings.
- There is **no notification** for the toggle. Poll on `viewWillAppear`.

---

## 5. Where custom keyboards do not appear, and how to degrade

| Situation | Behaviour | Confidence |
|---|---|---|
| **Secure text entry** (`isSecureTextEntry == true`) | System temporarily swaps in the Apple keyboard; yours resumes on the next non-secure field | **CONFIRMED** — archived guide |
| **Phone pad fields** (`.phonePad`, `.namePhonePad`) | Same swap. Rationale: carrier-restricted character sets | **CONFIRMED** |
| **App opts out** | `application(_:shouldAllowExtensionPointIdentifier:)` returning `false` for `.keyboard` (`com.apple.keyboard-service`). Still current — **not deprecated**, iOS 8.0+ | **CONFIRMED** |
| **`UIApplicationSupportsCustomKeyboards` / `allowsCustomKeyboards`** | **These do not exist.** No such Info.plist key, no such API. The delegate method above is the only public opt-out. **If the PRD or any team member cites these keys, it's wrong** | **LIKELY (confirmed by absence)** |
| **MDM / supervised devices** | Third-party keyboards can be blocked by MDM restriction; on managed devices keyboard extensions obey Managed Open In rules | **LIKELY**. Exact payload key name: UNVERIFIED |
| **Lock screen passcode, Apple Pay, Wallet, Passwords app** | System keyboard only | **LIKELY** |

**How to detect and degrade:** you *cannot* detect the app-level opt-out — when a host returns `false`, **your extension is simply never launched**; neither it nor the containing app is informed. Same for secure fields. **CONFIRMED by mechanism.** So:
- For **secure fields you *do* get invoked in** (apps that toggle `isSecureTextEntry` for show/hide-password), read `textDocumentProxy.isSecureTextEntry` on each appearance and **hard-disable the learning bar, the shadow buffer, and all networking.** This is what actually delivers §21's privacy promise, rather than relying on iOS having excluded you.
- Also gate on `keyboardType` in {`.emailAddress`, `.URL`, `.numberPad`, `.decimalPad`, `.asciiCapableNumberPad`, `.webSearch`}: translating an email address or URL is a bug, not a feature.
- Onboarding must say: *"Some apps (banking, enterprise) block third-party keyboards entirely; iOS will use the Apple keyboard there."*

---

## 6. Globe key, dictation, emoji — what Apple mandates

**App Store Review Guideline 4.4.1** (retrieved 2026-08-18) — keyboard extensions **must**: provide keyboard input functionality; follow Sticker guidelines if they include images or emoji; **provide a method for progressing to the next keyboard**; **remain functional without full network access and without requiring full access**; collect user activity only to enhance the keyboard's functionality on the iOS device. They **must not**: launch other apps besides Settings, or repurpose keyboard buttons. **CONFIRMED**

Also: **"Apps and extensions, including third-party keyboards and Sticker packs, may not include Apple emoji"** (5.2.5). **CONFIRMED.** You may render emoji with the on-device system font; you may not bundle Apple emoji artwork.

**Globe key mechanics (CONFIRMED):**
- Check `needsInputModeSwitchKey`; **on Face ID iPhones iOS draws the globe itself below your view and sets this to `false`** — do not draw your own.
- Wire the button to `handleInputModeList(from:with:)` with **`.allTouchEvents`** (not `.touchUpInside`) so long-press opens the system picker. `advanceToNextInputMode()` alone loses the picker.
- There is **no API to enumerate enabled keyboards or switch to a specific one.**

**Dictation:** the dictation key belongs to the system. `hasDictationKey == true` means the system key is *disabled*. You cannot implement in-keyboard dictation (no mic — §4.2).

**Other user expectations Apple names but provides no API for** (you must build all of them): layout adaptation to `UIKeyboardType`, autocorrection & suggestion, auto-capitalisation, double-space-period, caps lock, keycap artwork, multistage input. **CONFIRMED** — archived guide. *This validates PRD §24's stance.*

**Layout/geometry rules (CONFIRMED):** width is always set by the system to the screen width; height is yours via a constraint on `self.view`, **only adjustable after the primary view first draws**; support compact and regular widths, both orientations, and iPad floating.

---

## 7. Other things that will blindside the team

### 7.1 You cannot identify the host app, and cannot return to it
All known methods (`_hostBundleID`, `_hostApplicationBundleIdentifier`, `xpc_connection_copy_bundle_id`, `NSXPCConnection.processBundleIdentifier`, `proc_pidpath`, `LSApplicationWorkspace.frontmostApplication`) return `nil`/`EPERM` on **iOS 26.4+**. Apple DTS confirms: **no public App-Store-safe API exists** either to identify the host or to return to it after a container-app round trip; open radars FB22247647 and FB24235692. KeyboardKit **removed** its return-to-host feature in v10.4 as a result. **CONFIRMED (DTS reply)** — forums/thread/826851 (2026).
> Kills: per-app behaviour tuning, "you're in WhatsApp so keep it casual" prompts, any dictation round-trip design, and any analytics keyed by host.

### 7.2 You cannot draw outside your own view
No callouts above the top edge (the way Apple's own keyboard does for the top row), no inline correction UI near the insertion point, no access to the host's edit menu, **no text selection**. **CONFIRMED.** LinguaKey's "long press Spanish sentence -> expanded breakdown" (§10) must expand *within* the keyboard's own (possibly grown) frame, pushing the host's content up.

### 7.3 Launch flicker is unsolved
See §2.6. Expect a visible resize animation on every keyboard appearance; developers note Grammarly/SwiftKey appear not to suffer it, but **no solution has been published**, and every documented technique (height constraint in `viewDidLoad`, `intrinsicContentSize`, `allowsSelfSizing`, `preferredContentSize`, overriding `layoutSubviews`) fails. **CONFIRMED as an open problem.** Budget engineering time; do not promise "native feel" until you've fought this.

### 7.4 iOS 26 changed how your keyboard looks, and you can't fully control it
- **Extra grey margins** are drawn around the left/right/top of custom keyboards **in Apple's own apps** (Messages, Notes, Safari) but not in third-party apps; **the margin cannot be painted over by your views.** Any non-grey keyboard background looks framed. 26 boosts, no Apple response. **CONFIRMED as a report** — forums/thread/800838 (Sep 2025, still live Apr 2026).
- iOS 26 ships **two keyboard designs** depending on whether the host app has adopted Liquid Glass, so "look like the native keyboard" (§25) is now **a moving target with no single correct answer.** **LIKELY**
- Third-party keyboards have crashed calling `textDocumentProxy.keyboardAppearance` on iOS 26. **LIKELY** — wrap trait reads defensively.

### 7.5 KeyboardKit is now fully closed-source (PRD §5 understates this)
`main` (KeyboardKit 10): **"KeyboardKit is closed-source."** LICENSE: *"Closed Source License, Copyright (c) 2016-2026 Kankoda Sweden AB…"* **CONFIRMED.** The `master` branch's MIT *badge* is stale — its LICENSE is also closed-source. **OpenKeyboardKit** is real and MIT but is a 1-star fork with "no support and no guarantee that the software works as intended." **CONFIRMED.** Treat as "you now own a keyboard framework," not a fallback. **PRD §5's abstraction-layer instinct is correct and should be mandatory, not aspirational.**

### 7.6 Apple's on-device LLM is a real option — with a specific trap for extensions
- `SystemLanguageModel` (FoundationModels, iOS 26+): OS-managed, memory not attributed to your process, ~4,096-token context. Requires Apple Intelligence-eligible hardware (iPhone 15 Pro+) and region. **LIKELY / CONFIRMED for the availability API**
- **Trap:** an Apple Frameworks Engineer states rate limiting **"applies when your device is on battery AND when your process is running in the background,"** and recommends **not streaming** in that case. Extensions hit this. A Safari extension was rate-limited after **4 requests at 30-second intervals**, surfacing as a *misleading* "Safety guardrail was triggered" error. Radar 153216632. **CONFIRMED (Apple staff reply)** — forums/thread/789788 (Jun 2025).
  - Whether a *keyboard* extension is classified "background" is **UNVERIFIED.** Must be measured before betting the local-fallback path on it.
- **iOS 27 (June 2026) adds the `LanguageModel` protocol** — "adopt the `LanguageModel` protocol to use **any** large language model — server or on-device — with the Foundation Models framework" — plus `PrivateCloudComputeLanguageModel` for larger context. **CONFIRMED.** A genuinely attractive architecture for LinguaKey: one call site, on-device for cheap/offline, your proxy for quality.

### 7.7 Apple Translation framework is not a drop-in local fallback
`TranslationSession` **cannot be instantiated directly** — you obtain it through the SwiftUI `.translationTask(_:action:)` modifier, i.e. it is bound to a live SwiftUI view. It does not work in the Simulator, and first use of a language pair may require a **system download flow that a keyboard extension cannot present.** **CONFIRMED for the API shape** (iOS 17.4+). **UNVERIFIED whether it functions inside a keyboard extension at all.** Prototype before listing it as a P2 local fallback.
> *(Note: Research 03 finds a headless `TranslationSession(installedSource:target:)` initialiser added in iOS 26.0 that removes the SwiftUI-view coupling. The two findings are compatible: the SwiftUI-bound path is the iOS 17.4/18 API; the headless path requires iOS 26. Extension viability remains UNVERIFIED in both reports and must be spiked.)*

### 7.8 Networking realities inside an extension
- The extension can be suspended/killed the moment the keyboard is dismissed; **in-flight `URLSession` tasks die with it.** Never rely on a request completing across a dismissal. **LIKELY**
- DNS + TLS handshake to a cold proxy from a freshly launched extension is a real first-request cost. Warm the connection on `viewDidAppear` if you want <1.5 s to be reachable on the first sentence.
- Background `URLSession` in a keyboard extension: **UNVERIFIED**, and pointless for a sub-second interactive feature.

### 7.9 Onboarding friction is a product risk
Enabling requires: install app -> Settings -> General -> Keyboard -> Keyboards -> Add New Keyboard -> pick yours -> tap it -> **Allow Full Access** -> accept a scary system warning. Every step is a funnel drop. Apple's own doc: "Enabling open access shouldn't be done lightly. Keyboards handle some of the most sensitive user data." **CONFIRMED**

### 7.10 Small but real
- `requestSupplementaryLexicon(completion:)` gives you `UILexicon` — common words, Address Book first/last names, and the user's Text Replacement shortcuts — **without Full Access.** Free autocorrect substrate; §24 should use it. **CONFIRMED**
- `PrimaryLanguage` in `NSExtensionAttributes` is a single string. Supporting EN + IT + ES from one keyboard target means either a **multilingual keyboard switching `primaryLanguage` dynamically** or **one target per language** (each appearing separately in Settings). §12 P0 implies the former; make the decision explicitly. **CONFIRMED**
- `IsASCIICapable` must be `true` to serve `.asciiCapable` fields properly. **CONFIRMED**
- **Simulator lies.** App Group writes succeed in the Simulator and fail on device; Translation doesn't run in the Simulator; memory limits aren't enforced. **All Full-Access and memory work must be validated on hardware.**

---

## 8. iOS 27 addendum — status as of 2026-08-18

### 8.1 Release status
- **iOS 27 announced at WWDC 2026-06-08**; developer beta 1 same day. **Beta 6 seeded 2026-08-17.** Ships ~September 2026. **CONFIRMED** — MacRumors 2026-06-08 and 2026-08-17.
- Current shipping release: **iOS 26.6.1** (2026-08-17). **CONFIRMED**

### 8.2 What changed for keyboard extensions in iOS 27 — **nothing at the API level**
- Apple's **"Update to UIKit" changelog, June 2026 section**, lists Core Location/Core Motion view alignment, compositional-layout observation tracking, Mac Catalyst controls, **scene-based life cycle requirement**, `UIDragInteraction.allowsPointerDragBeforeLiftDelay`, and TextKit 2 additions. **There is no keyboard-extension, `UIInputViewController`, or `UITextDocumentProxy` entry.** **CONFIRMED** — https://developer.apple.com/documentation/updates/uikit
- `UIInputViewController` and `UITextDocumentProxy` symbol graphs show **no beta symbols, no new members, no deprecations.** **CONFIRMED**
- **WWDC 2026 has no keyboard-extension or input-method session.** The only text-adjacent session is *"Elevate your app's text experience with TextKit"* (host-side rendering). **CONFIRMED**
- **Stated explicitly: no iOS 27 material specific to custom keyboard extensions was found. That absence is itself the finding — Apple has shipped no keyboard-extension improvements in iOS 26 or 27.** The platform is in maintenance mode for third-party keyboards while simultaneously changing the visuals around them (§7.4).

### 8.3 Newly required / deprecated for a project starting today

| Item | Impact | Confidence |
|---|---|---|
| **Scene-based life cycle is mandatory.** *"Beginning in iOS 27 … apps built with the latest SDK must adopt the scene-based life cycle or they fail to launch."* | Affects the **containing app**, not the extension. SwiftUI `App` lifecycle already satisfies it | **CONFIRMED** |
| iOS 27 marks many UIKit value types **explicitly non-`Sendable`** | New Swift-6 concurrency warnings when moving proxy-derived values off the main actor. `UITextDocumentProxy` is already `@MainActor` | **LIKELY** |
| **Nothing deprecated** for keyboard extensions | `application(_:shouldAllowExtensionPointIdentifier:)`, `RequestsOpenAccess`, `advanceToNextInputMode`, `handleInputModeList`, `requestSupplementaryLexicon` all current | **CONFIRMED** |

### 8.4 New iOS 27 capabilities a third-party keyboard could use
- **`LanguageModel` protocol + `PrivateCloudComputeLanguageModel`** in FoundationModels — one abstraction over on-device *and* server models, PCC offering "more reasoning capabilities and a larger context size." Maps directly onto LinguaKey's local/remote split. **CONFIRMED.** **Whether either is usable from a keyboard extension: UNVERIFIED** (see the rate-limiting issue, §7.6).
- New on-device `SystemLanguageModel` revision in iOS 27 — Apple explicitly warns to **re-test prompts** because the model changes under you on OS update. **CONFIRMED.** Relevant to §16's prompt contract.
- **No** relaxation of the emoji restriction (5.2.5 unchanged), **no** dictation/microphone relaxation, **no** new proxy APIs, **no** new input-method entitlements, **no** host-identity API. **CONFIRMED / CONFIRMED-by-absence**
- iOS/iPadOS 27 adds a **new sliding keyboard animation** and "the keyboard pops up more quickly" — cosmetic/system-level, may interact with the launch-flicker problem either way. **LIKELY** (press coverage). **Beta-subject-to-change.**

### 8.5 Deployment target recommendation

**Recommendation: `iOS 26.0` minimum, build with the iOS 27 SDK.**

- **Adoption (Apple, measured on devices transacting on the App Store 2026-06-07): 79 % of all iPhones and 86 % of iPhones introduced in the last four years already run iOS 26.** **CONFIRMED** — https://developer.apple.com/support/app-store/
- **iOS 18 (PRD §29) buys essentially nothing** and costs a lot: you'd support the pre-Liquid-Glass aesthetic *and* both iOS 26 aesthetics, and lose FoundationModels entirely.
- **Don't set iOS 27 as the floor yet** — beta 6, unshipped, and pinning before GM costs the entire iOS 26 install base for zero keyboard-relevant API gain.
- **Do build against the iOS 27 SDK** so the containing app satisfies the scene-lifecycle requirement from day one.
- Simpler rule given "personal use first": **develop on the iOS 27 beta on your own device from day one**, because the iOS 26/27 visual changes are exactly the class of problem to discover in Phase 0, not Phase 4.

### 8.6 Beta caveats
Everything in §8.4 and the keyboard-animation item is **from the iOS 27 beta and subject to change before GM.** All iOS 27 claims are from **publicly available** Apple developer documentation and public press — **no NDA material is involved** (Apple's WWDC/beta materials have been non-confidential since 2020). Re-verify §8.3 and §8.4 against the GM release notes in September 2026 before locking architecture.

---

## 9. PRD §4 — every wrong, outdated, or dangerously optimistic statement

| # | PRD §4 text | Verdict | Correction |
|---|---|---|---|
| 4.1 | "must use an iOS Custom Keyboard Extension based on `UIInputViewController`" | Correct | — |
| 4.2 | "`UITextDocumentProxy` … insert text, delete text, **inspect selected text**, **inspect limited context before/after the cursor**, adjust cursor position" | **Dangerously optimistic + incomplete** | (a) `selectedText` is **truncated for multi-line selections and frequently disagrees with the visible selection**; treat as a hint, never truth. (b) "limited context" hides the real risk: **paragraph-truncated, host-dependent, `nil` in some hosts after paste (Gmail/Mail), only the last ~2 sentences of pasted text in WhatsApp/Signal/Telegram.** There is **no documented length guarantee.** (c) Missing: `setMarkedText`/`unmarkText` (the *right* primitive for insert/code-switch), `documentIdentifier` (only reliable field-change signal), `hasText`, and **inheritance from `UITextInputTraits`** — read `isSecureTextEntry`, `keyboardType`, `autocapitalizationType`, `returnKeyType` off the proxy; the single most useful thing the PRD omits. (d) Every proxy access is an **IPC round trip**; none belong on the keypress path |
| 4.3 | "does **not receive unrestricted** network access by default" | **Understated to the point of being wrong** | It receives **no network access at all.** Apple: *"This sandbox's default configuration disallows access to the network."* |
| 4.4 | "`RequestsOpenAccess` must be enabled… check `hasFullAccess` before attempting remote functionality" | **Correct but incomplete in a way that breaks §19** | Full Access **also** gates: **writing to the App Group container** (incl. `UserDefaults(suiteName:)` writes — fails *silently* on device, works in Simulator), **`UIPasteboard`**, **haptics**, and **all audio/speaker access (so `AVSpeechSynthesizer`)**. It does **not** grant microphone access. Also: `hasFullAccess` is **unreliable in `viewDidLoad`**, there is **no change notification** (poll on appearance), and **toggling it terminates the extension and can SIGKILL the containing app** on first enable |
| 4.5 | "secure/password fields use the system keyboard" | Correct | Add: an app can toggle `isSecureTextEntry` dynamically, so **you must still check it yourself** and hard-disable the learning bar and networking. This is what actually delivers the §21 privacy promise |
| 4.6 | "some phone-related fields use the system keyboard" | Correct | Precisely: `.phonePad` and `.namePhonePad` |
| 4.7 | "third-party apps may explicitly block custom keyboards" | **Correct but §4's conclusion ("degrade gracefully when the extension is unavailable") is not actionable** | The mechanism is `application(_:shouldAllowExtensionPointIdentifier:)`. **There is nothing to degrade** — when an app opts out, your extension is *never launched*, and nothing is notified. You cannot detect it. Handle in onboarding copy, not code. Also: `UIApplicationSupportsCustomKeyboards` / `allowsCustomKeyboards` **do not exist** |
| 4.8 | "the extension runs separately from the containing app and **can be terminated by iOS**" | **Dangerously vague — the #1 operational risk gets one clause** | Dominant cause is **jetsam for exceeding a per-process memory limit of roughly 30-60 MB.** Failure mode: **silent — no crash dialog, no crash log; iOS swaps the user back to the previous keyboard mid-sentence.** Also: **dismissing the keyboard does not free your memory**, so leaks compound across host apps |
| — | **Missing entirely from §4** | | **No microphone, even with Full Access.** **No way to identify the host app and no way to return to it** (Apple DTS, 2026). **Cannot present modal UI.** **Cannot draw outside the keyboard's own frame.** **App Store 4.4.1: must remain functional without Full Access and without network** — the binding product constraint. **iOS 26 draws uncoverable grey margins in Apple's own apps.** **Launch resize flicker (~390 ms) is an unsolved platform problem.** **MDM can block third-party keyboards outright.** **Apple emoji artwork may not be bundled (5.2.5)** |

---

## 10. PRD §22 — every wrong, outdated, or dangerously optimistic statement

| # | PRD §22 text | Verdict | Correction |
|---|---|---|---|
| 22.1 | Keypress path: no network, no synchronous AI, no heavy DB, "key visual response should feel immediate" | Right instinct, **unquantified, missing the real hazard** | Set numbers: **8.3 ms frame budget on 120 Hz ProMotion**; key highlight must be a pre-baked state change with no re-layout. Add the missing rule: **no `textDocumentProxy` reads on the keypress path either** — every access is a cross-process round trip. Add: **no `adjustTextPosition` polling** |
| 22.2 | "cached result: effectively instant" | OK | Cache must be **byte-bounded**, in-memory, pre-warmed at `viewDidAppear`; do not open a DB to answer a cache hit |
| 22.3 | "**remote result: ideally <1.5 seconds**" | **Dangerously optimistic as stated** | Achievable at p50 with a warm connection and a small model, but nothing is budgeted for **cold DNS+TLS from a freshly-launched extension process** (add 200-600 ms on the first request after every app switch), **LLM time-to-first-token**, and **cellular variance.** Realistic: **p50 ~ 0.8-2.0 s, p95 ~ 3-6 s.** Mandate: warm the proxy connection on `viewDidAppear`; stream or return partial results; make the first request of a session speculative/silent |
| 22.4 | ">3 seconds: show a subtle loading state or suppress" | Backwards ordering + missing failure mode | Show the loading state **immediately on trigger** (not at 3 s) and **hard-cancel at ~3 s.** Missing: **when the keyboard is dismissed the extension is suspended/killed and in-flight `URLSession` tasks die** — §17's cancellation logic must treat "keyboard disappeared" as a cancellation cause, and §23 must not display a stale result on the next appearance (use `documentIdentifier` to invalidate) |
| 22.5 | "Memory: keyboard extensions have stricter runtime constraints… keep model state compact, caches bounded" | **Dangerously vague — no number, no failure mode, no instrumentation** | State the budget: **hard ceiling ~30-60 MB `phys_footprint`, varies by device; design to 40 MB with an alarm at 30 MB.** State the failure mode: **silent jetsam, no crash log, user bounced to the previous keyboard.** Required practices: implement `didReceiveMemoryWarning`; instrument `phys_footprint` via `task_vm_info` and log to the App Group on every appearance; test on the oldest supported device; **never trust the Simulator** |
| 22.6 | **Missing: emoji is the largest memory line item** | | Measured: **~10 MB per emoji page** plus `LazyVGrid` failing to release off-screen cells, causing monotonic growth. Decide in Phase 0 whether V1 ships an emoji key at all |
| 22.7 | **Missing: cold-start budget** | | The system's launch sequence takes ~390 ms to settle your height, and the flicker is currently **unavoidable.** Your view hierarchy must be constructible in **<100 ms** with **zero disk I/O, zero JSON decode, zero DB open before first paint.** This is a per-app-switch cost |
| 22.8 | **Missing: replace-sentence cost** | | `deleteBackward()` is the only deletion primitive; replacing a 40-char sentence = 40 IPC round trips, visible character-by-character erasure, and a polluted host undo stack. Set a cap (<=120 chars), prefer `setMarkedText` where hosts honour it, and add a §27 acceptance test for replacement in Messages, WhatsApp, and Safari |
| 22.9 | **§22 does not reconcile with §12-P2 / §8** | **Contradiction** | §8 and §12-P2 contemplate on-device model experimentation and a local translation fallback. Inside a 30-60 MB extension **an embedded LLM is arithmetically impossible**, and Apple's `TranslationSession` (pre-26) can only be vended by a SwiftUI `.translationTask`. The only viable on-device path is **`SystemLanguageModel`** — itself **rate-limited for background/extension processes on battery.** Either delete these items or reclassify as **host-app-only, spike-first** |
| 22.10 | **§29 "SwiftUI where practical" is unqualified** | | Viable in 2026, **but only if the key grid is isolated from per-keystroke state.** Any observable that mutates on every keypress must not be observed by the ~30 key views. Watch `LazyVGrid`/`LazyVStack` retention |

---

## 11. Adjacent PRD corrections

- **§5 (KeyboardKit):** understated. **Now closed-source in its entirety.** The abstraction layer in §5.3 is **mandatory**; OpenKeyboardKit is a 1-star fork, i.e. "you now own a keyboard framework."
- **§19 (Persistence):** **writes from the keyboard require Full Access.** Design the no-Full-Access path as: keyboard **reads** shared settings, buffers vocabulary deltas in its **own** container, and the host app drains them. Otherwise LinguaKey silently loses all learning state for any user who declines Full Access.
- **§24 (Autocorrect):** **haptics require Full Access**; **key click sound does not** (adopt `UIInputViewAudioFeedback`). Also `requestSupplementaryLexicon` gives common words + Address Book names + the user's Text Replacement shortcuts **free, without Full Access** — the PRD never mentions `UILexicon`.
- **§29 (Minimum target iOS 18+):** -> **iOS 26** (79 % of all iPhones as of 2026-06-07), built against the iOS 27 SDK.
- **§27 (Acceptance tests):** add — memory stays under 40 MB after 5 minutes of typing incl. emoji; keyboard survives 20 host-app switches without a jetsam; sentence replacement is correct in Messages, WhatsApp, Safari, Gmail, and a WKWebView; the keyboard is fully usable with Full Access **off** (guideline 4.4.1); learning bar disabled in secure/email/URL/number fields.

---

## 12. Key sources

Apple primary: [Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard) · [Handling text interactions](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards) · [Configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) · [UITextDocumentProxy](https://developer.apple.com/documentation/uikit/uitextdocumentproxy) · [UIInputViewController](https://developer.apple.com/documentation/uikit/uiinputviewcontroller) · [hasFullAccess](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/hasfullaccess) · [shouldAllowExtensionPointIdentifier](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:shouldallowextensionpointidentifier:)) · [playInputClick](https://developer.apple.com/documentation/uikit/uidevice/playinputclick()) · [App Extension Programming Guide: Custom Keyboard (archived)](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) · [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Scene-based life cycle](https://developer.apple.com/documentation/UIKit/transitioning-to-the-uikit-scene-based-life-cycle) · [Update to UIKit](https://developer.apple.com/documentation/updates/uikit) · [Update to FoundationModels](https://developer.apple.com/documentation/updates/foundationmodels) · [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) · [Translation](https://developer.apple.com/documentation/translation) · [App Store iOS usage](https://developer.apple.com/support/app-store/) · [WWDC 2026 sessions](https://developer.apple.com/videos/wwdc2026/)

Apple Developer Forums: 813579 (launch flicker) · 800838 (iOS 26 grey margins) · 826851 (no host identity, DTS reply) · 812642 (Gmail paste nil context, DTS engaged) · 772158 (paste returns last two sentences) · 45121 (textDidChange not called) · 728434 (App Group write requires RequestsOpenAccess) · 751384 (host app SIGKILLed on first Full Access enable) · 789788 (FoundationModels rate limit in extensions, Apple engineer reply) · 709107 (AVAudioSession failure in keyboard extension) · 800500 (mic workaround) · 63493 (haptics require Full Access) · 105815 (30 MB crash) · 787687 (iOS 26 inputAccessoryView regression)

GitHub / other: [KeyboardKit #757](https://github.com/KeyboardKit/KeyboardKit/issues/757) (emoji memory) · [KeyboardKit #83](https://github.com/KeyboardKit/KeyboardKit/issues/83) · [KeyboardKit](https://github.com/KeyboardKit/KeyboardKit) · [OpenKeyboardKit](https://github.com/valomedia/OpenKeyboardKit) · [react-native #31910](https://github.com/facebook/react-native/issues/31910) · [openradar-mirror #8945](https://github.com/lionheart/openradar-mirror/issues/8945) · [MacRumors iOS 27 beta 1](https://www.macrumors.com/2026/06/08/apple-releases-ios-27-beta-1/) · [MacRumors iOS 27 beta 6](https://www.macrumors.com/2026/08/17/apple-seeds-sixth-ios-27-developer-beta/)
