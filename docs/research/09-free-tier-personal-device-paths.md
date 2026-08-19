# Research 09 — Free-Tier Paths to a Personal-Device Keyboard (Italy/EU)

> Source: research subagent, 2026-08-19.
> **This report CORRECTS research 04 §1.3 and §1.4.** See §0.
> Blocked domains (claims from these rest on search summaries only): `docs.sidestore.io`,
> `appleinsider.com`, `fsfe.org`, `takazudomodular.com`, `mybyways.com`. `api.github.com` was
> rate-limited. Everything marked CONFIRMED was fetched directly on 2026-08-19.

---

## 0. Headline — and a correction to research 04 §1.3/§1.4

**Research 04 §1.3 and §1.4 are wrong. App Groups and Keychain Sharing are NOT paid-membership features.**

**CONFIRMED** — https://developer.apple.com/help/account/reference/supported-capabilities-ios/ (fetched 2026-08-19). Apple's capability matrix has three columns, `ADP | ADEP | Apple Developer`, where the third is defined verbatim as:

> "**Apple Developer:** Apple Account holders who have agreed to the Apple Developer Agreement to access certain resources on the Apple Developer website. **No cost is associated with this agreement** and developers can't distribute apps."

Rows, from the source markup:

| Capability | ADP | ADEP | Apple Developer (free) |
|---|---|---|---|
| **App groups** | yes | yes | **yes** |
| **Keychain sharing** | yes | yes | **yes** |
| Push notifications | yes | yes | no |
| Network extensions | yes | yes | no |
| Apple Pay | yes | no | no |

The Apple DTS quote research 04 relied on ("App Groups are mediated by the developer web site") is accurate but was **over-read**. It says the *portal* must mint the group. It does not say the portal refuses free teams. **It does not.**

**Independent code-level corroboration (CONFIRMED, source read directly):** AltStore's production signing path calls Apple's developer-portal API to *create* App Group identifiers, with no paid-team gate anywhere:

- `AltSign/Apple API/ALTAppleAPI.h:71` — `addAppGroupWithName:groupIdentifier:team:session:`
- `AltStore/Operations/FetchProvisioningProfilesOperation.swift:385-470` — `updateAppGroups(for:app:team:session:)`. Flow: `registerAppID -> updateFeatures (features[.appGroups] = true) -> updateAppGroups (create + assign) -> fetchProvisioningProfile`. The **only** `team.type == .free` branch in that file (line 261) is the 10-App-ID cap.
- `AltStore/Operations/ResignAppOperation.swift:126` — `if let appGroups = profile.entitlements[.appGroups] as? [String]`, i.e. the fetched profile *does* carry the app-group entitlement.
- `AltStore/AltStore.entitlements` and `AltWidget/AltWidgetExtension.entitlements` both declare `com.apple.security.application-groups`; AltStore.entitlements also declares `keychain-access-groups`. **AltStore Classic ships an app plus an app extension sharing an App Group and a keychain group, installed by millions of users on free Apple IDs.**

**What is actually gated is Xcode's UI, not the entitlement.** The widely-reported "Provisioning profile doesn't include the application-identifier and keychain-access-groups entitlements" errors on personal teams are Xcode's automatic-signing behaviour, not a portal refusal. **LIKELY, not CONFIRMED:** no Apple statement or first-hand 2026 report was found confirming Xcode's Signing & Capabilities pane will add App Groups for a Personal Team. The known hard-blocked Xcode error string is capability-specific — *"Personal development teams … do not support the **Push Notifications** capability"* (CONFIRMED) — and Push Notifications is exactly a row the matrix marks **no** for free. Suggestive, not proof.

**So the real gate is not shared state. It is the 7 days.**

---

## 1. Sideloading tools, August 2026

### 1.1 The 7-day limit is still real, verified today

**CONFIRMED** — https://developer.apple.com/support/compare-memberships/ and https://developer.apple.com/help/account/basics/about-your-developer-account/, both re-fetched 2026-08-19, verbatim:

> "The number of App IDs that can be registered your account at one time is limited to 10 and each expires after 7 days. The number of test devices … is limited to 3 and each expires after 7 days. **Provisioning profiles will expire 7 days from issuance, which may require you to rebuild and re-install your app to your device after expiration.**"

A search summary claimed free personal-team profiles now last 1 year. **FALSE / misparse** — Apple's own pages, fetched today, still say 7 days.

### 1.2 AltStore Classic — alive, maintained, works on iOS 26.4

**CONFIRMED** (AltStore FAQ repo cloned, HEAD 2026-07-28):
- "Apps installed with AltStore expire after 7 days… AltStore will attempt to 'refresh' your sideloaded apps in the background… you can only have 3 sideloaded apps installed on a device at a time."
- **AltServer 1.7.4 (Windows), 2026-03-24 — "Fixed apps crashing on launch on iOS 26.4."** 1.7.3, 2026-02-08 — "Fixed -22410 error when installing and refreshing apps." **Actively maintained against current iOS.**
- "Every app you sideload with AltStore requires a certain number of 'App IDs'… which depends on the **number of app extensions each app contains**."

**Day-to-day refresh, honestly:** background refresh works *only when it can reach AltServer on your Mac/PC over the same Wi-Fi*, plus an "Add to Siri" Shortcut for manual triggering. The computer must be awake, on the LAN, running AltServer at least once every 7 days.

**New in 2026 — computer-free refresh (CONFIRMED, `altstore-classic/no-computer-instructions.md`):** *"This feature is still in **beta and only available on Patreon**."* Requires AltServer 1.8+. One-time USB pairing, then install **LocalDevVPN** from the App Store (`id6755608044`), tap Connect, be on Wi-Fi. AltStore Classic has converged on SideStore's architecture, but still needs one USB pairing session and (currently) a Patreon membership.

### 1.3 SideStore — actively developed, most fragile link

**CONFIRMED** (repo cloned 2026-08-19). Last commits **2026-08-19** and **2026-08-18**. Tags `v1.6.3`, `1.4.3`, plus nightly/alpha channels. **A repo being worked on today.**

README, verbatim: *"SideStore resigns apps with your personal development certificate, and then uses a specially designed VPN in order to trick iOS into installing them… By leveraging a custom-built App Store app with additional entitlements (**LocalDevVPN**) to create the VPN tunnel for us, it allows SideStore to take advantage of Jitterbug's loopback method **without requiring a paid developer account**."*

**LIKELY** (docs blocked): StosVPN was pulled from the App Store; LocalDevVPN is the current iOS 26 path; a pairing file is still required, generated once from a computer, and *"pairing files randomly break — when this happens you need computer access to regenerate the file."*

**iOS 26.4 breakage (LIKELY):** iOS 26.4 beta changed lockdown connection validation, breaking SideStore's on-device signing; fixed in a nightly. Corroborated in spirit by the CONFIRMED AltServer 1.7.4 fix. **The recurring pattern: every few iOS point releases sideloading breaks for days-to-weeks and you run a nightly build to recover.**

### 1.4 The entitlements question, answered

**App Groups and keychain sharing survive sideloading. CONFIRMED at source level** (§0), corroborated by:
- **CONFIRMED** — SideStore issue #782 (closed): an IPA with >3 `keychain-access-groups` or App Groups failed in SideStore, but *"the same IPA installs without issue in AltStore."* No free/paid distinction anywhere in the thread — which only makes sense if free-account app groups work at all.
- AltStore error codes 3014 "The provided app group is invalid" / 3015 "App group does not exist" exist precisely because app-group registration is routine in the free-account path.
- Release notes: "Fixed potentially registering an app group twice when sideloading an app containing app extensions"; "Fixed resigning apps with wildcard `keychain-access-groups` entitlement."

**Practical ceiling: <=3 App Groups and <=3 keychain-access-groups on SideStore (LIKELY).** You need one of each. Non-issue.

**Concrete code requirement (UNVERIFIED but source-derived):** AltStore **rewrites** bundle IDs and group IDs by appending your Team ID (`group.your.group` -> `group.your.group.<TEAMID>`; `FetchProvisioningProfilesOperation.swift:445`) and injects the rewritten list into `Info.plist`. **Your code must read the group ID from `Info.plist` at runtime, not hardcode the string**, or the shared-container lookup fails after sideloading.

### 1.5 App extensions — supported, at a cost

**CONFIRMED** — `let requiredAppIDs = 1 + application.appExtensions.count`. A keyboard app = **2 App IDs** (host + keyboard extension) of 10 per rolling 7 days. Extensions are *supported*, not stripped — but the sideloaders prompt you to optionally **remove** extensions to stay under the cap. For a keyboard you obviously say keep.

Whether the pair consumes 2 of 3 active-app slots: **UNVERIFIED**, **LIKELY 1** — AltStore counts *apps* (`freeAccountActiveAppsLimit = 3`, verbatim comment: *"Free developer accounts are limited to only 3 active sideloaded apps at a time as of iOS 13.3.1"*) and the extension is nested in the host bundle. The sideloader itself occupies one slot, so you have 2 free either way.

### 1.6 LiveContainer — definitively cannot work

**CONFIRMED** — LiveContainer README, verbatim:
> "**App extensions aren't supported.** they cannot be registered because: LiveContainer is sandboxed, SpringBoard doesn't know what apps are installed in LiveContainer, and they take up App ID."

LiveContainer is the standard 2025-26 answer to the 3-app limit and is **useless for a keyboard** — a keyboard extension must be registered with SpringBoard to appear in Settings > General > Keyboards. **Ruled out.**

### 1.7 Newer alternatives, 2025-2026

Nothing changes the calculus. The 2026 landscape is AltStore Classic (+ remote AltServer/LocalDevVPN), SideStore (+ LocalDevVPN), LiveContainer (no extensions), and Sideloadly / iOS App Signer (one-shot desktop signing, no auto-refresh). **LIKELY** — no 2026-era tool escapes the 7-day profile, because none can: **the expiry is enforced by Apple's signing service, not by the client.**

---

## 2. EU DMA alternative distribution — Italy, 2026

**Every EU alternative-distribution path is a superset of the $99 membership, not an alternative to it.**

### 2.1 AltStore PAL
- **User cost: EUR 0** (LIKELY, converging sources + FAQ artifact). The EUR 1.50/yr fee was dropped 2024-08-15 after an Epic MegaGrant covering Apple's Core Technology Fee. Still shipping: **AltStore PAL 2.3.2, 2026-06-15** (CONFIRMED).
- **Developer cost: paid ADP membership, mandatory. CONFIRMED**, verbatim: *"You will still submit apps through **App Store Connect using your paid Apple Developer account**, so make sure you are set up with one before proceeding."* and *"Even though you are distributing outside the App Store, you still need to **submit your app(s) to Apple for Notarization**."* Plus the Alternative EU Terms Addendum, Developer ID registration with PAL, self-hosting an Alternative Distribution Package, and publishing a source JSON.
- What PAL buys (CONFIRMED, its own comparison table): **no 7-day expiry, no 3-app limit, full iOS app capabilities, no computer, no Apple ID password.** Exactly what you want, and unreachable without $99.

### 2.2 Apple Web Distribution
**CONFIRMED** — https://developer.apple.com/support/web-distribution-eu (fetched 2026-08-19). As of the **2026-10-01** unified-EU-terms transition the "EUR 1,000,000 of standing / two years' membership" gate is **partially relaxed but not removed.** You must meet baseline obligations *and* **at least one** of:

1. Fee waiver (nonprofit / accredited educational institution / government)
2. Dun & Bradstreet Global Business Ranking of Low or Below Average Risk
3. Listed on a WFE or Euronext exchange
4. VC funding from a Midas List / Midas List Europe / Invest Europe / HEC-Dow Jones firm
5. **Stand-by letter of credit of USD 1,000,000** from a BBB- or better institution, held 6+ months
6. Unqualified financial audit by an accredited firm within 3 years
7. **1,000,000 first annual installs worldwide** in the prior calendar year, *and* 2+ continuous years of membership in good standing

**What changed vs 2024-25 (CONFIRMED):** the blanket two-years-good-standing precondition and the EU legal-entity requirement were dropped — they now attach only to option 7. **A relaxation for funded startups and audited companies, not for a solo developer.** A private individual in Italy with no company, audit, VC or million-install app meets **none** of the seven. Not struck down by regulators; still in force, restated 2026-08-18.

Moot regardless: Web Distribution is a capability granted **inside an Apple Developer account** — *"you'll need to be the Account Holder of your **membership**."*

### 2.3 Core Technology Fee -> Core Technology Commission
**CONFIRMED** — https://developer.apple.com/support/dma-and-apps-in-the-eu/ (page updated 2026-08-18), verbatim:
> "The Core Technology Fee, a per-install fee for developers who achieve extraordinary scale, will be replaced by the **Core Technology Commission, a simple 5% commission on digital transactions in apps distributed outside the App Store**."

Effective **2026-10-01**. **For a zero-revenue personal keyboard, both are EUR 0.** Neither is the gate.

### 2.4 Bottom line
**There is no DMA-derived path for an Italy-based individual to get a self-built app onto their own iPhone without the $99.** Every EU route requires (a) an ADP membership as the *floor*, and (b) Apple notarization; web distribution additionally requires a corporate/financial credential an individual cannot produce. **The DMA opened distribution to third parties, not development to non-members.**

---

## 3. Other paths, ruled out explicitly

| Path | Verdict | Evidence |
|---|---|---|
| **Xcode direct install** | Works; **7 days**, then the app refuses to launch. Rebuild + reinstall with the device attached resets the clock. No way to extend | **CONFIRMED**, Apple: "Provisioning profiles that enable apps to be installed on a device will expire 7 days from issuance" |
| **Apple Configurator / `cfgutil`** | **Not a signing tool.** Installs an already-validly-signed IPA; cannot mint or extend a profile, so it inherits the same 7 days. Zero benefit over Xcode | **LIKELY**; mechanism unambiguous |
| **Developer Mode (iOS 16+)** | Required, must stay enabled. Free. Not a gate, but a permanent state | **LIKELY** |
| **Apple Developer Enterprise Program** | **Ruled out.** $299/yr, requires **100+ employees** and a legal entity, for internal employee-only distribution. An individual cannot enroll | **CONFIRMED** — https://developer.apple.com/it/support/enrollment/ |
| **Fee waiver** | Accredited educational institutions, nonprofits, governments only | **CONFIRMED** |

**ADP individual enrollment in Italy (CONFIRMED, Apple's Italian support page):** 99 USD/yr in local currency (**~EUR 99/yr LIKELY** on the Italian storefront), Apple Account with 2FA, legal age of majority, personal legal name as seller. **No D-U-N-S, no partita IVA, no company.** Trivially available.

---

## 4. What a year of free-tier friction actually costs

### 4.1 Path A — Xcode tether, weekly
Per cycle: plug in USB, open Xcode, run the host app, wait for install + extension registration, unlock phone, dismiss trust prompts. **~4-6 minutes** if nothing goes wrong. Over 52 weeks: **~4-5 hours/year of pure tax**, plus a recurring calendar reminder you cannot ignore, plus needing your Mac physically present every 7 days (travel, holidays, a dead SSD all break it).

Additional risks: after 10 App IDs in a rolling week you are locked out (2 per reinstall -> 5 reinstalls/week ceiling; you *will* hit it during a heavy iteration day and be blocked for days; **CONFIRMED**, error 3013). Reinstall may reset the keyboard's **"Allow Full Access"** toggle and any UserDefaults outside the shared container — **UNVERIFIED**, but a plausible weekly re-onboarding.

### 4.2 Path B — AltStore/SideStore auto-refresh
**Steady state: ~0 minutes/week.** That is the honest best case and it is genuinely good.

**Non-steady state, from 2026 evidence:**
- iOS point releases break the lockdown/pairing layer. **CONFIRMED**: AltServer shipped fixes for iOS 26.4 (2026-03-24) and a -22410 install error (2026-02-08); iOS 18 broke verification (2024-09-16). **Expect 2-4 breakages/year, each costing hours-to-weeks of a dead keyboard until a nightly lands.**
- Pairing files "randomly break" and regenerating one **requires a computer** (LIKELY).
- Background refresh needs the phone to wake the app within the 7-day window; iOS background scheduling is not a guarantee. Miss it abroad and you are on the stock keyboard until you reach a computer.
- LocalDevVPN is an App Store app maintained by one person; StosVPN was already pulled once (LIKELY). Single point of failure.
- AltStore's own no-computer mode is **Patreon-gated beta** as of 2026-07-28 (CONFIRMED).

### 4.3 The failure mode on a daily driver — this is what decides it

When the profile expires:
- The host app will not launch and iOS refuses to load the appex. **LIKELY:** the keyboard either disappears from the rotation or renders dead/blank; iOS falls back to the system keyboard. **UNVERIFIED** exactly which — no Apple documentation of appex-expiry UX exists.
- It happens **silently and mid-sentence**, in whatever app you are typing in. No warning banner, no grace period, no "your keyboard expires tomorrow" notification.
- Recovery requires a laptop or a working sideloader, i.e. **not something you can fix from the message you are currently trying to send.**

For a product whose success condition is "leave it enabled as the default keyboard for normal daily messaging," a silent weekly kill switch with laptop-dependent recovery is not friction. It is a defect that will make you turn the keyboard off and never turn it back on.

### 4.4 The arithmetic

EUR 99/yr = **EUR 1.90/week ~= EUR 0.27/day.** Against 4-5 hours/year of tethered re-signing, or 2-4 multi-day outages/year on a tool Apple periodically breaks, on the keyboard you type everything into.

What the $99 actually buys, **corrected**:

| | Free tier | $99 ADP |
|---|---|---|
| App Groups | **yes** (capability exists; Xcode UI may refuse, use a sideloader) | yes |
| Keychain sharing | **yes** (same caveat) | yes |
| **Profile lifetime** | **7 days** | **1 year** |
| App IDs | 10, rolling 7-day expiry | no weekly churn |
| Devices | 3, expire every 7 days | 100/platform/year |
| Active sideloaded apps | 3 | n/a |
| TestFlight / ad hoc / notarization | no | yes |
| EU alternative distribution | no (membership is the floor) | yes (PAL; web dist. still gated by the 7 criteria) |

**The $99 buys one thing that matters here: 1-year profiles instead of 7-day ones.** Everything else you either already have free or do not need. But that one thing is the whole product.

---

## 5. Conclusion

**The free path is not viable for a daily-driver keyboard. Pay the $99. It is effectively mandatory, but for a different reason than research 04 states, and that distinction changes the architecture, not the budget.**

1. **Correct the record.** App Groups and Keychain Sharing are **available on the free tier** per Apple's own capability matrix, and AltStore proves the portal API honours them for free teams. PRD §12 P0 (shared App Group settings), §19 (persistence) and §7 (BYOK via keychain group) are **not** blocked by the free tier.
2. **The actual blocker is the 7-day provisioning profile**, re-confirmed on Apple's pages 2026-08-19. No jailbreak-free way to extend it, and no sideloader can — the expiry is server-side at signing time.
3. **EU alternative distribution is not an escape hatch.** AltStore PAL is free for *users* and requires a paid ADP account plus notarization for *developers*. Web Distribution's gate loosened on 2026-10-01 terms but still needs one of seven corporate/financial credentials. An Italian sole individual meets none. CTF -> CTC (5%, from 2026-10-01) is EUR 0 for a free personal app and is not the gate.
4. **Enterprise Program ruled out.** $299/yr, 100+ employees, legal entity.
5. **Best free configuration, if trying it for a few weeks:** SideStore or AltStore Classic + LocalDevVPN, keyboard extension kept (2 of 10 App IDs), App Group created automatically by the sideloader, **and read the app-group ID from `Info.plist` at runtime rather than hardcoding it.** Budget 2-4 multi-day outages/year keyed to iOS point releases. **A development convenience for Phase 0, not the shipping configuration.**
6. **Sequencing verdict:** "personal use first, pay later" is *defensible* for Phase 0 architecture work — you can build and validate the App Group + keychain design on a free account, which research 04 said you could not. But **the $99 must land before you start using this as your actual keyboard**, i.e. before the first dogfooding milestone, not before App Store submission. A few weeks of runway, not a blocker.
