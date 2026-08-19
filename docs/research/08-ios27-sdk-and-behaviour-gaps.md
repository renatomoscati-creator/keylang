# Research 08 — iOS 27 SDK Floor & Behavioural Gaps

> Source: research subagent, 2026-08-18/19, closing four items earlier passes could only mark
> LIKELY or UNVERIFIED.
>
> **Applicability note added after this report was written:** the target device was
> subsequently fixed to an **iPhone 13**, which is not Apple Intelligence capable. Sections 4a,
> 4b and finding F5 concern Foundation Models, PCC and Neural Engine memory attribution, and
> are therefore **moot for this project** unless the target device changes. They are retained
> because they are correct, because they document why the on-device teaching path died, and
> because they would apply immediately on any A17 Pro or later device. Sections 1, 2, 3 and 4c
> apply regardless of device.

---

## 1. iOS SDK submission floor — CONFIRMED, and better than "safe"

**The floor is iOS 26 SDK / Xcode 26. There is no iOS 27 deadline. And as of today the App Store will not accept an iOS 27 SDK build at all.**

| Claim | Status | Source |
|---|---|---|
| "Starting April 28, 2026, apps and games uploaded to App Store Connect need to meet the following minimum requirements: iOS and iPadOS apps must be built with the iOS 26 & iPadOS 26 SDK or later" | **CONFIRMED** | [developer.apple.com/news/?id=ueeok6yw](https://developer.apple.com/news/?id=ueeok6yw), published **2026-02-03** |
| "Apps uploaded to App Store Connect must be built with Xcode 26 or later using an SDK for iOS 26, iPadOS 26, tvOS 26, visionOS 26, or watchOS 26." | **CONFIRMED** | [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/), fetched 2026-08-19 |
| **No iOS 27 / 27-SDK / 2027 entry exists anywhere on the Upcoming Requirements page.** Most future-dated item on the whole page is 2026-04-28 | **CONFIRMED** (explicit negative, verified twice with different prompts) | same page |
| iOS 27 beta SDK builds are **TestFlight only** — five consecutive entries, beta 1 -> beta 5: "You can now submit apps built with Xcode 27 beta N … **for internal and external testing**." Dates: 2026-06-10, 06-23, 07-07, 07-21, **08-11** | **CONFIRMED** | [App Store Connect release notes](https://developer.apple.com/help/app-store-connect/release-notes/) |
| Most recent **App Store** upload entry: **2026-06-25** — Xcode 26.6 / iOS 26.5 RC SDK "for the App Store". No entry has ever authorised a 27.0-SDK App Store upload | **CONFIRMED** | same page |
| Corroboration from inside Apple's own docs: the iOS 27 launch-screen note says apps without one "are rejected **when the App Store begins accepting apps built with the 27.0 SDK**" — future tense, in beta 6 | **CONFIRMED** | iOS 27 b6 release notes, 168247372 |

**Verdict: D3 confirmed, and the risk is lower than assumed.** Xcode 26 is not merely *permitted* through Phase 0-1, it is currently the *only* toolchain that can produce an App Store build. Deferring the iOS 27 SDK is the default, not a choice to defend.

Forward projection (**LIKELY**, inference not statement): Apple's observed pattern is a late-April effective date announced ~12 weeks prior. Earliest plausible iOS 27 SDK floor is **~late April 2027, announced ~February 2027** — comfortably past Phase 0/0.5/1 on an 8-14 month schedule.

## 2. Xcode 27 hard facts — all CONFIRMED

| | Xcode 27 beta 5 | Xcode 26.6 (current release) |
|---|---|---|
| Swift | **6.4** | 6.3 |
| Min macOS to run | **macOS Tahoe 26.4** | macOS Tahoe 26.2 |
| Architecture | **Apple silicon only** | Universal |
| SDKs | iOS/tvOS/watchOS/visionOS/macOS 27, DriverKit 27 | iOS 26.5 etc. |
| Deployment targets | **iOS 15 - 27** | iOS 15 - 26.5 |
| On-device debugging | **iOS 17+** | iOS 15+ |

Intel, verbatim (radar 162138432):
> "Xcode 27 will only install and run on Apple silicon Macs. The macOS 27 SDK supports back deploying Universal (Intel and Apple Silicon) apps to macOS 12 and later. Intel development is still possible with macOS versions that support Rosetta like macOS 27."

Corroborated by [forum 829619](https://developer.apple.com/forums/thread/829619) (Jun 2026): the shipped binary is arm64-only on an Intel Mac running Tahoe 26.5.

- **Deploys to iOS 26 and earlier: YES** (iOS 15-27). Adopting Xcode 27 does not force a deployment-target bump.
- **Xcode 26 remains available and submission-valid: YES** — it is the *only* submission-valid toolchain.
- **Two things that bite:** (1) on an Intel Mac, Xcode 27 is a hardware purchase, not an update; Xcode 26.6 on Intel is fine and stays fine. (2) On-device debugging floor rises iOS 15 -> **iOS 17**; irrelevant at an iOS 26 deployment target, but an old test device that attaches today may stop under Xcode 27.
- Doc-lag: as of 2026-08-19 iOS release notes are at beta 6 while Xcode release notes are still titled beta 5, and ASC's newest TestFlight entry is beta 5 (2026-08-11).

## 3. iOS 27 betas 1-6 — keyboard-extension behavioural changes

**Headline: no new 26.4-class regression has surfaced. The 26.4 regression itself has become permanent. The two real iOS 27 deltas touching this project are both *outside* the keyboard extension — one a risk, one a significant win.**

### 3a. What was searched (so the negatives are meaningful)

Full text of the iOS/iPadOS 27 **beta 6** release notes (all 96 framework sections, ~65 KB, pulled raw and grepped); full text of the Xcode 27 beta 5 notes; Apple Developer Forums Extensions and UIKit tags plus threads 800971, 842439, 789788, 795044, 829619; `KeyboardKit` RELEASE_NOTES.md on `main` (10.4 -> 10.8, Apr-Aug 2026) plus GitHub code search and four differently-worded issue queries; `azooKey` issues (EN + JA); GitHub global code search for `"iOS 27"` + keyboard symbols in Swift; ~10 web searches across MacRumors/9to5Mac/dev blogs, June-August 2026.

**Domains that blocked the agent, named rather than silently downgraded:**
- `keyboardkit.com` / `docs.keyboardkit.com` — EGRESS_BLOCKED. Substance recovered from `raw.githubusercontent.com`. Two posts unread: *"Wrapping Up an Eventful Q2"* (2026-06-15) and *"KeyboardKit 10.6.1 patch restores the host application bundle ID sync"* (2026-07-02). **That second title conflicts with the 10.6 deprecation below and is unresolved.**
- `giellalt/giellakbd-ios` — GitHub 422. Not searched. Correct owner is probably `divvun/`.
- GitHub MCP `list_issues`/`get_file_contents` are allowlisted to own repos; only `search_issues`/`search_code` work cross-repo, capping exhaustiveness.

### 3b. Positive findings

**F1 — The iOS 26.4 host-bundle-ID regression is NOT fixed in iOS 27, and the vendor has given up. CONFIRMED.**
KeyboardKit `RELEASE_NOTES.md`, verbatim:
> "since the host application bundle ID keeps returning `nil` in iOS 27, we have deprecated the `KeyboardInputViewController` `hostApplicationBundleId` property, and updated the documentation with alternate ways to handle this."

This closes a loop the stress test left open: "no way to identify the host app or return to it" is **not** a temporary 26.4 bug awaiting a fix, it is a **permanent platform fact through iOS 27**. Consequences: any host-conditional behaviour is dead. PRD §18's hard-suppression list cannot key on the host app (only on `keyboardType`/`textContentType`), and "Notes/drafts is the only coherent context for Insert ES" **cannot be detected programmatically**. KeyboardKit's shipped workaround is `KeyboardHostApplication.Picker` — *asking the user which app they are in*. That is the state of the art.

**F2 — A keyboard-input scene is now delivered to third-party apps, from beta 3. CONFIRMED, and in no release note.**
[Forum 842439](https://developer.apple.com/forums/thread/842439), OP 2026-08-18, Apple Frameworks Engineer reply same day, FB24389661: on iOS 27 beta 3, `scene(_:willConnectTo:options:)` is called **twice** at launch — once for `.windowApplication` and once for `_UISceneSessionRoleKeyboardInputScene`. Earlier iOS delivered only `.windowApplication`. Apple: *"There is no guarantee of connected scene ordering"* — always pass the scene explicitly rather than searching `connectedScenes`.

Exactly the class of unannounced behavioural change worth hunting for, and the only one found. Affects the *containing app*: any `UIApplication.shared.connectedScenes.first` misbehaves. Cheap to defend against, expensive to discover in the field.

**F3 — UIScene lifecycle becomes mandatory under the 27.0 SDK. CONFIRMED.**
> "Adopting the scene-based life cycle is required. Beginning in iOS 27 … apps built with the latest SDK must adopt the scene-based life cycle or they fail to launch."

Scope is *apps*; a keyboard extension has no `UIApplicationDelegate`. **Phase-0 action, ~30 minutes:** add `UIApplicationSceneManifest` to the containing app's Info.plist now. Free today, mandatory later.

**F4 — Launch screen mandatory under the 27.0 SDK. CONFIRMED** (168247372). Needs one of `UILaunchStoryboardName` / `UILaunchStoryboards` / `UILaunchScreen` / `UILaunchScreens`. Same Phase-0 slot as F3.

**F5 — Neural Engine memory is now attributed to your process. CONFIRMED as written; applicability to Foundation Models UNVERIFIED.**
*(MOOT for an iPhone 13 target — retained for the record.)*
iOS 27 b6 release notes, **Core AI -> New Features**, verbatim:
> "iOS 27 includes Neural Engine improvements for Apple Intelligence capable devices. **The system now restricts background access to the Neural Engine, similar to GPU usage restrictions.** Large model loading (over 1 GB) performance is improved on the Neural Engine. **Neural Engine memory usage is now attributed to your app process instead of the system, and appears in the Allocations instrument.**" (174796039)
> "Access to the Neural engine when your app is in the background requires the new entitlement: `com.apple.developer.background-tasks.continued-processing.inference`." (179282606)

This would have undermined the DTS "very minimal memory" answer that the on-device architecture rested on. The caveat: the note sits in the **Core AI** section, not Foundation Models, and whether `SystemLanguageModel`'s footprint now lands in an extension's jetsam accounting is **UNVERIFIED**. Note also that "restricts background access to the Neural Engine" is the first new Apple statement in a year bearing on "is a keyboard extension background?", and it points the wrong way.

**F6 — MetricKit now reports extension memory-limit kills. CONFIRMED. A genuine win and the strongest argument for eventually taking the 27 SDK.**
> "`MemoryExceptionDiagnostic` are available when **your app or app extension** is terminated for exceeding its memory limit." (159890067)
> "`CrashDiagnostic` now includes a `terminationCategory` …" (96078210)
> "A new Swift-first `MetricManager` API enables your app to receive `MetricReport` and `DiagnosticReport` objects through `AsyncStream`." (164439529)

This directly attacks the worst property of the memory blocker — *"no crash dialog, no crash log… You will not see this in Xcode."* On iOS 27 you will. Requires compiling against the 27.0 SDK and iOS 27 devices. (`MXMetricManager`/`MXMetricPayload` are now "no longer recommended for new adoption", 174892111.)

### 3c. Explicit negative results — searched, found nothing

| Probe | Result |
|---|---|
| **Memory-limit change for keyboard extensions** | **Nothing.** No jetsam/memory-limit item for extensions in betas 1-6. Only memory-adjacent items are F5 and F6 |
| **Launch / resize / flicker** | **Nothing platform-side.** KeyboardKit issue #1041 "iOS keyboard extensions launch with height flickering" (opened 2026-06-02, closed) and 10.6's "Minimized on-launch redraws" are **vendor mitigations, not a platform fix.** The ~390 ms flicker stands unchanged |
| **Liquid Glass margins / grey bar** | **Unchanged, Apple still has not responded.** [Forum 800971](https://developer.apple.com/forums/thread/800971) (Sept 2025) — *"the keyboard currently has no way to detect whether the host app supports Liquid Glass when opened"* — **0 replies, 1 boost, 219 views** as of 2026-08-19. KeyboardKit 10.6 shipped "additional edge insets on Liquid Glass models", again a workaround |
| **`documentContextBeforeInput` regressions** | **Zero hits** across release notes, forums, KeyboardKit, azooKey, web. No iOS 27 change. The shadow-buffer requirement stands |
| **`hasFullAccess` behaviour** | **Zero hits.** No change in iOS 27 |
| **New iOS 27 keyboard animation** | **LIKELY, secondary sources only.** Consumer press describes keys sliding up from the bottom and Liquid Glass keyboard styling applied consistently across Apple and third-party *apps*. **No developer-facing note anywhere**, and no statement whether a third-party keyboard extension participates in the animation or sits next to it looking wrong. Device-testable in 20 minutes |
| **Rumoured "alternative words" autocorrect** | **LIKELY-only, unconfirmed as shipped.** Gurman via [MacRumors 2026-04-01](https://www.macrumors.com/2026/04/01/ios-27-upgraded-keyboard-rumor/): iOS 27's stock keyboard "expands autocorrect by offering alternative words," Grammarly-style; *"a final decision on releasing the keyboard tool hasn't been made."* Not confirmed in betas 1-6. **This is a product-risk item, not a technical one** — if it ships, Apple's stock keyboard lands directly on this product's differentiator surface |
| **iOS 27-only extension SIGKILL** | Found and **dismissed.** On betas 3-4 the MDM `InstallApplication` command causes `installcoordinationd` to SIGKILL an app and its extensions over a persona-association failure. MDM-specific, irrelevant to a consumer keyboard |

## 4. Foundation Models in an app extension under iOS 27

*(4a and 4b are MOOT for an iPhone 13 target. 4c applies if a remote path is taken.)*

### 4a. Rate limiting and "background" — NOT clarified. Still UNVERIFIED

The June-2025 DTS reply on [forum 789788](https://developer.apple.com/forums/thread/789788) remains **the only statement Apple has ever made**:
> "rate limiting is not expected when your device is connected to power. This is a known issue. (153216632) Rate limiting applies when you device is on battery AND when your process is running in the background. Safari extensions run in the background. When using Foundation Models in the background, we recommend *not* streaming the responses… Instead, we recommend calling `respond`."

Checked for a 2026 update, found **none**: the thread has no replies after June 2025; the OP's follow-up (and his report that he hits the limit *on power* too) was never answered; [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/) makes **no mention** of rate limiting, background execution, app extensions or memory; the Foundation Models updates page lists no rate-limit change; and `GenerationError.rateLimited`'s documentation is one sentence with no explanation of when it fires.

**The 2x2 device test that would settle it** (retained in case the target device ever changes): a throwaway keyboard extension + containing app pair, N sequential `respond(to:)` calls (not `streamResponse`, per Apple's guidance) at 5 s / 15 s / 30 s intervals, `os_signpost` logging, catching `GenerationError.rateLimited`, sampling `phys_footprint` via `task_vm_info` around the first call. Run **{keyboard extension, foreground app} x {battery, power}**. Requires iPhone 15 Pro+, Apple Intelligence on, iOS 27 beta, paid account. ~2-3 hours.

### 4b. `PrivateCloudComputeLanguageModel` — network requirement is CONFIRMED and decisive

- **iOS 27.0+ only.** Conforms to the new `LanguageModel` protocol. **32K context** vs 4K on-device; three reasoning levels; per-person **daily quota** (higher with iCloud+).
- Requires the managed entitlement `com.apple.developer.private-cloud-compute`, **not self-serve**: App Store Small Business Program enrolment, fewer than 2M first-time downloads, and assignment by request. **Another portal round-trip layered on the paid-membership blocker, with unknown turnaround — a Phase-0 lead-time item, not a Phase-3 discovery.**
- **CONFIRMED and decisive:** *"Using PCC requires a network connection, so if the request fails because the network connection is unavailable, retry the request using the on-device model."*

That puts PCC firmly in the **Full-Access-required** column alongside `AVSpeechSynthesizer` and App Group writes — **not** in the "works without Full Access" column that made the on-device architecture worth having.

**UNVERIFIED and unaddressed anywhere:** whether a PCC request is brokered through a system daemon such that a keyboard extension's sandbox never opens a socket; and whether app extensions may carry the entitlement at all (extensions have their own bundle IDs and profiles, so an account-level managed entitlement still has to be attached to the *extension's* App ID — a portal step, and where this most plausibly fails).

### 4c. Anthropic App Attest — CONFIRMED it says nothing about extensions, either way

- **The "OS 27 betas" claim, verbatim:** *"This package targets the Foundation Models server-side language model API introduced in the OS 27 betas. APIs might change before general availability."* Requires **iOS 27 and Xcode 27 (both beta)**.
- **Setup step 1, verbatim:** *"In Xcode, add the **App Attest** capability to your **app target** under Signing & Capabilities."* — "app target". **App extensions are not mentioned anywhere on either page or in the README.** UNVERIFIED, not refuted.
- Entitlement `com.apple.developer.devicecheck.appattest-environment`, requires an explicitly registered App ID. *"App Attest requires a physical device. The Simulator, and hardware without a Secure Enclave, cannot perform App Attest."*
- Registration accepts *"one or more bundle IDs (up to 32)"*, so registering a keyboard extension's bundle ID is **mechanically possible**. Whether `DCAppAttestService` will attest from an extension process is untested and undocumented.
- *"Requests go directly from your app to the Claude API"* -> **network required** -> **Full Access required in a keyboard extension.** Same wall as PCC.

**Assessment:** App Attest is precisely the mechanism PRD §7 wanted and could not name — no shipped secret, no proxy, no per-device quota to build, usage billed to your workspace. It is the correct answer to "a shipped app cannot hold a shared secret." But it is (i) beta, (ii) **OS 27-only, which per §1 cannot ship to the App Store today**, (iii) network-dependent and therefore Full-Access-gated in a keyboard, and (iv) silent on extension support. **V2 infrastructure, not V1.**

### 4d. The `LanguageModel` protocol collapses the escalation ladder

iOS 27 introduces a **public `LanguageModel` protocol**: *"Adopt the `LanguageModel` protocol to use any large language model — server or on-device — with the Foundation Models framework."* WWDC26 session 241: *"The abstraction layer is built around a new `LanguageModel` protocol that allows both local and server models to back a `LanguageModelSession`. Existing models like `SystemLanguageModel` and `PrivateCloudComputeLanguageModel` already conform."* Apple open-sourced `CoreAILanguageModel` and `MLXLanguageModel`; Anthropic and Google ship conforming packages.

This does not contradict "iOS 27 exposes no new keyboard API" — it is not a keyboard API. But the escalation ladder collapses into **one API surface with the `model:` argument swapped**. PRD §5's "isolate the framework behind an abstraction layer" gets partly written by Apple. An argument for **designing toward that seam now and taking it at ~27.1**, not for adopting the 27 SDK today.

**One recurring cost nobody has costed:** Apple, verbatim, June 2026 — *"Because the model changes when a person updates to iOS 27 … test your prompts with the new model to verify your app's behavior."* They said the identical thing for iOS 26.4 in February 2026. **The prompt contract must be re-validated on every OS point release, indefinitely.** A permanent maintenance line item, not a one-off.

---

## Summary of status changes

| Item | Was | Now |
|---|---|---|
| iOS 26 SDK floor, effective 2026-04-28, no iOS 27 deadline | LIKELY | **CONFIRMED** — and stronger: the App Store accepts *nothing* built with the 27.0 SDK today |
| "Defer the iOS 27 SDK until ~27.1" | recommendation | **Confirmed correct; it is the default path, not a deferral** |
| Xcode 27: Swift 6.4, macOS 26.4+, Apple-silicon-only, deploys iOS 15-27 | unstated | **CONFIRMED** (Intel-only Macs are a hardware blocker for Xcode 27) |
| Host-app bundle ID `nil` (26.4 regression) | 4-month vendor bug | **CONFIRMED permanent through iOS 27**; vendor deprecated the API |
| Silent jetsam with no crash log | permanent platform gap | **iOS 27 fixes the diagnostic** via MetricKit `MemoryExceptionDiagnostic` for app extensions |
| "Memory impact is very minimal" (DTS, iOS 26) | CONFIRMED for iOS 26 | **At risk in iOS 27** — ANE memory now attributed to the process. Moot on a non-Apple-Intelligence device |
| "Is a keyboard extension background?" | UNVERIFIED | **Still UNVERIFIED.** No WWDC26, no docs, no forum update |
| PCC from a keyboard extension | not considered | Network required -> **Full-Access-gated**; managed entitlement is a **request with lead time**; extension support UNVERIFIED |
| Anthropic App Attest for extensions | unknown | **Documentation is silent** — says "app target", never mentions extensions. OS 27 beta-gated, unshippable today |
| Liquid Glass margins, launch flicker, `documentContextBeforeInput`, `hasFullAccess` | open problems | **All unchanged in iOS 27 betas 1-6** (explicit negatives) |

**Two new Phase-0 action items, both cheap:** add `UIApplicationSceneManifest` and a launch-screen key to the containing app's Info.plist now (F3, F4), and never write `connectedScenes.first` (F2).
