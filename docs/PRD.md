# PRD — Spanish Learning Keyboard for iPhone

**Working name:** LinguaKey  
**Version:** v0.1  
**Date:** 2026-08-18  
**Platform:** iPhone / iOS 18+  
**Primary user:** Personal use first  
**Source languages:** English, Italian  
**Target language:** Spanish only

---

## 1. Product Overview

LinguaKey is a system-wide custom iOS keyboard that teaches Spanish while the user writes normal messages in English or Italian.

The keyboard should feel as close as practical to the native Apple keyboard while adding a compact learning layer above the keys. Instead of requiring separate lessons, the product turns normal typing in apps such as Messages, WhatsApp, Mail, Notes, Safari, Instagram, and other text fields into contextual Spanish exposure and active recall.

The product is not intended to be a general translator. Its core purpose is to progressively reduce dependence on English/Italian by helping the user produce Spanish naturally.

### Core loop

1. User types normally in English or Italian.
2. The keyboard detects the current source language.
3. After a short pause, punctuation, or explicit action, the current phrase/sentence is analyzed.
4. A Spanish equivalent is shown in the learning bar.
5. Known words are deemphasized; useful/new words are highlighted.
6. The user can:
   - view the translation,
   - insert the Spanish version,
   - hear pronunciation,
   - save a word,
   - ask for a short grammar explanation,
   - attempt active recall.
7. The system updates the user's familiarity model for encountered Spanish vocabulary and constructions.

---

## 2. Product Goals

### Primary goals

- Make Spanish learning happen inside the user's existing phone behavior.
- Keep the keyboard usable as the user's default everyday keyboard.
- Support English -> Spanish and Italian -> Spanish only.
- Make assistance adaptive rather than repeatedly translating words the user already knows.
- Preserve low latency for normal typing.
- Minimize the amount of typed text sent to remote services.
- Make the user progressively type more Spanish over time.

### Success condition

The user should be able to leave LinguaKey enabled as the default keyboard for normal daily messaging without feeling that the learning functionality interferes with typing.

---

## 3. Non-Goals for V1

- Android support.
- Languages other than English, Italian, and Spanish.
- Full Duolingo-style course structure.
- Social features, leaderboards, streak pressure, or gamification-heavy UX.
- Scraping or reading complete conversations inside third-party apps.
- Password-field support.
- Building a general-purpose AI writing assistant.
- Cloud accounts or multi-user infrastructure unless needed later.
- Monetization or App Store launch requirements for the first version.

---

## 4. Technical Constraints Confirmed by Apple

### Custom keyboard architecture

The product must use an iOS Custom Keyboard Extension based on `UIInputViewController`.

The extension does not directly access the host app's text field. It interacts through `UITextDocumentProxy`, which provides functions including:

- insert text,
- delete text,
- inspect selected text,
- inspect limited context before/after the cursor,
- adjust cursor position.

### Network access

A keyboard extension does not receive unrestricted network access by default.

To call a remote API from the keyboard:

- `RequestsOpenAccess` must be enabled in the keyboard extension configuration.
- The user must manually enable **Allow Full Access** for the keyboard in iOS Settings.
- The keyboard should check `hasFullAccess` before attempting remote functionality.

### System limitations

The keyboard cannot be guaranteed to appear everywhere.

Examples:

- secure/password fields use the system keyboard,
- some phone-related fields use the system keyboard,
- third-party apps may explicitly block custom keyboards,
- the extension runs separately from the containing app and can be terminated by iOS.

The product must therefore degrade gracefully when the extension is unavailable or restarted.

---

## 5. Recommended Keyboard Foundation

### Preferred starting point: KeyboardKit

Use KeyboardKit as the initial keyboard UI/interaction foundation rather than reproducing every Apple keyboard behavior from zero.

Repository:

`https://github.com/KeyboardKit/KeyboardKit`

Reasons:

- specifically designed for iOS/iPadOS keyboard extensions,
- Swift + SwiftUI,
- native-looking customizable keyboard UI,
- actions and gestures,
- proxy abstractions,
- layout utilities,
- autocomplete/autocorrect infrastructure,
- active maintenance as of 2026.

### Licensing note

The current KeyboardKit distribution has moved away from the historical fully open-source model and includes proprietary/paid functionality. Confirm that the current license is acceptable before making it a hard architectural dependency.

### Fully open-source fallback

OpenKeyboardKit is an MIT-licensed fork of the last open-source KeyboardKit version:

`https://github.com/valomedia/OpenKeyboardKit`

Tradeoff:

- fully inspectable and modifiable,
- no commercial dependency,
- less actively maintained than upstream KeyboardKit.

### Architecture decision

For V1:

1. Prototype with KeyboardKit for speed.
2. Isolate all KeyboardKit-specific code behind a small keyboard abstraction layer.
3. Keep the learning engine, API layer, persistence, and state model independent of KeyboardKit.
4. If licensing or framework limitations become problematic, replace the keyboard renderer without rewriting the product logic.

---

## 6. High-Level Architecture

```text
LinguaKey iOS App
|
|-- Host App
|   |-- onboarding
|   |-- keyboard setup instructions
|   |-- language settings
|   |-- API / backend configuration
|   |-- vocabulary dashboard
|   |-- learning statistics
|   |-- review screen
|   |-- privacy controls
|   `-- shared persistent settings
|
|-- Keyboard Extension
|   |-- Keyboard UI
|   |-- UITextDocumentProxy adapter
|   |-- source language detector
|   |-- context extractor
|   |-- debounce / trigger engine
|   |-- learning bar
|   |-- suggestion actions
|   |-- local vocabulary cache
|   |-- local phrase cache
|   `-- API client
|
|-- Shared Core
|   |-- translation model
|   |-- vocabulary model
|   |-- learning-state engine
|   |-- spaced repetition
|   |-- language utilities
|   |-- cache
|   `-- telemetry interface
|
`-- Optional Backend Proxy
    |-- secret API key
    |-- request authentication
    |-- model call
    |-- prompt enforcement
    |-- rate limiting
    `-- minimal logging / no text retention
```

---

## 7. API-Key Strategy

### Answer: yes, an API can be integrated

The keyboard can call a remote AI/translation API when Full Access is enabled.

However, the production design must **not hard-code a secret provider API key inside the iOS application or keyboard extension**.

For OpenAI specifically, current official guidance explicitly advises against deploying API keys inside client-side environments such as mobile apps.

### Recommended architecture

```text
Keyboard Extension
      |
      | HTTPS
      v
Tiny authenticated proxy
      |
      | provider secret stored server-side
      v
AI / translation API
```

Suitable proxy options include a minimal serverless function or worker. The proxy needs only one or a few endpoints and no conventional backend database is required for V1.

### Personal development mode

Because this is initially a personal-only sideloaded app, an optional **Developer BYOK Mode** may be supported:

- API key entered manually in the host app,
- stored in Keychain rather than source code or plist,
- shared with the extension through an appropriately configured Keychain access group if required,
- never committed to Git,
- direct API calls allowed only when Full Access is enabled.

This mode is acceptable for private experimentation but should be removed or disabled before distributing the app.

### API role in the product

The API should **not be called for every keypress**.

Remote inference should be triggered by:

- sentence-ending punctuation,
- space + idle debounce,
- explicit translate button,
- explicit explain button,
- explicit correction request,
- active-recall generation.

Target debounce after user stops typing: **500–900 ms**, configurable during testing.

---

## 8. Local vs Remote Processing

### Local operations

Perform locally whenever possible:

- keyboard rendering,
- keypress handling,
- capitalization state,
- cached autocomplete,
- source language detection,
- context extraction,
- vocabulary lookup,
- mastery scoring,
- spaced repetition state,
- cached translations,
- deciding whether an API request is necessary.

### Remote operations

Use the API for:

- high-quality English -> Spanish translation,
- high-quality Italian -> Spanish translation,
- grammar-aware corrections,
- concise grammar explanations,
- alternative natural phrasing,
- identifying the pedagogically important part of a sentence,
- generating active-recall prompts.

### Optional Apple frameworks

Where useful, Apple on-device frameworks may later be used for:

- language identification,
- local translation fallback,
- speech synthesis/pronunciation,
- local ML inference.

The architecture must not depend on remote AI for basic keyboard operation.

---

## 9. Source Language Handling

Supported source modes:

- **Auto**
- **English**
- **Italiano**

Default: **Auto**.

### Auto-detection

Detect whether the current sentence is primarily English or Italian.

Rules:

1. Use local language recognition first.
2. Require a reasonable minimum amount of text before changing language state.
3. Avoid oscillating source language on short words that exist in both languages.
4. Show the detected source language unobtrusively in the learning bar.
5. Allow immediate manual override.

Example:

```text
[ AUTO · IT -> ES ]   hoy... suggestion
```

The target language is permanently Spanish in V1.

---

## 10. Keyboard UX

### Principle

The keyboard must remain a keyboard first and a language-learning interface second.

The learning UI should occupy one compact strip above the normal suggestion row or replace the suggestion row when active.

### Normal state

```text
+------------------------------------------+
| ES  llegar = arrive        speaker  star |
+------------------------------------------+
| Q  W  E  R  T  Y  U  I  O  P            |
|  A  S  D  F  G  H  J  K  L              |
|   Z  X  C  V  B  N  M                    |
| 123   globe     space        return      |
+------------------------------------------+
```

### Translation result state

User types:

> I'll probably arrive around eight

Learning bar:

```text
Probablemente llegaré sobre las ocho.
[Insert ES] [Explain] [speaker] [star]
```

### Italian example

User types:

> Probabilmente arriverò verso le otto

Learning bar:

```text
Probablemente llegaré sobre las ocho.
[Insert ES] [Explain] [speaker] [star]
```

### Tap behavior

- Tap Spanish sentence -> optionally replace current source sentence with Spanish.
- Long press Spanish sentence -> expanded breakdown.
- Tap highlighted word -> definition + pronunciation.
- Tap star -> save word/construction.
- Tap Explain -> short teaching card.
- Swipe/collapse -> hide learning UI without changing keyboard state.

---

## 11. Core Learning Modes

### Mode A — Passive Translation

Show a natural Spanish version of the user's source sentence.

Best for early learning.

### Mode B — Highlighted Learning

Show the complete Spanish sentence but emphasize only unfamiliar or currently-learning vocabulary.

Example:

```text
Probablemente LLEGARE sobre las ocho.
            ^ new construction
```

### Mode C — Hybrid / Code-Switch

Gradually replace known source-language concepts with Spanish.

Example progression:

```text
I'll probably arrive around eight.

Probablemente I'll llegar around ocho.

Probablemente llegaré sobre las ocho.
```

### Mode D — Active Recall

Hide a word the model predicts the user should know.

```text
Probablemente ______ sobre las ocho.
Hint: arrive / arrivero
```

### Mode E — Spanish Correction

When the user writes directly in Spanish, detect errors and offer minimal correction.

User:

```text
creo que voy estar tarde
```

Suggestion:

```text
creo que voy a llegar tarde
              ^
```

Actions:

```text
[Fix] [Why?] [Ignore]
```

---

## 12. V1 Feature Requirements

### P0 — Required

- Native-feeling QWERTY keyboard.
- English keyboard layout.
- Italian typing support.
- Spanish accented character access.
- Shift, caps lock, delete, space, return, numbers/symbols.
- Globe / next keyboard behavior compliant with iOS requirements.
- `UITextDocumentProxy` text insertion/deletion.
- Source language toggle: Auto / EN / IT.
- English -> Spanish translation.
- Italian -> Spanish translation.
- Learning bar above keyboard.
- Tap to insert Spanish translation.
- Tap to dismiss suggestion.
- API request debounce.
- Request cancellation when text changes.
- Translation cache.
- Basic vocabulary tracking.
- Main app onboarding.
- Keyboard enabled/full-access status page.
- Shared App Group settings.
- Graceful offline/no-Full-Access state.
- Privacy setting to disable remote processing instantly.

### P1 — Strongly desired

- Short grammar explanation.
- Word tap breakdown.
- Pronunciation using system TTS.
- Save vocabulary.
- Basic spaced repetition.
- Spanish-input correction mode.
- Familiarity scoring.
- Hybrid code-switch mode.
- Learning-level control.
- Translation history stored locally.

### P2 — Later

- Swipe typing.
- Advanced autocorrect.
- next-word prediction.
- richer conjugation cards.
- automatic CEFR estimation.
- on-device model experimentation.
- local translation fallback.
- detailed learning analytics.
- iPad layouts.

---

## 13. Learning-State Model

Each vocabulary item should have a persistent local record.

Example data structure:

```json
{
  "lemma": "llegar",
  "language": "es",
  "meaning_en": "to arrive",
  "meaning_it": "arrivare",
  "exposures": 8,
  "successful_recalls": 5,
  "failed_recalls": 2,
  "last_seen_at": "2026-08-18T21:30:00+02:00",
  "next_review_at": "2026-08-20T09:00:00+02:00",
  "mastery": 0.72,
  "status": "learning"
}
```

### Suggested mastery states

```text
0.00–0.20   New
0.20–0.50   Learning
0.50–0.80   Familiar
0.80–0.95   Strong
0.95–1.00   Mastered
```

Do not show explicit mastery percentages in the keyboard UI unless useful for debugging. They are internal decision variables.

---

## 14. Adaptation Logic

The keyboard should choose the least intrusive teaching intervention that still produces useful learning.

Example policy:

```text
if mastery < 0.20:
    show translation + meaning
elif mastery < 0.50:
    show translation + highlight
elif mastery < 0.80:
    show partial hint
elif mastery < 0.95:
    occasionally ask recall
else:
    normally show nothing
```

Additional factors:

- recency,
- number of exposures,
- repeated mistakes,
- whether the word is important/common,
- whether the sentence contains a useful grammar construction,
- amount of learning UI shown recently.

The system should intentionally avoid teaching too many things simultaneously.

### Per-sentence teaching budget

Default maximum:

- **1 primary vocabulary concept**, and
- **1 grammar note only when valuable**.

---

## 15. API Contract

### Endpoint

```text
POST /v1/assist
```

### Request

```json
{
  "sourceLanguage": "en",
  "targetLanguage": "es",
  "text": "I'll probably arrive around eight",
  "mode": "translate_and_teach",
  "knownVocabulary": ["ocho", "sobre"],
  "learningVocabulary": ["llegar"],
  "desiredDifficulty": 0.35
}
```

### Response

```json
{
  "translation": "Probablemente llegaré sobre las ocho.",
  "focus": {
    "surface": "llegaré",
    "lemma": "llegar",
    "meaning": "to arrive",
    "meaningItalian": "arrivare",
    "explanation": "Llegaré is the first-person future form of llegar."
  },
  "alternatives": [],
  "confidence": 0.98
}
```

### Requirements

- Strict structured output.
- No markdown in API responses.
- No conversational filler.
- Request timeout.
- Cancellation support.
- Retry only for transient errors.
- Cache identical/normalized requests.
- Maximum context length limited to what is needed for the current sentence/phrase.

---

## 16. Suggested AI System Behavior

The model should behave as a Spanish tutor embedded inside a keyboard.

Core rules:

1. Translate naturally, not word-for-word.
2. Source language is English or Italian only.
3. Target language is always standard Spanish.
4. Return the shortest useful explanation.
5. Prefer common everyday Spanish.
6. Teach at most one important new concept unless explicitly requested.
7. Preserve names, URLs, handles, codes, and obvious technical tokens.
8. Do not moralize or add unrelated commentary.
9. Do not expand the user's sentence unless necessary for a natural translation.
10. Return JSON matching the API schema exactly.

---

## 17. Trigger Engine

Do not send a request while the user is rapidly typing.

### Trigger conditions

Request may fire when any of the following occurs:

- user enters `.`, `?`, `!`, or newline,
- user pauses for the debounce period,
- user taps the learning/translate button.

### Cancellation

When the source sentence materially changes before the previous response returns:

1. cancel the old request,
2. invalidate its response,
3. wait for the next stable state.

Never display a stale translation for text that is no longer current.

---

## 18. Context Extraction

Use `documentContextBeforeInput` and `documentContextAfterInput` conservatively.

The keyboard should normally send only the current sentence or current clause needed for accurate translation.

### Rules

- Prefer current sentence over full paragraph.
- Hard-cap remote context length.
- Do not send previous conversation messages that are not part of the current input field context.
- Strip obvious passwords/tokens where detectable.
- Never retain remote-request text by default.

---

## 19. Persistence

### App Group

Use an App Group for data that must be shared between the host app and keyboard extension.

Shared data:

- language mode,
- learning mode,
- difficulty setting,
- vocabulary state,
- cached translations,
- onboarding state,
- privacy preferences,
- API/backend configuration that is safe to share.

### Recommended storage

V1:

- `UserDefaults(suiteName:)` for small settings.
- SQLite / SwiftData/Core Data or a compact local store for vocabulary and history.
- Keychain for credentials/tokens.

The keyboard extension must not depend on large synchronous database work in the critical keypress path.

---

## 20. Host App

The containing app should be deliberately simple.

### Screen 1 — Setup

Show:

- keyboard installed status,
- keyboard enabled status,
- Full Access status,
- step-by-step link/instructions for enabling the keyboard.

### Screen 2 — Learning

Show:

- words encountered,
- words learning,
- words mastered,
- recent vocabulary,
- review due.

### Screen 3 — Settings

Controls:

- source: Auto / English / Italian,
- target: Spanish (locked),
- mode: Passive / Adaptive / Recall,
- learning intensity,
- remote AI on/off,
- pronunciation on/off,
- store translation history on/off,
- clear local history,
- backend/API configuration.

### Screen 4 — Review

Simple flashcard review generated from words encountered during real typing.

The app should not become the main learning experience; the keyboard remains the primary product.

---

## 21. Privacy Requirements

### Default principles

- Process locally whenever practical.
- Send the smallest useful unit of text to the backend.
- Do not send data on every keystroke.
- Do not persist raw typed text remotely by default.
- Make remote processing clearly controllable.
- Never process secure/password fields because iOS excludes the custom keyboard there anyway.

### User-visible Full Access explanation

The onboarding screen must clearly explain that iOS requires Full Access for network-backed AI features and that this technically permits the keyboard to transmit typed text.

The product should explain what it actually sends:

> Only the current phrase/sentence needed for translation or teaching is sent when AI assistance is triggered. Normal keypresses are handled locally.

---

## 22. Performance Requirements

### Keypress path

- No network dependency.
- No synchronous AI work.
- No heavy database queries.
- Key visual response should feel immediate.

### AI suggestion target

Desired perceived response:

- cached result: effectively instant,
- remote result: ideally < 1.5 seconds,
- > 3 seconds: show a subtle loading state or suppress the suggestion rather than blocking typing.

### Memory

Keyboard extensions have stricter runtime constraints than normal apps. Keep:

- model state compact,
- caches bounded,
- images/assets minimal,
- large processing outside the keypress path.

---

## 23. Failure States

### No Full Access

Keyboard remains fully usable for typing.

Learning bar shows optional local functionality only and a small status indicator when the user explicitly requests a remote feature.

### No network

- continue typing normally,
- use cached translations if available,
- do not repeatedly display network errors.

### API timeout/error

- silently discard non-critical requests,
- never block text entry,
- expose detailed diagnostics only in developer settings.

### Extension restart

Reload settings and vocabulary state from shared persistent storage.

---

## 24. Autocorrect Strategy

A poor typing experience will kill the product faster than weak AI.

### V1

Prioritize:

- correct key sizing,
- native-looking spacing,
- capitalization,
- double-space period,
- delete repeat behavior,
- press callouts,
- haptic/audio feedback where allowed,
- basic English/Italian suggestions.

### Later

Improve:

- autocorrect ranking,
- next-word prediction,
- typo probability based on nearby keys,
- Spanish prediction while in Spanish mode.

Do not delay the learning engine until autocorrect is perfect, but do not consider the keyboard usable until normal typing feels acceptable for daily messaging.

---

## 25. Visual Design

### Design target

Visually approximate the native iOS keyboard rather than inventing a branded keyboard UI.

Use:

- system typography,
- system semantic colors,
- familiar key geometry,
- native dark/light appearance,
- subtle learning highlight only in the top bar.

Avoid:

- persistent gradients,
- large logos,
- gamification graphics,
- excessive icons,
- multi-row teaching panels during normal typing.

The learning UI should disappear when it has nothing useful to teach.

---

## 26. Development Phases

### Phase 0 — Keyboard shell

Deliver:

- host app + keyboard extension,
- keyboard activation instructions,
- native-looking QWERTY layout,
- working text insertion/deletion,
- shift/caps/numbers/symbols/globe,
- App Group.

Acceptance:

The keyboard can replace the Apple keyboard for ordinary short messages without crashes.

### Phase 1 — Translation MVP

Deliver:

- EN/IT source selection,
- Auto language detection,
- Spanish translation bar,
- debounced API request,
- insert translation,
- cache,
- loading/error behavior.

Acceptance:

User can type English or Italian in WhatsApp/Notes/Messages and reliably see a natural Spanish equivalent without interrupting typing.

### Phase 2 — Learning engine

Deliver:

- word extraction,
- vocabulary records,
- mastery score,
- highlighted teaching focus,
- save word,
- pronunciation,
- host-app vocabulary view.

Acceptance:

Repeated words produce less intrusive assistance over time.

### Phase 3 — Adaptive recall

Deliver:

- active recall,
- hybrid code-switching,
- spaced repetition,
- Spanish correction mode.

Acceptance:

The keyboard can transition a recurring phrase from full translation to active Spanish production based on demonstrated familiarity.

### Phase 4 — Polish

Deliver:

- improved autocorrect,
- performance tuning,
- keyboard-state edge cases,
- orientation/device testing,
- analytics/debug screen,
- privacy hardening.

---

## 27. V1 Acceptance Tests

### Typing

- User can type a normal English message with no AI response required.
- User can type a normal Italian message with no AI response required.
- Delete/shift/space/return work continuously.
- Keyboard does not freeze while a remote request is running.

### Translation

- English sentence -> natural Spanish output.
- Italian sentence -> natural Spanish output.
- Stale API responses never overwrite newer suggestions.
- Translation can be inserted with one tap.

### Learning

- New Spanish vocabulary can be saved.
- Repeated exposure increments local learning state.
- Known terms are progressively deemphasized.

### Privacy

- Remote requests do not occur when remote processing is disabled.
- Remote requests do not occur without Full Access.
- API credentials are absent from source control.

### Failure

- Network loss does not impair normal typing.
- API failure does not impair normal typing.
- Keyboard process restart restores settings.

---

## 28. Suggested Repository Structure

```text
LinguaKey/
|
|-- LinguaKeyApp/
|   |-- App/
|   |-- Features/
|   |   |-- Onboarding/
|   |   |-- Dashboard/
|   |   |-- Review/
|   |   `-- Settings/
|   `-- Resources/
|
|-- LinguaKeyKeyboard/
|   |-- KeyboardViewController.swift
|   |-- KeyboardRootView.swift
|   |-- LearningBar/
|   |-- Input/
|   |-- Context/
|   `-- ExtensionState/
|
|-- LinguaKeyCore/
|   |-- Models/
|   |-- Language/
|   |-- Learning/
|   |-- Translation/
|   |-- Persistence/
|   |-- Networking/
|   `-- Utilities/
|
|-- LinguaKeyTests/
|   |-- LearningEngineTests/
|   |-- LanguageDetectionTests/
|   |-- TranslationParserTests/
|   `-- ContextExtractionTests/
|
`-- docs/
    `-- PRD.md
```

---

## 29. Recommended Implementation Decisions

| Area | Decision |
|---|---|
| UI | SwiftUI where practical, hosted by keyboard extension |
| Keyboard foundation | KeyboardKit prototype; abstraction layer around dependency |
| Minimum target | iOS 18+ |
| Source languages | English + Italian |
| Target language | Spanish |
| Source detection | Local auto-detection + manual override |
| Remote API | Provider-agnostic proxy |
| API key | Server-side for real use; Keychain BYOK only for private dev mode |
| Networking | Async/await with cancellation |
| Shared settings | App Group UserDefaults |
| Secrets | Keychain / server-side secret store |
| Vocabulary store | Local persistent database |
| Translation cache | Local bounded cache |
| TTS | AVSpeechSynthesizer initially |
| Learning algorithm | deterministic mastery + spaced repetition before LLM personalization |
| Privacy | sentence-level requests, remote processing opt-out |

---

## 30. Build Priority

The order of importance should be:

1. **Typing quality**
2. **Reliability**
3. **Fast translation**
4. **Low-friction teaching UI**
5. **Adaptive learning**
6. **Advanced AI features**

The product should never sacrifice the basic keyboard experience to expose more learning features.

---

## 31. Final V1 Definition

V1 is complete when the user can:

1. Install the app on an iPhone.
2. Enable LinguaKey as a system keyboard.
3. Use it comfortably for normal typing.
4. Type in English or Italian.
5. Automatically or manually request a Spanish equivalent.
6. Insert the Spanish phrase directly into the active app.
7. Tap one important Spanish word for a short explanation/pronunciation.
8. Have encountered vocabulary stored locally.
9. See assistance become progressively less explicit as vocabulary becomes familiar.
10. Disable all remote AI functionality while retaining a functional keyboard.

---

## 32. Verified Technical References — 2026-08-18

### Apple

- Creating a Custom Keyboard — Apple Developer Documentation  
  `https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard`

- Handling Text Interactions in Custom Keyboards — Apple Developer Documentation  
  `https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards`

- Configuring Open Access for a Custom Keyboard — Apple Developer Documentation  
  `https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard`

### Keyboard foundations

- KeyboardKit  
  `https://github.com/KeyboardKit/KeyboardKit`

- OpenKeyboardKit — MIT fork of the last open-source KeyboardKit  
  `https://github.com/valomedia/OpenKeyboardKit`

### API-key security

- OpenAI — Best Practices for API Key Safety  
  `https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety`

---

## 33. Product Principle

> **A normal iPhone keyboard that quietly teaches Spanish through the messages the user was already going to type.**

Every feature should be evaluated against that sentence.
