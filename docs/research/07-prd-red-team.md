# Research 07 — Adversarial Red Team of PRD v0.1

> Source: hostile-review subagent, 2026-08-18. Reproduced verbatim.
> Verdict: the PRD is a competent technical brief wrapped around an unvalidated product mechanic.

**Verdict up front:** the document is a competent *technical* brief wrapped around an unvalidated *product* mechanic. The engineering constraints (§4, §7, §21) are largely correct and well-researched. The core loop (§1) does not survive contact with the primary use case (WhatsApp, §26 Phase 1 acceptance). Roughly 60% of the "P0" list is not needed for a usable artifact, and the two things that would actually make it usable are not in P0 at all.

---

## 1. Internal Contradictions

**F1. Two different, incompatible trigger specifications. (§7 "API role in the product" vs §17 "Trigger conditions") — BLOCKER**
§7 lists six triggers including "space + idle debounce". §17 lists three, omits the space precondition, and *adds* newline. An engineer implementing §17 fires on any 700 ms pause mid-word; implementing §7 fires only after a space. These produce materially different request volumes and different privacy footprints.
*Failure:* whichever is built, the other section becomes the spec for QA, and the acceptance test in §27 ("stale API responses never overwrite newer suggestions") passes against a trigger model nobody agreed to.
*Fix:* delete the §7 list. §17 is the single normative source. Specify exactly: `fire := (lastChar in {. ? !} AND nextChar == space|EOF) OR (idleMs >= D AND charsSinceLastFire >= 8 AND currentSegment != lastFiredSegment) OR explicitTap`. Name D. Name the dedupe rule.

**F2. "Newline" as a trigger is a no-op in the flagship app. (§17 line 668 vs §26 Phase 1 acceptance, line 937) — BLOCKER**
In Messages, WhatsApp, Instagram DM and Slack, Return **sends the message**. `returnKeyType` is `.send`/`.default`-as-send. By the time a newline reaches the proxy, the text field is empty and the message is gone.
*Failure:* the user types "voy a llegar tarde", hits send, and 700 ms later a Spanish suggestion appears above an empty field, offering to insert into their *next* message.
*Fix:* remove newline as a trigger. Add a normative rule: **on `textDocumentProxy` transitioning to empty, cancel all in-flight requests and clear the bar.** Add it to §27 as a test.

**F3. "Do not call the API for every keypress" (§7 line 246, §21 line 781) is technically true and practically false. — MAJOR**
A 500-900 ms debounce (§7 line 258) fires constantly during real composition: word-finding pauses, glancing up, walking, being interrupted. Empirically a 20-word chat message contains 4-8 pauses over 700 ms. Each fire sends the **full growing prefix**. So a single sentence generates 5+ requests carrying nested supersets of the same text.
*Failure:* the user-facing privacy copy in §21 line 792 ("Only the current phrase/sentence needed for translation is sent when AI assistance is triggered") is misleading — over a day, effectively the entire typed corpus is transmitted 3-6x redundantly.
*Fix:* require sentence *completeness* before auto-fire (terminal punctuation or >=N tokens with a stable tail for >=1.2 s), plus a per-minute request ceiling, plus prefix-suppression (do not fire if the new segment is a prefix-extension of one fired <3 s ago). Rewrite the §21 copy to say "each sentence may be sent more than once as you revise it."

**F4. §22 forbids heavy DB work on the keypress path; §14 + §8 + §15 require exactly that. — MAJOR**
§22 line 802: "No heavy database queries" on the keypress path. §8 line 265 puts *vocabulary lookup, mastery scoring, spaced-repetition state, and "deciding whether an API request is necessary"* in the local column — all of which run on text change. §14's policy branches on per-lemma mastery. §15's request body requires assembling `knownVocabulary` + `learningVocabulary`.
*Failure:* a SwiftData/Core Data fetch on the main thread inside `textDidChange` in a ~50 MB extension. First keystroke after keyboard launch stalls 200-400 ms while the store opens; user perceives a dropped key.
*Fix:* mandate an in-memory, immutable snapshot of the vocabulary model loaded once per keyboard appearance on a background actor, with all keypress-path decisions reading only that snapshot. Writes are append-only to a queue, flushed on `viewWillDisappear`. State it as a hard architectural rule, not a performance aspiration.

**F5. The translation cache (§12 P0, §15 "Cache identical/normalized requests") is defeated by the request schema (§15). — MAJOR**
The request includes `knownVocabulary`, `learningVocabulary` and `desiredDifficulty`. These mutate after every exposure. The cache key therefore changes for identical source text.
*Failure:* near-zero hit rate. §22's "cached result: effectively instant" path never executes; every repeat of "sto arrivando" costs a round trip.
*Fix:* split the endpoint. `/translate` keyed on `(normalizedText, srcLang)` only -> cacheable forever. `/teach` takes the translation plus learner state -> cheap, optionally local. Cache key = SHA of normalized source text + source lang + prompt version.

**F6. §10 makes the learning bar replace the suggestion row; §24 + §30 make typing suggestions the #1 priority. — MAJOR**
§10 line 342: the learning UI "replace[s] the suggestion row when active." §24 lists "basic English/Italian suggestions" as V1. §30 ranks typing quality above everything.
*Failure:* the moment the learning bar has something to say — i.e. exactly when the user is mid-sentence and most likely to have typos — autocorrect candidates vanish. The two features contend for the same 44pt strip and the PRD never arbitrates.
*Fix:* pick one. Recommended: the learning bar is a **second strip that only appears on a completed sentence**, is 32pt, and never displaces the suggestion row. Specify total keyboard height in points for portrait/landscape and state that the bar's appearance must not change keyboard height (reserve the space or use an overlay).

**F7. Autocorrect/suggestions are ranked #1 in §30 but appear nowhere in the §12 P0 list. — MAJOR**
§12 P0 has no entry for autocomplete, suggestions, or a word dictionary. §12 P2 has "Advanced autocorrect". §24 says the keyboard is not "usable until normal typing feels acceptable."
*Failure:* Phase 0 ships and the developer discovers the keyboard is unusable for daily messaging (no suggestions, no autocorrect), abandoning the whole project at the "acceptance" gate that §26 declares passed.
*Fix:* move "basic English + Italian word suggestion and autocorrect, with a named dictionary source" into P0, with an explicit dependency note (KeyboardKit's autocomplete is a **Pro/paid** feature — see F13).

**F8. "Italian typing support" is P0 (§12 line 467) with no Italian layout, dictionary, or accent strategy anywhere in the document. — BLOCKER**
The only layout shown (§10 lines 346-355) is a bare English QWERTY with no accent affordances, no apostrophe, and no ñ. Italian needs à è é ì ò ù (typed as long-press callouts or dedicated keys), heavy apostrophe usage (l'ho, un'ora, dell'anno), and a different symbol layout. Spanish needs ñ á é í ó ú ü ¿ ¡.
*Failure:* one keyboard extension = one entry in iOS Settings with one `PrimaryLanguage`. The PRD never says whether Italian is a separate keyboard (user must add two keyboards and globe-switch), a mode toggle inside one keyboard, or "the same layout, different dictionary."
*Fix:* decide explicitly. Recommended: **one keyboard, one layout, long-press secondary callouts carrying the union of EN/IT/ES accents, dictionary switched by the source-language toggle.** Add a full callout map to the PRD as a table. Note that secondary callouts are a nontrivial build (see F41).

**F9. §11 Mode C (code-switch) is unimplementable against §15's schema and forbidden by §16 rule 9/rule 3. — MAJOR**
§16 rule 3: "Target language is always standard Spanish." Rule 9: "Do not expand the user's sentence." Rule 10: "Return JSON matching the API schema exactly." §15's schema has exactly one `translation` string and one `focus`. There is no field that can carry "Probablemente I'll llegar around ocho."
*Failure:* the engineer either violates the schema or Mode C silently never ships — but it's listed in §12 P1 and §26 Phase 3 as a deliverable.
*Fix:* add `codeSwitched: string?` and `blanked: {text, answerLemma, hint}?` to the response, and amend §16 rule 3 to "the `translation` field is always standard Spanish; other fields may be mixed."

**F10. Mode E's trigger cannot exist under §9's rules. — BLOCKER**
§9 line 316: "Detect whether the current sentence is primarily English or Italian." Source modes are Auto/EN/IT (§9 line 306, §12 line 471). Spanish is not a detectable state. Mode E (§11 line 436) fires "when the user writes directly in Spanish."
*Failure worse than a no-op:* Spanish and Italian are the highest-confusion pair for `NLLanguageRecognizer` on short strings. "creo que voy estar tarde" will frequently classify as Italian, and the system will "translate Italian -> Spanish" the user's already-Spanish sentence, garbling it and *teaching them that their correct Spanish was wrong*. This is the exact opposite of the product's purpose.
*Fix:* Auto must be a three-way classifier {EN, IT, ES} with a confidence floor and an explicit `ES` branch that routes to correction mode. Add a fourth toggle position: Auto / EN / IT / **ES**. Add an acceptance test: correct Spanish input must never be rewritten by the translate path.

**F11. "Personal use first" (front matter, §3) vs a mandated authenticated production proxy (§7). — MAJOR**
§3 forbids "cloud accounts or multi-user infrastructure" and "monetization or App Store launch requirements." §7 requires an *authenticated* proxy with *rate limiting* and states "no conventional backend database is required." Authentication and rate limiting are stateful; with no account system, the only auth is a static token shipped in the app — which is the identical threat model §7 exists to avoid.
*Failure:* the shared token is extracted from the IPA; the proxy is drained; the developer eats an unbounded provider bill.
*Fix:* for a single-user V1, use **BYOK in Keychain with a hard client-side spend counter**, and explicitly defer the proxy to "when a second user exists." Add a per-day request cap and a hard monthly token budget to §12 P0. Delete "authenticated proxy" from V1 scope.

**F12. §3 non-goal "no scraping conversations" vs §18's use of `documentContextBeforeInput`. — MINOR**
In Notes, Mail and Safari textareas, `documentContextBeforeInput` returns a large slab of preceding document text, which the user did not think of as "the current message."
*Fix:* state a hard numeric cap (e.g. 240 characters, truncated at a sentence boundary) in §18 rather than "hard-cap remote context length," and state that the extractor never crosses more than one preceding sentence boundary.

**F13. §5 recommends KeyboardKit *for* autocomplete/autocorrect (line 128), then notes licensing risk (line 133), then §12 lists nothing from that set as P0. — MAJOR**
KeyboardKit's autocomplete, secondary callouts for non-English locales, and emoji keyboard are Pro (commercial, annual) features. OpenKeyboardKit is a fork of a pre-iOS-17 open-source version — "less actively maintained" (line 145) understates an abandoned tree that will not match iOS 18 SwiftUI keyboard patterns.
*Failure:* Phase 0 is architected on Pro APIs; the licensing review at line 133 comes back unacceptable; the abstraction layer (line 152) leaks because callouts and autocomplete are exactly the parts that don't abstract.
*Fix:* resolve the licensing question **before Phase 0**, as a written decision in the PRD, and list the specific KeyboardKit features used with their license tier. If Pro is off the table, budget +3-4 weeks for hand-built callouts and autocomplete.

**F14. §13's mastery bands and §14's policy thresholds disagree at every boundary and use different vocabulary. — MINOR**
§13: "0.00-0.20 New, 0.20-0.50 Learning" — 0.20 belongs to both. §14 branches on `< 0.20`, `< 0.50`, `< 0.80`, `< 0.95`, else. §14's terminal `else` (show nothing) starts at 0.95, matching "Mastered", but "Strong" (0.80-0.95) maps to "occasionally ask recall" with "occasionally" undefined.
*Fix:* half-open intervals `[0, 0.2)` etc., and replace "occasionally" with a probability and a cooldown.

**F15. Four overlapping, unmapped controls for the same dial. (§11 Modes A-E, §12 "Learning-level control", §15 `desiredDifficulty: 0.35`, §20 "mode: Passive/Adaptive/Recall" + "learning intensity") — MAJOR**
§20's mode enum has three values; §11 defines five modes; neither maps to `desiredDifficulty`, and "learning intensity" is never defined in any unit.
*Failure:* the settings screen ships with two sliders and a segmented control that interact in undefined ways; the API receives a number the client computed by guessing.
*Fix:* collapse to **one** user-facing control ("Assistance: Light / Balanced / Push me"), define its numeric mapping to `desiredDifficulty` in a table, and make Modes A-E internal states selected by the §14 policy, never by the user.

**F16. §16 rule 6 ("at most one new concept") vs §11 Mode B ("emphasize unfamiliar or currently-learning vocabulary", plural) vs §15's singular `focus`. — MINOR**
*Fix:* make `focus` an array with a server-enforced `maxItems: 1` for V1; document that Mode B highlights exactly one span.

**F17. Explanations are English-only in the schema while Italian->Spanish is P0. (§15 `explanation`, §12 line 474) — MAJOR**
The response carries `meaning` and `meaningItalian` but a single `explanation` string, and §16 never says which language to explain in.
*Failure:* an Italian-mode user gets Spanish grammar explained in English — a third language in the loop, defeating §1's "reduce dependence."
*Fix:* add `explanationLanguage` to the request; require the model to explain in the detected source language.

**F18. §21 line 784: "Never process secure/password fields because iOS excludes the custom keyboard there anyway." Overstated to the point of being wrong. — MAJOR**
iOS substitutes the system keyboard for `isSecureTextEntry` fields only. 2FA codes, recovery phrases, credit-card numbers, API keys, and most `WKWebView` login forms are frequently **not** flagged secure. §18's mitigation is "strip obvious passwords/tokens where detectable" — undefined and unreliable.
*Failure:* the user pastes a seed phrase or types a one-time code into a non-secure field; the debounce fires; it goes to a third-party LLM provider.
*Fix:* add a hard suppression list to §18: never fire when `keyboardType in {.numberPad, .decimalPad, .phonePad, .emailAddress, .URL, .asciiCapableNumberPad}`, when `textContentType` is any of the `oneTimeCode`/`password`/`creditCard*`/`newPassword` values, or when the segment matches high-entropy/`\d{4,}` patterns. Make this P0 and an acceptance test.

**F19. §2 "Make the user progressively type more Spanish" vs §10's headline action "Insert ES". — BLOCKER (see §6, kill shot)**
The primary interaction hands the user a finished machine translation and inserts it. That is production *by the model*, not by the learner. Every tap of Insert ES is a skipped retrieval opportunity — the single most learning-productive event the system could create.
*Fix:* make the default terminal action **not** insert. Default should be Mode D (blank + hint) or a "type it yourself, I'll check" affordance; Insert ES becomes the escape hatch, visually secondary, and is logged as a *failed* recall for the focus lemma.

---

## 2. Undefined Behavior / Underspecified Requirements

**F20. "Sentence" is never defined. (§1 step 3, §7, §17, §18, §14 "per-sentence budget") — BLOCKER**
No segmenter is named. No handling for: chat messages with zero punctuation (the majority), abbreviations ("Dr.", "8 p.m.", "ecc."), decimals, URLs, "...", emoji mid-sentence, Italian apostrophes, English contractions, or a message that is one 40-word run-on.
*Failure:* "arrivo alle 8. 30 circa" splits into two garbage segments; the URL "claude.ai/code" triggers three fires.
*Fix:* normative: `NLTokenizer(unit: .sentence)` over `documentContextBeforeInput`, take the **last** unit, plus explicit override rules for URLs/handles/emails (never split inside), plus a fallback: if no terminal punctuation exists and the buffer is >= 4 tokens, treat the whole buffer as one segment.

**F21. Mid-message editing is completely unspecified. (§18, §10 tap behavior) — BLOCKER**
User taps into the middle of "I'll probably arrive around eight tonight" after "arrive". Now `documentContextBeforeInput` ends mid-sentence and `documentContextAfterInput` holds the tail.
*Failure:* the trigger fires on "I'll probably arrive", translates a fragment, and Insert ES deletes backwards — destroying the prefix while leaving " around eight tonight" dangling after the inserted Spanish.
*Fix:* rule — **suppress all auto-triggers when `documentContextAfterInput` is non-empty and does not begin with whitespace-then-EOF.** Explicit translate remains available and operates on the full reconstructed sentence, but Insert is disabled unless the cursor is at end-of-field.

**F22. Multi-sentence input: which sentence wins? (§14 per-sentence budget, §17) — MAJOR**
User types three sentences then pauses.
*Fix:* always the sentence containing the cursor; if that sentence is empty, the immediately preceding one; never more than one per request.

**F23. "Insert ES" semantics are entirely undefined. (§10 line 385, §12 line 476) — BLOCKER**
Not specified: does it replace the source sentence or append? What is deleted, exactly (the sentence? the whole field?)? How many `deleteBackward()` calls (there is no bulk-delete API; 40 chars = 40 proxy calls, each of which the host may animate)? Where does the cursor land? Is the leading capital preserved? Is a trailing space added? What happens to the tail after the cursor? What if `deleteBackward` walks past the field's start? What about grapheme clusters — one `deleteBackward` on a family emoji removes the whole cluster, but on "é" composed as e+combining-acute it may remove only the combining mark.
*Fix:* write the algorithm explicitly, including: compute `deleteCount` from the *matched* source segment only; loop `deleteBackward()` `deleteCount` times inside a single run-loop turn; `insertText(spanish)`; do not add trailing space; re-assert shift state; store an `UndoRecord{deletedText, insertedText, timestamp}` and expose an Undo affordance in the bar for 5 s.

**F24. Undo is mentioned nowhere in 1,147 lines. — BLOCKER**
Insert ES is destructive to user-authored text. Shake-to-undo does not reliably cover proxy-driven edits; the host app's undo stack often has no record of them.
*Fix:* per F23, a first-class Undo button that replays the inverse (`deleteBackward` x len(inserted), `insertText(deletedText)`), plus an acceptance test.

**F25. Host-app text substitution fighting the insertion. (§4, §10) — MAJOR**
The host field's `autocapitalizationType`, `smartQuotesType`, `smartDashesType`, and `smartInsertDeleteType` act on inserted text. Inserting "llegaré sobre las ocho" after a period yields "Llegaré..."; smart quotes mangle apostrophes in "l'ho" / "qué'".
*Fix:* specify that the keyboard reads `textDocumentProxy` traits on `textDidChange` and pre-normalizes inserted text to match (pre-capitalize, pre-curl quotes) rather than letting the host do it.

**F26. Source-language toggle x Auto is undefined. (§9, §12 line 471) — MAJOR**
Does manual selection persist forever, for the session, for the app, or until the next sentence? Does switching mid-sentence re-fire the request or invalidate the current suggestion? Where does the toggle physically live — §10's normal-state mock (line 348) shows no language chip at all, contradicting §9 rule 4 ("show the detected source language in the learning bar").
*Fix:* define: manual override is sticky until the user returns it to Auto; it persists across app switches; it re-fires the current segment immediately; the chip lives at the leading edge of the bar and is itself the tap target for the toggle.

**F27. Auto-detection has no numeric thresholds. (§9 rules 1-3) — MAJOR**
"Reasonable minimum amount of text", "avoid oscillating" — no character count, no confidence floor, no hysteresis window.
*Failure:* "ok" / "no" / "come" / "sono" / "male" flip the state every word; the language chip strobes.
*Fix:* `NLLanguageRecognizer` with `languageConstraints = [en, it, es]`; require >= 12 characters AND top-hypothesis probability >= 0.65 AND a 2-consecutive-agreement rule before changing state; never change state within a sentence once set.

**F28. "Learning intensity" (§20) has no unit, range, default, or effect. — MAJOR** *Fix:* per F15.

**F29. `desiredDifficulty: 0.35` (§15) has no defined semantics on either side of the wire. — MAJOR**
Neither the client's computation nor the model's interpretation is specified. §16 gives the model no rule referencing it.
*Fix:* define it as "target probability that the focus item is unknown to the learner," add a §16 rule that binds it, or delete the field.

**F30. `confidence: 0.98` (§15) — no threshold, no client behavior. — MINOR** *Fix:* "suppress the suggestion below 0.75; never insert below 0.85."

**F31. `alternatives: []` is untyped and unused. — MINOR** *Fix:* type it or cut it.

**F32. No error schema, no auth spec, no versioning on `/v1/assist`. (§15) — MAJOR**
No error body, no HTTP status mapping, no retry-after, no request id, no prompt-version field (essential for cache invalidation when §16 changes), no model name, no max-token budget, no JSON-mode/structured-output enforcement mechanism, no behavior when the model returns non-JSON or refuses.
*Fix:* add all of the above. Specifically add `promptVersion` to the cache key.

**F33. `knownVocabulary` / `learningVocabulary` are unbounded. (§15) — MAJOR**
After six months these are thousands of lemmas. Every request carries the array.
*Failure:* multi-kilobyte requests, token cost dominated by the vocab list, latency blown past §22's 1.5 s target.
*Fix:* send at most the lemmas present in *this sentence's* likely translation — which the client can't know — so instead: send nothing, have the server return `focusCandidates` (3-5 lemmas), and let the **client** pick the focus against local state. This also fixes F5 and F4's payload assembly.

**F34. Lemmatization is required everywhere and specified nowhere. (§13 `lemma`, §14, §26 Phase 2 "word extraction") — MAJOR**
Mapping "llegaré"/"llegué"/"llegando" -> "llegar" is a hard Spanish morphology problem. `NLTagger`'s `.lemma` for Spanish is mediocre on conjugated verbs and clitics ("dímelo").
*Failure:* mastery is tracked per surface form; "llegar" never accumulates exposures; §31 item 9 never demonstrably happens.
*Fix:* have the API return the lemma (it already does, in `focus.lemma`) and make server-supplied lemmas the only source of truth. Never lemmatize on-device in V1.

**F35. Mastery update rules do not exist. (§13 "mastery: 0.72", §29 "deterministic mastery + spaced repetition") — BLOCKER for Phase 2**
No formula, no increment per exposure, no decay function, no algorithm named (SM-2? FSRS?), no rule for how `next_review_at` is computed.
*Fix:* pick FSRS or SM-2 by name; write the mastery function explicitly; and critically — **weight exposure far below recall** (see F45).

**F36. "Tap to dismiss" / "swipe to collapse" has no scope. (§10 line 390, §12 line 477) — MAJOR**
Dismissed until when? Next sentence? Next app? Next keyboard appearance? Forever? And a vertical swipe in the strip above the keys collides with the reach-down gesture and with the top row's key targets.
*Fix:* define: dismiss hides the current suggestion only; a *long* swipe-down disables the bar until the keyboard is next dismissed and re-presented; persist neither.

**F37. Mode D has no input mechanism. (§11 lines 427-434) — MAJOR**
The blank is rendered *in the learning bar*, but the user types into the *host text field*. There is no specified way to answer, no way to be marked right or wrong, and therefore no way `successful_recalls` (§13) ever increments during real typing.
*Failure:* the entire adaptive-recall pillar (§26 Phase 3) has no data source.
*Fix:* the recall answer is what the user *types next in the field*; match it (accent-insensitively, then strictly) against the answer lemma's inflected forms within N seconds; that is the recall event. Write this down.

**F38. Mode E's correction UI is unspecified. (§11 lines 436-457) — MAJOR**
`[Fix]` must perform a *diff-based* edit inside already-typed text — i.e. a mid-field edit, which F21 says is undefined. What if the error is 20 characters back? What if there are two errors?
*Fix:* restrict V1 corrections to the current sentence with cursor at end; `[Fix]` replaces the whole sentence via the F23 algorithm; one correction at a time.

**F39. `hasFullAccess` is treated as a stable boolean. (§4 line 93, §12, §23) — MAJOR**
It can be `false` for the first moments after extension launch (a long-standing iOS behavior) and can change while the keyboard is alive.
*Failure:* the keyboard decides it has no network on launch, shows the degraded bar for the whole session.
*Fix:* re-check on `viewWillAppear` and on first network need; never cache the value across appearances.

**F40. First-launch ordering is unhandled. (§20, §19, §23) — MAJOR**
A user can enable the keyboard in Settings before ever opening the host app. The App Group contains no settings, no onboarding state, no vocabulary DB.
*Fix:* the extension must ship with compiled-in defaults and must never assume the App Group is populated. Add "keyboard used before host app onboarding" as an acceptance test.

**F41. The keyboard mechanics that make it *feel* native are listed as one bullet each. (§12 line 469, §24) — MAJOR**
"Shift, caps lock, delete, space, return, numbers/symbols" hides: shift double-tap timing, shift-after-punctuation auto-capitalize, delete long-press acceleration curve (and word-wise deletion after ~2 s), space long-press cursor scrubbing, double-space -> period+space (and its interaction with `smartInsertDeleteType`), primary key callouts, **secondary long-press callouts with drag selection** (the only accent mechanism, per F8), key repeat, and touch-slop/next-key correction geometry.
*Fix:* expand §12 P0 into an itemized table with one line per behavior, each independently testable. This is where Phase 0's real cost lives.

---

## 3. The Interaction Model — Keystroke-Level Walkthrough

**Scenario: user is in a WhatsApp group chat, typing to their (English-speaking) friends, walking to the bus.**

```
t=0.0s   taps field, keyboard appears (extension cold-launch: 150-400ms with SwiftUI)
t=1.2s   types "hey"            -> nothing
t=2.0s   types " sorry"         -> 700ms pause while dodging a person
t=2.7s   DEBOUNCE FIRES. segment = "hey sorry". request out.
t=3.1s   types " im gonna"
t=3.3s   response for "hey sorry" arrives -> "oye, lo siento" appears in bar
         but the text is now "hey sorry im gonna" -> §17 says invalidate.
         Bar flashes and clears. Visual noise, zero value.
t=4.4s   types " be late"       -> pause
t=5.1s   DEBOUNCE FIRES. segment = "hey sorry im gonna be late"
t=5.4s   user hits Return -> MESSAGE SENDS. Field empties.
t=6.2s   response arrives: "Oye, perdona, voy a llegar tarde."
         Field is empty. Bar shows a translation of a message already sent.
         Insert ES would type Spanish into the next message.
```

**F42. The suggestion is structurally too late. (§22 vs §17 vs real composition) — BLOCKER**
Debounce (0.5-0.9 s) + network (target < 1.5 s, realistic p50 1.2-2.5 s for a JSON-constrained tutor response) = **1.7-3.4 s after the user stops typing**. Median chat message is composed and sent in 4-8 s. The suggestion arrives during the last beat or after send, in the majority of real cases. §22's own fallback ("> 3 s: suppress the suggestion") means the system is specified to give up in the common case.
*Fix:* accept that the auto-trigger only works for slow, deliberate composition (Mail, Notes, long WhatsApp messages). Make the **explicit tap** the primary path in V1 and the auto-trigger an opt-in setting, default off. This inverts §12's P0 emphasis and drastically cuts Phase 1 cost.

**F43. Insert ES is incoherent in a mixed-language conversation — the recipient is never mentioned in the PRD. — BLOCKER**
The user has typed English *because they are writing to an English speaker*. Inserting Spanish makes the message unreadable to the recipient. In a group chat it's worse: it looks like a misfire. The PRD's §10, §11 and §31 item 6 all assume inserting Spanish into the live field is desirable, and never once asks who receives it.
*Consequence:* the only contexts where Insert ES is legitimate are (a) messaging an actual Spanish speaker — in which case the user should be typing in Spanish and using Mode E, not Mode A — and (b) Notes/drafts, where there is no recipient. That is a small fraction of typing.
*Fix:* split the product in two. **"Study" surface**: read-only bar, never inserts, works everywhere (this is the real product). **"Compose in Spanish" surface**: Mode E + Spanish autocorrect, used when the recipient is Spanish-speaking. Cut the mixed case entirely.

**F44. The bar competes for the exact screen region users look at least. — MAJOR**
While typing, gaze is on the text field and the keys — not the 44pt strip between them. §25 correctly demands the learning UI be subtle; §14 demands it be adaptive. Combined, the most likely outcome is that the user never notices it, which is indistinguishable from the feature not existing.
*Fix:* V1 must include one deliberate, measurable attention hook (a single brief highlight animation on first appearance per session) and instrumentation for "bar shown vs bar interacted with". Without that number the product cannot be evaluated.

**F45. Passive exposure is counted as learning. (§13 `exposures`, §14 policy, §31 item 9) — MAJOR**
A word appears in the bar -> `exposures++` -> mastery rises -> §14 shows less -> the assistance fades for a word the user never read, never produced, and cannot recall.
*Failure:* the flagship differentiator ("assistance becomes progressively less explicit") degenerates into "the app stops helping with words you never learned."
*Fix:* exposures may raise mastery only up to a hard ceiling (e.g. 0.35). Crossing into "Familiar" requires >= 2 successful *recall* or *production* events (F37).

**F46. Emoji breaks everything and is unaddressed. — MAJOR**
Emoji mid-sentence corrupt segmentation (F20), are sent to the API, and `deleteBackward` over them is grapheme-cluster-sized. And separately — see F47 — the user cannot even *reach* the emoji keyboard without leaving LinguaKey.
*Fix:* strip emoji from the outbound segment (preserving positions for the delete count); specify grapheme-aware deletion using `String.Index` counts, not UTF-16 offsets.

---

## 4. Missing Requirements — Things a Shipping Keyboard Needs, Absent from 1,147 Lines

**F47. No emoji keyboard, and no acknowledgment that this is fatal to daily use. — BLOCKER**
A custom keyboard cannot present the system emoji keyboard. Users must globe-switch away from LinguaKey for every emoji — which, in chat, is many times per message, and each switch may not return. The PRD's success condition (§2 line 53, "leave LinguaKey enabled as the default keyboard for normal daily messaging") is unreachable without a built-in emoji picker with recents, search, and skin-tone variants. That is 1-2 weeks of work on its own (or a KeyboardKit Pro feature, per F13).
*Fix:* add "emoji keyboard with recents and search" to P0, or explicitly accept that the keyboard is not a daily driver and re-scope the success condition.

**F48. No dictation. — MAJOR**
The system mic key is unavailable to custom keyboards. Heavy dictation users will not adopt.
*Fix:* acknowledge as a known limitation in onboarding; there is no fix.

**F49. `keyboardType` is never handled. — MAJOR**
`.numberPad`, `.decimalPad`, `.phonePad`, `.emailAddress`, `.URL`, `.twitter`, `.webSearch` each require a distinct layout. Ignoring them means the user sees full QWERTY when entering a phone number or PIN.
*Fix:* P0 — number pad and decimal pad layouts, plus `.emailAddress`/`.URL` variants (@ and . on the primary row). Also required for F18.

**F50. `returnKeyType` is never handled. — MAJOR**
The return key must render as Send / Go / Search / Done / Next / Join, honor `enablesReturnKeyAutomatically` (disabled state when the field is empty), and use the correct blue tint.
*Fix:* P0.

**F51. Accessibility is entirely absent. — BLOCKER**
A keyboard is the single most accessibility-critical UI on the device. Required: per-key `accessibilityLabel` and `accessibilityTraits`, VoiceOver **touch-typing** mode (touch to hear the key, lift to type — this is the *expected* interaction, not standard direct-touch), Switch Control, Full Keyboard Access, Reduce Motion, Increase Contrast, Bold Text, and Dynamic Type on the learning bar. There is not one word about any of it. It is also an App Store review risk and, for many jurisdictions, a legal one.
*Fix:* add an "Accessibility" section with the above as P0, and add VoiceOver typing to §27.

**F52. No keyboard height / `UIInputView` sizing spec. — MAJOR**
The extension must set its own height via a constraint on `view` (the well-known SwiftUI-in-keyboard height problem), for portrait, landscape, and each device class. The learning bar changes the total, which shifts the host's content and can cover the text field in short-form apps.
*Fix:* specify exact heights in points, and require the bar to occupy reserved space (fixed height, empty when idle) so total height never changes.

**F53. Landscape is unspecified. — MAJOR**
Landscape keyboards are ~half the height; a 44pt learning bar consumes a third of it.
*Fix:* specify that the bar collapses to a single-line 24pt chip in landscape, or hides entirely.

**F54. iPad is a non-goal (§12 P2) but the extension will still load there. — MAJOR**
An iPhone-family keyboard extension runs on iPad (including in iPhone-compatibility rendering) and, if the app is universal, renders at iPad width — a 1024pt-wide iPhone layout with 30pt keys.
*Fix:* either set the app's device family to iPhone-only, or ship a minimum iPad fallback layout. State the decision.

**F55. Dynamic Type is unaddressed. — MAJOR**
Key labels and, more importantly, the learning bar's Spanish sentence at AX5 will truncate to two words.
*Fix:* specify the bar's truncation/scroll behavior and a minimum legible size.

**F56. Key click sound and haptics are hand-waved ("where allowed", §24). — MINOR but user-visible**
Click requires conforming to `UIInputViewAudioFeedback` and calling `playInputClick()`; haptic feedback in a keyboard extension requires **Full Access**. So a user who declines Full Access (the privacy-conscious user this PRD courts) also loses haptics.
*Fix:* state this explicitly in onboarding and in §23's "No Full Access" section.

**F57. Text selection is unhandled. — MAJOR**
When the user selects text, `deleteBackward` replaces the selection; the bar's state is stale; `selectedText` is often `nil` even when a selection exists.
*Fix:* on `selectionDidChange`, cancel in-flight requests and clear the bar; disable Insert while a selection exists.

**F58. Clipboard / paste is unmentioned. — MINOR**
Any read of `UIPasteboard` from the keyboard triggers the iOS "LinguaKey pasted from..." banner and looks like spyware.
*Fix:* explicitly forbid pasteboard access in V1.

**F59. Lock-screen and data protection. (§19) — MAJOR, crash-class**
The keyboard can be invoked from a notification reply on the lock screen. Files in the App Group container default to `NSFileProtectionCompleteUntilFirstUserAuthentication` in some paths and `Complete` in others; Keychain items default to `WhenUnlocked`. Opening the vocabulary DB or reading the BYOK key before first unlock fails.
*Fix:* specify protection classes explicitly for the DB, the cache, and the Keychain item; require the keyboard to function (typing only) when the store is unavailable.

**F60. Memory budget has no number. (§22 "stricter runtime constraints") — MAJOR**
Keyboard extensions are jetsammed in roughly the 40-60 MB range. SwiftUI + KeyboardKit + a translation cache + a vocabulary store is close to that ceiling before any feature work.
*Fix:* state a hard budget (e.g. 35 MB steady state, 45 MB peak), require an instrument run at the end of each phase, and cap the translation cache in bytes (not entries).

**F61. Extension lifecycle mid-request. (§23 "Extension restart") — MAJOR**
App switch, keyboard dismissal, and memory kill all destroy in-flight `URLSession` tasks. Nothing specifies whether a response is persisted, discarded, or resumed.
*Fix:* discard on `viewWillDisappear`; never write a response to shared storage from a torn-down request. Add to §27.

**F62. No data migration or schema versioning. (§13, §19) — MAJOR**
The vocabulary record has no `schemaVersion`. Phase 3 will change it (F35 will add SR fields).
*Fix:* add `schemaVersion` to the record and a migration policy now. A keyboard extension that crash-loops on an unmigrated store is unrecoverable without deleting the app.

**F63. No error telemetry spec, and telemetry is itself a privacy problem. (§6 "telemetry interface", §26 Phase 4) — MAJOR**
The architecture diagram lists a telemetry interface that no section defines. Crash reporting from a keyboard extension requires network -> Full Access -> and can leak typed text via breadcrumbs.
*Fix:* define a local-only, ring-buffered diagnostic log visible in the host app's developer screen. No remote telemetry in V1. Explicitly forbid logging typed text.

**F64. No way for the user to report a bad translation. — MAJOR**
This is a tutoring product; wrong Spanish actively teaches errors. §27's translation test ("natural Spanish output") has no rubric and no feedback channel.
*Fix:* add a long-press "this is wrong" action that stores `{source, translation, promptVersion, timestamp}` locally for review in the host app. P0 — it is the only quality signal the project will have.

**F65. No Spanish variety is chosen. (§16 rule 3 "standard Spanish") — MAJOR**
"Standard Spanish" is not a thing. §10's own example ("sobre las ocho") is peninsular. *coger*, *ordenador/computadora*, *vosotros/ustedes*, *tú/vos* differ in ways that range from confusing to socially catastrophic.
*Fix:* pick one variety (peninsular, given an EN/IT European user) and put it in §16 rule 3 verbatim. Add a settings toggle in P2.

**F66. No cost model, no spend cap, no request quota. (§7, §15) — MAJOR**
Nowhere is a per-day request estimate, a token budget, a model choice, or a hard spend ceiling.
*Rough figure:* with F3's realistic 4-8 fires/sentence x ~40 sentences/day = 160-320 requests/day ~= 5-10 k/month for **one user**. Fine as a bill; not fine as an unbounded, un-instrumented one behind a static token (F11).
*Fix:* name the model, state expected tokens per request, and add a client-side daily cap that fails closed.

**F67. No EN/IT word list or autocorrect dictionary source is named. (§24, §8 "cached autocomplete") — MAJOR**
Frequency lists with acceptable licenses are a real acquisition and bundling task (size, load time, memory — see F60).
*Fix:* name the source and its license; budget its memory footprint.

**F68. Provisioning is never mentioned, and it blocks §31 item 1. — BLOCKER**
A keyboard extension needs a second App ID, an App Group entitlement, and a Keychain access group. **App Groups are not available on free personal provisioning profiles**, and free profiles expire after 7 days. §3 declares App Store distribution a non-goal and §31 item 1 says "install the app on an iPhone."
*Failure:* the developer builds Phase 0, then discovers the App Group in §12 P0 requires the $99/yr Apple Developer Program, and that without it the keyboard stops working every 7 days.
*Fix:* state the paid-account requirement in §4 as a hard prerequisite, and add TestFlight (90-day builds, requires the paid account) as the distribution mechanism for personal use.

**F69. Low Power Mode, background refresh, locale/region settings, and system keyboard-switching mid-request are all unmentioned. — MINOR**
*Fix:* one paragraph in §23: suppress auto-triggers in Low Power Mode; treat globe-switch as `viewWillDisappear`.

---

## 5. Scope and Sequencing

**F70. §26 contains no time estimates, no dependencies, and no measurable exit criteria. — MAJOR**
"without crashes", "reliably see a natural Spanish equivalent", "less intrusive assistance over time" are not acceptance criteria; none can be evaluated by a test.
*Fix:* attach durations, and rewrite each acceptance as a countable assertion.

**Honest solo-developer estimate (evenings/weekends, ~10-12 h/week, competent iOS dev, first keyboard extension):**

| Phase | PRD content | Real hours | Elapsed |
|---|---|---|---|
| 0 — Shell | Layout, shift/caps timing, delete acceleration, callouts + **secondary accent callouts**, autocap, double-space period, space-scrub, height constraints, dark mode, `keyboardType`/`returnKeyType` (F49/F50), App Group, provisioning (F68) | **70-110 h** | 7-10 wks |
| 0.5 — *missing* | Emoji keyboard (F47), autocorrect + dictionary (F7/F67), accessibility (F51) | **60-90 h** | 6-8 wks |
| 1 — Translation MVP | Proxy or BYOK, segmentation (F20), detection (F27), debounce/cancel, insert algorithm + undo (F23/F24), cache, error states | **45-70 h** | 4-6 wks |
| 2 — Learning engine | DB in App Group w/ protection classes (F59), lemma handling (F34), mastery (F35), highlight rendering, TTS, 3 host-app screens | **60-100 h** | 6-9 wks |
| 3 — Adaptive recall | Recall input mechanism (F37), code-switch generation (F9), SR algorithm, correction mode incl. mid-field editing (F38) | **70-120 h** | 7-12 wks |
| 4 — Polish | open-ended | **60 h+** | 6 wks+ |

**Total to §31's V1: ~360-550 hours, 8-14 months elapsed part-time.** The PRD reads as if this is a 6-8 week project. It is not. Phase 0.5 — the block the PRD omits entirely — is comparable in size to Phase 1.

**F71. P0 items that are actually P1 or later. — MAJOR**

| §12 P0 item | Why it isn't P0 |
|---|---|
| Italian typing support | Doubles layout, dictionary, detection and eval surface. Ship EN->ES. Italian is a v1.1. |
| Italian -> Spanish translation | Same. Also the highest-confusion detection pair with ES (F10). |
| Auto language detection | A manual toggle is 1 hour of work and is *more* reliable. Auto is a P1 nicety that adds a whole failure class. |
| Translation cache | Broken as specified (F5), and worth ~nothing at one user's request volume. |
| Basic vocabulary tracking | Contributes nothing to the first usable artifact; belongs with Phase 2. |
| API request debounce | Should be **off by default** (F42). Explicit tap is the reliable path. |
| Shared App Group settings | Real, but it drags in the paid-account prerequisite (F68) — call that out. |

**F72. P1/P2 items that are secretly P0 — the product is unusable without them. — BLOCKER**

- **Emoji keyboard** (not listed anywhere) — without it, nobody keeps this as their default keyboard, which voids §2's success condition.
- **Basic autocorrect + suggestions** (§24 "V1", §12 P2) — §30 ranks it #1; it must be P0.
- **Accessibility / VoiceOver** (absent) — non-negotiable for a keyboard.
- **Undo for Insert ES** (absent) — the primary action is destructive.
- **`keyboardType` / `returnKeyType` handling** (absent) — the keyboard looks broken in half of iOS without them.
- **Bad-translation reporting** (absent) — the only quality signal that will exist.
- **Secure/numeric field suppression** (F18) — the difference between a learning tool and a keylogger.

**F73. §31's V1 definition is not achievable as one release, and item 9 is not demonstrable. — MAJOR**
Item 9 ("see assistance become progressively less explicit") requires the mastery model, recall events, and *months* of the user's own typing to produce enough exposures for any lemma to cross a threshold. It cannot be validated at ship time. §27 has no test for it.
*Fix:* split V1 into V1 (items 1-7, 10) and V2 (items 8, 9). Add a debug affordance that lets the developer force mastery values so the fade behavior is testable in minutes.

**F74. The true minimum first milestone is smaller than Phase 1 and different in shape.**
**V0 — "the tap keyboard" (~90-130 h, 8-12 weeks part-time):**
1. Phase 0 shell, English only, no auto-detection.
2. Emoji keyboard, basic English suggestions, accessibility labels, `keyboardType`/`returnKeyType`.
3. **One button in the bar: "ES ->".** No debounce, no auto-trigger, no cache, no vocabulary, no App Group beyond a BYOK Keychain item.
4. Tap -> sends the last sentence -> shows Spanish, read-only, with a speaker and a copy action. **No Insert.**
5. Bad-translation long-press logging.

That is a thing the developer can actually use every day, and it tests the real hypothesis (F75) with none of the adaptive machinery.

---

## 6. The Kill-Shot

**The single most likely reason this fails:** the terminal action of the core loop — insert a machine-generated Spanish sentence into a live message — is something the user will almost never want to do, because almost none of their messages go to Spanish speakers, and the ones that do are exactly the messages they'd want to compose in Spanish themselves. Strip the insert away and what remains is a translation *readout* pinned above the keys — a passive, glanceable, easily-ignored strip that appears 2-3 seconds late (F42), in the part of the screen nobody looks at (F44), showing a correct answer the user never had to retrieve (F19). That is recognition exposure, not production practice, and recognition exposure from an app you're not attending to is close to worthless pedagogically — which means the mastery counter (F45) will climb, assistance will fade, and the user will have learned nothing while the system congratulates itself. The keyboard, meanwhile, costs 300+ hours to make merely tolerable and permanently loses dictation and (without another 60-90 h) emoji.

**The cheaper experiment, in this order:**
1. **Two days, zero code.** For 14 days, the user copies every message they were going to send into a chat thread carrying the §16 prompt, and logs three numbers daily: how many times they *wanted* to send the Spanish version; how many times they could produce the Spanish before seeing it; how many times they read the answer and moved on. If the first number is near zero across two weeks, F43 is confirmed and the keyboard should not be built.
2. **One weekend, ~8 hours.** Deploy the §15 endpoint and a 150-line SwiftUI app with a text field, a Translate button, and a speaker — plus an iOS **Share Sheet extension** and a Shortcut so it can be invoked from any app on selected text. Live with it for a month. It exercises the entire learning engine, the prompt, the API contract, and the pedagogy, with **none** of the keyboard-extension cost, no Full Access, no App Group, no memory ceiling, no emoji problem, and no accessibility surface.
3. Only if step 2 is still in daily use after 30 days does the keyboard become the right delivery vehicle — and by then §15, §16, §13 and §14 will have been rewritten by contact with reality, which is worth more than Phase 0.

---

## 7. What's Actually Good — Keep These

1. **§4 is largely accurate and unusually well-researched.** `UITextDocumentProxy` limits, `RequestsOpenAccess`/`hasFullAccess`, secure-field exclusion, extension termination — most keyboard PRDs get these wrong. Keep the section, tighten F18 and F39.
2. **§7's refusal to ship a provider key in the client** is correct and non-negotiable, and the BYOK-in-Keychain-for-dev carve-out is the right pragmatic answer for a single user.
3. **§5's "isolate the framework behind an abstraction layer"** is the right instinct, and flagging the KeyboardKit license question *before* depending on it is exactly the discipline most projects skip.
4. **§30's build priority order** (typing quality -> reliability -> speed -> teaching UI -> adaptation) is correct and should govern the rewrite. The rest of the PRD violates it; the principle itself is sound.
5. **§24's opening line** — "A poor typing experience will kill the product faster than weak AI" — is the truest sentence in the document. Promote it to §33.
6. **§25's anti-branding stance** (approximate the native keyboard, no gradients, no gamification, learning UI disappears when it has nothing to say) is right and rare.
7. **§14's "least intrusive intervention that still produces useful learning" and the per-sentence budget of one concept** is genuinely good pedagogy, and the *shape* of the adaptive policy is worth keeping even though every number in it is placeholder.
8. **§17's cancellation rule** — "never display a stale translation for text that is no longer current" — is the correct invariant, and §27 tests it.
9. **§21's default posture** (smallest useful unit, no remote retention, instant opt-out with a still-functional keyboard) is a better privacy stance than most shipping keyboards, and §23's "No Full Access -> keyboard remains fully usable" is the right degradation.
10. **§33's product principle** is a real, falsifiable one-sentence thesis. Every finding above is ultimately an argument that the document does not yet honor it.
