# Research 04 — Distribution, Provisioning & Compliance

> Source: research subagent, 2026-08-18. All URLs fetched that day unless noted.
> **Egress caveat:** `help.openai.com`, `platform.openai.com`, `openai.com`, `anthropic.com/legal`,
> `developers.cloudflare.com`, `vercel.com`, `docs.deno.com`, `help.apple.com` were blocked by the
> sandbox proxy. Claims sourced from those domains are marked LIKELY and rest on search summaries.

---

## 1. Free personal team vs paid Apple Developer Program

### 1.1 What the free tier gives you

**CONFIRMED** — https://developer.apple.com/help/account/basics/about-your-developer-account, verbatim:

> "To install and test your apps on a personal device, you'll need to sign in to your Apple Account in Xcode. If your account is not associated with a developer program membership, Xcode will indicate it's a Personal Team. Your account's App IDs, devices, certificates, and provisioning profiles are managed directly in Xcode, and you'll be required to reprovision your apps to a device periodically."

| Limit | Value | Status |
|---|---|---|
| App IDs | **10 max, each expires after 7 days** | CONFIRMED |
| Devices | **3 max per platform, expire after 7 days** | CONFIRMED |
| Apps installed per device | **3** | CONFIRMED |
| Provisioning profile lifetime | **7 days from issuance** | CONFIRMED |

**CONFIRMED** — https://developer.apple.com/support/compare-memberships/. Membership-gated: Certificates/Identifiers & Profiles; App Store Connect; TestFlight; Xcode Cloud; code-level support; notarization; Ad hoc distribution; custom app distribution. Free tier gets only beta Xcode/OS releases, on-device testing via Xcode, Developer Forums, Feedback Assistant.

### 1.2 Can you install app + extension for free?

**Yes, mechanically. LIKELY (strong).** Each target needs its own App ID; you have 10. The "3 apps per device" limit counts installed containers, and a keyboard extension is nested inside its host app's bundle, so the pair should consume one slot. **UNVERIFIED**: no Apple statement explicitly says extensions do not consume a separate slot. Budget for it possibly counting as 2 of 3.

### 1.3 Does a free personal team support App Groups? — **NO**

The load-bearing answer, and the PRD's biggest exposure.

1. **CONFIRMED** — Apple DTS (Quinn "The Eskimo!"), https://developer.apple.com/forums/thread/660802, verbatim:
   > "On iOS App Groups are mediated by the developer web site. To use an App Group you must add it to the developer web site and then add it to your app's provisioning profile. An app can't use an App Group unless its profile includes the group ID in its `com.apple.security.application-groups` allowlist."

   and:
   > "It's this last point that prevents random apps from 'stealing' your App Group. The profile is created by the developer web site and it will only include an App Group in that profile's allowlist if that App Group is associated with your team."

2. **CONFIRMED** — that "developer web site" is Certificates, Identifiers & Profiles, listed under **"Features Requiring Membership."** A personal team's identifiers are managed in Xcode, not on the portal, and Xcode's automatic signing cannot mint an App Group identifier the portal never issued.

3. **Corroboration (LIKELY)** — third-party guides uniformly instruct "Both your app and its extension must be added to the same App Group in the Apple Developer portal." KeyboardKit's own docs note its demo "isn't code signed and can therefore not use an App Group to sync settings between the app and its keyboards."

**Verdict: App Groups on a free personal team — NOT AVAILABLE (LIKELY, with a CONFIRMED mechanism).** No Apple sentence says it outright; the conclusion follows from the portal-mediation mechanism, which is directly confirmed by Apple DTS.

**Consequence:** PRD §12 P0 ("Shared App Group settings"), §19 (entire Persistence section) and §26 Phase 0 ("App Group") **cannot be built on a free account.** There is no workaround.

### 1.4 Keychain access groups — **NO (for cross-target sharing)**

- **LIKELY** — Keychain access groups are prefixed with an App ID prefix allocated through the Apple Developer Program; `keychain-access-groups` is portal-mediated the same way. Apple: "third-party apps use access groups with a prefix allocated through the Apple Developer Program in their application groups" (https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps).
- **LIKELY** — personal-team users widely report `Provisioning profile doesn't include the application-identifier and keychain-access-groups entitlements`, with one thread participant summarising "all issue are from personal team" (https://developer.apple.com/forums/thread/114539). No Apple staff resolution.
- **Single-target Keychain works fine.** Sharing that item with the extension does not.

**Consequence:** PRD §7's "Developer BYOK Mode … shared with the extension through an appropriately configured Keychain access group" is **not achievable on a free account either.** Both shared-state channels are paid-only.

### 1.5 What breaks at day 7

**CONFIRMED:** the profile expires and the app stops launching. Rebuild + reinstall from Xcode with the device attached, weekly, forever. An expired profile means iOS refuses to load the extension, so the system keyboard silently stops working mid-week. For a product whose success condition (§2) is "leave LinguaKey enabled as the default keyboard for normal daily messaging," a 7-day kill switch is a product-level defect.

### 1.6 TestFlight / ad hoc without paying — **NO**

**CONFIRMED** — TestFlight, App Store Connect, and "Ad hoc distribution for testing and internal use" are membership-only. No free path to a second device or another person's phone.

### 1.7 Bottom line

| Item | Cost | Necessity |
|---|---|---|
| **Apple Developer Program** | **$99 / ~EUR99 per year** | **Mandatory from Phase 0**, not "App Store later." Required for App Groups, Keychain sharing, non-7-day profiles, TestFlight, any distribution. |
| LLM API usage | ~$1-8/mo at 2000 req/day, small model | From Phase 1 |
| Serverless proxy | $0 (Cloudflare Workers free tier) | Optional if BYOK-only |
| KeyboardKit Pro | Commercial license | Avoidable |

**The PRD's "personal use first, pay later" sequencing is wrong.** The $99 is a Phase 0 prerequisite.

---

## 2. App Store Review Guidelines — keyboard-specific

All quotes **CONFIRMED** from https://developer.apple.com/app-store/review/guidelines/ (fetched 2026-08-18).

### 4.4.1 — the keyboard clause, verbatim

> **4.4.1 Keyboard extensions have some additional rules.** They must:
> - Provide keyboard input functionality (e.g. typed characters);
> - Follow Sticker guidelines if the keyboard includes images or emoji;
> - Provide a method for progressing to the next keyboard;
> - **Remain functional without full network access and without requiring full access;**
> - Collect user activity only to enhance the functionality of the user's keyboard extension on the iOS device.
>
> They must not:
> - Launch other apps besides Settings; or
> - Repurpose keyboard buttons for other behaviors.

**Read against the PRD:** §23 satisfies the fourth bullet. But "Collect user activity only to enhance the functionality of the user's keyboard extension **on the iOS device**" is in tension with shipping typed sentences to a third-party LLM. The defensible reading is that translation *is* the keyboard's functionality and the data is not retained; that is how translation keyboards ship today. **LIKELY safe, not certain.** State it explicitly in reviewer notes.

### 4.4 Extensions (preamble)

> "Apps hosting or containing extensions must comply with the App Extension Programming Guide … and should include some functionality, such as help screens and settings interfaces where possible. … **the extensions may not include marketing, advertising, or in-app purchases.**"

-> No IAP or upsell inside the keyboard strip. Monetization lives in the host app.

### 4.2 Minimum Functionality

> "Your app should include features, content, and UI that elevate it beyond a repackaged website. If your app is not particularly useful, unique, or 'app-like,' it doesn't belong on the App Store."

-> PRD §20's four-screen host app clears 4.2. A setup-instructions-only container app is the classic keyboard rejection.

### 5.1.1(i) Privacy Policies

> "All apps must include a link to their privacy policy … The privacy policy must clearly and explicitly: Identify what data, if any, the app/service collects, how it collects that data, and all uses of that data. Confirm that any third party with whom an app shares user data … will provide the same or equal protection … Explain its data retention/deletion policies and describe how a user can revoke consent and/or request deletion."

### 5.1.2(i) — the AI clause (the one that matters most)

> "Unless otherwise permitted by law, you may not use, transmit, or share someone's personal data without first obtaining their permission. … **You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so.** … Apps that share user data without user consent … may be removed from sale and may result in your removal from the Apple Developer Program."

**CONFIRMED provenance** — https://developer.apple.com/news/?id=ey6d8onl, **November 13, 2025**: "**5.1.2(i):** Clarifies that you must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so."

-> **Typed sentences are personal data.** §21's onboarding explanation is necessary but not sufficient: 5.1.2(i) requires an **in-app explicit consent gate naming the AI provider** before the first remote call, plus a revocation path. The PRD has the revocation toggle; the affirmative, provider-named, pre-first-request consent does not exist in it.

### 2.5.x

> **2.5.1** "Apps may only use public APIs and must run on the currently shipping OS."
> **2.5.2** "Apps should be self-contained in their bundles, and may not read or write data outside the designated container area, **nor may they download, install, or execute code which introduces or changes features or functionality of the app**."
> **2.5.14** "Apps must request explicit user consent and provide a clear visual and/or audible indication when recording, logging, or otherwise making a record of user activity. This includes any use of the device camera, microphone, screen recordings, or **other user inputs**."

-> **2.5.2** is fine for a linked binary framework but forbids fetching a model/prompt-pack at runtime that changes functionality. Keep prompts in the binary. **2.5.14 covers "other user inputs"** — a keyboard that logs vocabulary from typed text is making a record of user activity and needs explicit consent + indication. **PRD §13's learning-state model needs a consent gate under 2.5.14 as well as 5.1.2(i).**

**No dedicated third-party-analytics clause exists in 2.5.x.** Obligations live in 5.1.1(i) and 5.1.2(i). **Recommendation: ship zero third-party analytics.**

### 4.7 — does it apply?

**No, LIKELY.** 4.7 covers software not embedded in the binary that your app offers to users. LinguaKey calls an API; it does not distribute a chatbot. If you ever expose free-form "ask the tutor anything," re-read 4.7.1/4.7.5.

### AI age rating

**LIKELY** — Apple's updated age-rating questionnaire (new 13+/16+/18+ tiers, completion required by **January 31, 2026**) asks how AI features may produce sensitive content. A constrained JSON translation tutor should rate low. Source: https://developer.apple.com/news/?id=ks775ehf (via search, not fetched directly).

---

## 3. Privacy manifests and required-reason APIs

### 3.1 Enforcement status

**CONFIRMED** — https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api: since **May 1, 2024**, App Store Connect rejects uploads using required-reason APIs without declarations.

> "Your app or third-party SDK must declare one or more approved reasons that accurately reflect your use of each of these APIs and the data derived from their use. **You may use these APIs and the data derived from their use for the declared reasons only.**"

**Per-target: LIKELY.** A `PrivacyInfo.xcprivacy` goes in each target that collects data or uses required-reason APIs. For LinguaKey: **host app needs one, keyboard extension needs one.** A shared `LinguaKeyCore` framework touching UserDefaults should carry one too.

### 3.2 Categories this product trips

| Category | Trips? | Reason code |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | **YES - certain.** §19 mandates `UserDefaults(suiteName:)` | **`1C8F.1`** - access user defaults readable only by apps/extensions that are **members of the same App Group**. Plus `CA92.1` for app-private defaults. |
| `NSPrivacyAccessedAPICategoryActiveKeyboards` | Only if you call the active-keyboards API | **`3EC4.1`** - "Providing a systemwide custom keyboard to the user must be the primary functionality of the app. **Information accessed for this reason, or any derived information, may not be sent off-device.**" |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | **Likely YES** - SQLite/SwiftData and cache eviction touch file attributes | **`C617.1`** |
| `NSPrivacyAccessedAPICategoryDiskSpace` | Only if you bound the cache by free-disk checks | **`E174.1`** - "may not be sent off-device" |
| `NSPrivacyAccessedAPICategorySystemBootTime` | **Possible** - `mach_absolute_time`/`systemUptime` for debounce or latency timing | **`35F9.1`** - "may not be sent off-device," with an exception for elapsed time between in-app events |

**Trap:** `3EC4.1`, `35F9.1`, `E174.1`, `C617.1` all carry **"may not be sent off-device."** If debounce timings or keyboard-inventory data ever enter a telemetry payload (§6 lists a "telemetry interface"), you break the declaration you signed. Keep §22 performance metrics strictly on-device.

### 3.3 Third-party SDKs

**CONFIRMED** — https://developer.apple.com/support/third-party-SDK-requirements/:

> "You must include the privacy manifest for any SDK listed below when you submit new apps … **Signatures are also required in these cases where the listed SDKs are used as binary dependencies.**"

**KeyboardKit / OpenKeyboardKit are NOT on the list.** But KeyboardKit ships as a **binary framework**, so you cannot audit or add its manifest yourself; you depend on the vendor. If KeyboardKit touches UserDefaults (it does — its `appGroupId` feature is App Group UserDefaults sync), **its declarations become your submission's problem.** Verify before adopting.

### 3.4 Nutrition-label answers

Assuming sentences -> proxy -> LLM; no account; no analytics; no ads; nothing retained server-side.

| Question | Answer | Basis |
|---|---|---|
| **User Content -> Other User Content** | **Collected. Purpose: App Functionality. Not Linked to You. Not used for tracking.** | The typed sentence is user-generated content and it leaves the device. "Not Linked" requires no identifier travelling with it. |
| **User Content -> Emails or Text Messages** | **Avoid this box.** §18 forbids sending prior conversation messages; hold that line — ticking this on a keyboard is a review red flag. | §18 |
| **Identifiers -> Device ID / User ID** | **Not collected** — *only if* your proxy auth token is not a per-user identifier you log. A static shared bearer token never logged is defensible; a per-install UUID logged with requests is a Device ID. | Apple's "Not Linked" test |
| **Diagnostics** | Not collected | recommendation |
| **Usage Data -> Product Interaction** | Not collected (learning state on-device only) | §19 |
| **Data Used to Track You** | **None** | CONFIRMED definition |

**The "Optional Disclosure" escape does not apply** — it requires collection to occur "only in infrequent cases that are not part of your app's primary functionality." Translation *is* the primary functionality. **You must disclose User Content.**

**Critical nuance:** the moment the LLM provider retains text for any period (e.g. a default 30-day abuse-monitoring window), the honest answer to "does a third party receive this" is yes, and 5.1.1(i) requires naming them and confirming equal protection. Use zero-data-retention / no-training settings where offered, and say so.

---

## 4. The Full Access trust problem

### 4.1 What Full Access unlocks - and what it takes away

**CONFIRMED** — https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard and the App Extension Programming Guide.

With `RequestsOpenAccess = true` **and** the user's toggle on: "Option to use a **shared container** with the keyboard's containing app"; "Ability to send keystrokes, other input events, and data over the network for server-side processing"; `UIPasteboard`; `playInputClick` (keyboard click sounds); Location/Contacts/Camera Roll with permission; iCloud; IAP via containing app.

With Full Access **off** (default), verbatim from Table 8-1:
- "**No shared container with containing app**"
- "**No access to file system apart from keyboard's own container**"
- "No ability to participate directly or indirectly in iCloud, Game Center, or In-App Purchase"

> **This breaks PRD §23 and §19.** §23's "No Full Access -> keyboard remains fully usable for typing" plus "Extension restart -> Reload settings and vocabulary state from shared persistent storage" are mutually inconsistent: **without Full Access there is no shared persistent storage, and no keyboard click sound either.**
>
> Design implication: the extension needs its **own private-container** copy of settings/vocabulary, written by the extension itself, as the no-Full-Access fallback. Host-app settings cannot reach the keyboard until Full Access is on. Reports vary on whether reads are one-way or fully blocked — treat App Group access as **unavailable** without Full Access and design accordingly.

### 4.2 Apple's stated developer obligations - verbatim

| Capability | Developer responsibility |
|---|---|
| Shared container with containing app | "Store data securely, and use only for the purpose of text input" |
| Sending keystroke data to your server | "**Transmit data securely, and use only for the purpose of text input**" |
| Dynamic autocorrect lexicon from network data | "Don't associate the user's identity with their use of trending or other network-based information, for any reason that isn't obvious to the user" |

> "**Don't store received keystroke or voice data beyond the time needed to provide text back to the user or to provide features that you explain to the user.**"

> "Open access keyboards must adhere to networked keyboard guidelines in App Store Review Guidelines and iOS Developer Program License Agreement."

**The strongest single constraint on the PRD.** "Use only for the purpose of text input" is narrower than "language tutoring." A translation returned into the field is text input. A grammar explanation card or an active-recall quiz generated from private message content is arguably beyond it — mitigated by the "or to provide features that you explain to the user" carve-out, which makes the **onboarding explanation load-bearing, not cosmetic.**

### 4.3 The system warning users see

**LIKELY, not CONFIRMED verbatim.** No Apple-authored page with the current alert string was reachable. Two strings circulate in secondary sources:
- "Full Access allows the developer of the keyboard to transmit anything you type, including things you have previously typed."
- "If you enable Full Access, developers are permitted to access, collect and transmit the data you type."

Apple's developer docs state the intent (CONFIRMED): "Users know that when they enable this, their keystrokes are available to the keyboard developer." **Action: screenshot the actual alert on-device before writing onboarding copy.**

### 4.4 GDPR for an Italy-based solo developer

| Scenario | Assessment |
|---|---|
| **You build it, only you use it, never distributed** | **Household exemption applies - LIKELY.** GDPR Art. 2(2)(c) excludes processing "by a natural person in the course of a purely personal or household activity." You are both controller and data subject. |
| **You distribute it - free, App Store, zero revenue** | **Exemption LOST - LIKELY.** Publishing to the App Store as a named developer is a professional activity regardless of price (Recital 18 and consistent DPA guidance). |

Once distributed you owe: lawful basis (**consent**, which Apple's 5.1.1(ii) already forces), Art. 13 transparency (identity, purposes, recipients **including the US LLM provider**, retention, rights), Art. 44-49 transfer basis for US providers (SCCs / EU-US DPF), an Art. 28 processor agreement, and Art. 30 records — with the Art. 30(5) small-entity relief not applying cleanly because the processing is not occasional.

**UNVERIFIED:** whether Italy's Garante has issued anything specific on keyboard apps. Nothing found.

### 4.5 EU DSA trader status - a real, often-missed blocker

**LIKELY** — under DSA Articles 30/31 Apple verifies and **publicly displays** trader contact info — **address, phone number, email** — on the App Store product page for apps distributed in the EU. Deadline was **17 February 2025**; apps without verified trader status were removed from the EU App Store on 18 February 2025.

-> **A solo developer in Italy publishing this app publishes their home address and phone number.** Plan for a registered business or service address before submission. This is a personal-safety decision, not a formality.

---

## 5. BYOK / API-key handling

### 5.1 Is it possible?

**(a) Technically - YES, CONFIRMED by mechanism.** With Full Access on, the extension can make arbitrary HTTPS calls and the key can live in Keychain. **But** sharing the key host app -> extension requires a keychain access group, which requires the paid program. Alternative: the user pastes the key **into the keyboard's own settings UI**, so it never crosses the target boundary — worse onboarding, no entitlement needed.

**(b) Provider ToS - allowed, LIKELY.** No provider forbids an end user supplying their own key to a client they run. Anthropic's `anthropic-dangerous-direct-browser-access` header exists precisely to permit client-side calls; the documented rationale is that in a BYOK tool the key belongs to the user. CORS is irrelevant to a native app. **UNVERIFIED:** OpenAI's own pages were egress-blocked, so the PRD's cited OpenAI key-safety article is unverified today; its substance is consistently reported and stated in equivalent form by Anthropic.

**Anthropic key guidance - CONFIRMED**, https://platform.claude.com/docs/en/manage-claude/authentication: API keys are for "Local development, prototyping, scripts, and **single-tenant servers where you control secret storage**." Keys now carry a chosen expiration (3h / 1d / 7d / 30d / custom / Never).

**(c) App Store review - allowed but risky, LIKELY.** No guideline forbids BYOK. Exposure: **4.2** (an app that does nothing until a key is pasted reads as incomplete — mitigated here, the keyboard works without one); **2.1** (give the reviewer working credentials or a demo mode); **5.1.2(i)** still applies in full. **3.1.1 is not triggered.**

### 5.2 The finding that changes the architecture: Anthropic App Attest

**CONFIRMED** — https://platform.claude.com/docs/en/manage-claude/app-attest, verbatim:

> "App Attest authenticates iOS and macOS apps that call the Claude API directly from the device, with usage billed to your workspace. … Anthropic then issues the device a short-lived access token that bills usage to your workspace. **The app ships no API key, and there is no proxy for you to operate.**"
>
> "Tokens are scoped to your workspace, expire after one hour, and authorize only Messages API calls. They carry no end-user identity."

Setup: add the **App Attest** capability under Signing & Capabilities, register your **Apple Developer Team ID** and up to 32 bundle IDs in the Claude Console.

**Caveats (all CONFIRMED from the same page):**
- Ships via the Claude for Foundation Models Swift package, **in beta: "it requires the OS 27 betas, and APIs might change before general availability."**
- "App Attest requires a physical device. The Simulator, and hardware without a Secure Enclave, cannot perform App Attest."
- Requires an Apple Developer Team ID -> paid program again.
- **UNVERIFIED:** whether `DCAppAttestService` attestation works from inside a *keyboard extension* process. Extensions have their own bundle IDs and you can register 32, so it is at least mechanically possible. Test before betting on it.

### 5.3 What shipping apps do

**KeyboardKit Pro** ships BYOK LLM integration as a first-class API: `nextWordPredictionRequest: .claude(...)` in its `KeyboardApp` config (CONFIRMED, KeyboardKit README fetched 2026-08-18). BYOK-from-a-keyboard-extension is an established shipping pattern, not exotic.

### 5.4 Recommendation

1. **Personal phase:** BYOK, key entered in the keyboard's own settings, stored in the extension's own Keychain (no access group needed). Zero infrastructure, zero proxy hop, zero server cost.
2. **Distribution phase:** proxy with a server-held key (or App Attest once GA). Keep BYOK as an advanced opt-in — the PRD's "remove or disable before distributing" is over-cautious.
3. Never ship *your* key in the binary.

---

## 6. Serverless proxy options (2026)

Cold-start figures **LIKELY** (aggregated secondary benchmarks; vendor docs egress-blocked).

| | Cold start | Free tier | Cost @ 2000 req/day (~60k/mo) | Auth for one device | Streaming | EU latency |
|---|---|---|---|---|---|---|
| **Cloudflare Workers** | **<5 ms** (V8 isolates) | 100k req/day; 10 ms **CPU**/req; 128 MB; 50 subrequests | **$0** | Static bearer in `env` secret + token in Keychain | Yes - `ReadableStream`, SSE pass-through | Nearest PoP -> **single-digit ms from Italy** |
| Vercel Functions | 50-250 ms edge / 200-800 ms Node | Hobby: 1M invocations, 4 CPU-hrs | $0 - **but Hobby is non-commercial-use only**; Pro $20/seat/mo | Env var + bearer | Yes | Good |
| Deno Deploy | <5 ms | 1M req/mo, 100 GB egress, 50 ms CPU/req | $0 | Env var + bearer | Yes | Good |
| AWS Lambda + Function URL | 200 ms-1 s+ | 1M req + 400k GB-s/mo | ~$0 | IAM_NONE + bearer | Yes (`RESPONSE_STREAM`) | Cold starts hurt |
| Fly.io | N/A always-on, or ~1-3 s from scale-to-zero | **No free tier since 2024** | ~$1.94/mo always-on | Build your own | Yes | `fra`/`mad`, excellent |

### Recommendation: Cloudflare Workers

1. **The <1.5 s target is dominated by the LLM, not the proxy.** A ~5 ms isolate start plus ~5-15 ms EU PoP RTT is noise. A Lambda cold start of 400 ms consumes ~27 % of the budget on the first request after idle — and a personal keyboard is *always* idle-then-bursty, so you hit cold starts constantly. This eliminates Lambda and Fly-scale-to-zero.
2. **10 ms CPU limit is a non-issue**: CPU time excludes time awaiting `fetch()`. A pass-through proxy uses ~1-2 ms.
3. **60k req/mo vs 3M/mo free** — 50x headroom, permanently $0.
4. **Vercel Hobby's non-commercial restriction** is a dead end the moment you monetize.
5. **Auth for a single personal device without accounts:** generate a 32-byte random token, `wrangler secret put`, put the same value in the keyboard's Keychain during onboarding. Compare with a **constant-time** check. Add `cf.ipCountry` gating and a KV-backed request counter. Later upgrade to DeviceCheck/App Attest verified server-side. Do **not** use Cloudflare Access — it needs an interactive browser login, hostile inside a keyboard.
6. **Placement:** default routing (nearest PoP) is right when the origin is a US LLM API and the user is in Italy. Skip Smart Placement.

**Latency reality check (LIKELY, reasoned not measured):** Italy -> CF PoP ~5-15 ms; PoP -> US LLM ~90-120 ms RTT; TTFT ~250-600 ms; full short JSON ~500-1100 ms. **Total ~0.7-1.4 s — the 1.5 s target is achievable but has no slack.**

---

## 7. Bonus finding: KeyboardKit is now closed-source *and* binary-only

**CONFIRMED** — https://raw.githubusercontent.com/KeyboardKit/KeyboardKit/main/LICENSE, verbatim:

> "**Closed Source License** — Copyright (c) 2016-2026 Kankoda Sweden AB. **KeyboardKit (hereby referred to as 'the Software') is closed-source.** The Software is free to start using and has commercial pro features that require a valid license to be used. The Software's pro features must only be used in the application(s) that are included in the license agreement. The source code must not be distributed to or used by other individuals, teams or companies."

**CONFIRMED** — same repo's `main` README: license badge reads `closedsource`, and:

> "**Since KeyboardKit is a binary framework, it must only linked to the main app target.** All other targets will be able to use it without linking."

The stale `master` branch still carries the old MIT statement in its README while its own LICENSE file already says "Closed Source License" — **the README's MIT claim is obsolete and contradicted by the LICENSE in the same tree.** Do not rely on shields/GitHub metadata.

**CONFIRMED** — https://raw.githubusercontent.com/valomedia/OpenKeyboardKit/main/LICENSE: **MIT License, Copyright (c) 2016-2025 Daniel Saidi.** The fork is genuinely MIT.

**Implications:** (a) a closed binary framework in a keyboard extension is opaque for the memory ceiling, for privacy-manifest auditing, and for debugging; (b) the PRD's "isolate behind an abstraction layer" advice is now *more* important; (c) "binary framework linked only to the main app target" is a structurally awkward fit for a project whose primary product lives in the extension — verify it works in an extension-first build before committing.

---

## Blocking-risks list — resolve before Phase 0

1. **[BLOCKER] No App Groups on a free personal team.** §12 P0, §19, §26 Phase 0 all require one; App Group IDs are portal-mediated (Apple DTS, CONFIRMED) and the portal is membership-only (CONFIRMED). **Phase 0 as written cannot be delivered without paying $99.** -> Pay before writing code, or rewrite Phase 0 to drop the App Group and use extension-local storage only.

2. **[BLOCKER] No Keychain access group either.** §7's BYOK sharing fails on the same limitation. -> Pay, or have the user enter the key in the keyboard's own settings UI.

3. **[BLOCKER] 7-day profile expiry kills the core value proposition.** §2's success condition is "leave it enabled as the default keyboard for daily messaging." A free-provisioned keyboard stops loading every 7 days. No technical workaround.

4. **[BLOCKER] App Group container is unavailable without Full Access — PRD §23 is wrong.** Apple's own table: "No shared container with containing app" when open access is off (CONFIRMED). §23's reload-from-shared-storage and the P0 "Graceful offline/no-Full-Access state" are mutually inconsistent. -> Design a dual-store: extension-private store as source of truth for the keyboard, App Group store as the sync channel when Full Access is on. Decide before the persistence layer is written.

5. **[MAJOR] 5.1.2(i) requires an explicit, provider-named, in-app consent gate before the first remote call** (effective 2025-11-13, CONFIRMED). -> Add a blocking consent screen naming the AI provider and the exact data sent; log the consent; make the toggle the documented revocation path. Also required by 2.5.14 for vocabulary logging.

6. **[MAJOR] Apple's "purpose of text input" and "don't store keystroke data beyond the time needed" obligations constrain features.** Grammar explanations, recall quizzes and translation history (§12 P1) all go beyond text input and must be explicitly explained to fall under the carve-out. -> Write the explanation copy before building the features; default translation history to OFF.

7. **[MAJOR] EU DSA trader status publishes your home address and phone number.** -> Decide on a business/service address before first submission.

8. **[MAJOR] KeyboardKit is closed-source, binary-only, and paid for the features you want** (CONFIRMED). -> Decide before the abstraction layer is designed. Prototype an extension-first build to prove it links at all.

9. **[MODERATE] Privacy manifests needed in two targets from day one**, and `1C8F.1` is unavoidable given §19. Several reason codes carry "may not be sent off-device," which quietly forbids parts of §6's telemetry interface.

10. **[MODERATE] The <1.5 s target has no slack from Europe.** ~0.7-1.4 s realistic. Any cold-start-prone platform blows it.

11. **[MODERATE] Anthropic App Attest — the no-proxy, no-key path — requires OS 27 betas and is beta-status** (CONFIRMED). Whether it works from a keyboard extension is UNVERIFIED. -> Don't architect around it yet; keep the proxy interface provider-agnostic.

---

# CORRECTION NOTICE — added 2026-08-19

**Sections 1.3 and 1.4 of this report are wrong.** See [research 09](09-free-tier-personal-device-paths.md) §0 for the full evidence.

- **§1.3 "Does a free personal team support App Groups? — NO"** is **incorrect**. Apple's own
  capability matrix at
  https://developer.apple.com/help/account/reference/supported-capabilities-ios/ lists **App
  groups: yes** in the free "Apple Developer" column (a column Apple defines as "No cost is
  associated with this agreement"). Corroborated at source level: AltStore's production signing
  path creates App Group identifiers through Apple's portal API with no paid-team gate, and
  AltStore itself ships an app plus an app extension sharing an App Group, installed by millions
  of users on free Apple IDs.
- **§1.4 "Keychain access groups — NO"** is **incorrect** for the same reason; the matrix lists
  **Keychain sharing: yes** for the free tier.
- **What this report got right:** the Apple DTS quote is accurate. The error was in **over-reading
  it** — it says the portal must mint the group, not that the portal refuses free teams.
- **What is actually gated is Xcode's automatic-signing UI, not the entitlement** (LIKELY, not
  confirmed). The forum errors cited in §1.4 are Xcode behaviour, not a portal refusal. Note the
  known hard-blocked Xcode string is capability-specific and names **Push Notifications**, which
  the matrix does mark unavailable for free.
- **The conclusion that the paid membership is effectively mandatory survives, for a different
  reason**: the **7-day provisioning-profile expiry**, re-confirmed on Apple's own pages
  2026-08-19. That is the real blocker, no sideloader can extend it, and its failure mode on a
  daily-driver keyboard is a silent mid-sentence death requiring a laptop to recover.
- **Blocking-risks list**: items 1 and 2 should be struck and replaced by a single item, "7-day
  provisioning profiles make the free tier unusable as a daily driver." Item 3 stands as written.
