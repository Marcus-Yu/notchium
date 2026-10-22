# Security, privacy and distribution impact

Research date: 2026-10-21. This document describes proposed controls and qualification gates, not grants observed on this Mac. Source facts are in [01](01-current-architecture.md). The developer explicitly retained **zero-cost distribution** and approved **user-invoked, advisory BYOK AI first**.

## Four distinct authorities

Keep these independent: (1) macOS permission to acquire data, (2) app-level consent to use a selected source, (3) consent to send particular content to a named provider, and (4) authority to change a particular destination. Accessibility approval does not authorize cloud upload. Calendar full access does not authorize an AI calendar edit. Text in an email, webpage or tool output cannot grant any of these authorities.

The initial assistant uses manually supplied text and no action tools, so it needs no additional cross-app capture grants. BYOK credentials are a new sensitive asset; session-only conversations still leave the device when explicitly sent to the provider. “Local processing before upload” is not “all data stays local.”

## Capability/permission ledger

| Capability | Authorization / adapter | Trigger and denial behavior | Distribution impact |
|---|---|---|---|
| Explicit-text AI | Provider key/account plus app egress consent | User submits supplied text; offline/invalid-key/quota states keep existing utility features available | No special AI entitlement in current nonsandboxed profile; outbound HTTPS and credential handling still need tests |
| Conventional global hotkey | Registered OS hotkey adapter, conflict handling | User configures/enables; collision leaves menu entry available | No blanket Input Monitoring requirement inferred; qualify chosen API in actual ad-hoc artifact |
| Modifier double-press | Optional future event observation and timing state machine | Explicit experiment only; disabled on missing required event access/Secure Input | May add event-listening/Accessibility constraints; no general key logging |
| App/window metadata | NSWorkspace/qualified window metadata adapter | Only enough observation to bind/invalidate a requested context | Do not accumulate browsing/activity history |
| AX text/actions | `AXIsProcessTrusted[WithOptions]`, bounded `AXUIElement` access | Optional capability; check live trust and supported attributes; deny → manual text/Copy | Existing volume-key trust is not app-content consent; ad-hoc update identity needs validation |
| Screen/window image | ScreenCaptureKit filter/picker, direct Screen Recording status/request where applicable | User chooses scope; deny/revoke → manual text/file; stop and release frame buffers | Separate from audio taps and saved screenshot-folder access; current runtime coverage unverified |
| Calendar inventory | EventKit full event access and selected calendars | Existing authorization, new purpose-specific local-analysis/egress consent | Existing purpose string covers upcoming-event display, not silently sending all calendar data to models |
| Reminders inventory/write | EventKit full reminders access, narrow read/write adapters | Current adapter creates only; new read/completion behaviors need explanation and explicit scope | `NSRemindersFullAccessUsageDescription` currently describes Quick Reminder creation and must be revised when broader behavior ships |
| Google accounts | Per-API OAuth scopes, system browser/native redirect/PKCE | User connects account/feature; revoked/expired token never causes silent fallback to another account | Public verification and restricted-scope assessment may conflict with cost constraint |
| Browser page/editor | Extension permissions plus native bridge identity | Extension invocation or separately approved host grant; no private/incognito collection by default | Safari/Chromium/Firefox packaging and bridge distribution are different; current verifier rejects bundled `.appex` and unexpected Mach-O inventory, not all browser extension formats |
| Selected files/PDFs | NSOpenPanel/drop/bookmark access; bounded security-scope lifetime | User chooses files; stale/missing grant → reselect | No Full Disk Access; sandbox access is more constrained than current direct profile |
| Apple Events automation | Target-specific Automation TCC; entitlement where required by runtime/sandbox | Explicit supported target action, no OS grant manipulation | Spotify grant/purpose is not a generic app-control grant; future targets need proper purpose/entitlement review |
| In-app briefing cards | Existing Activity/NotificationCoordinator | App runs and source available; respect interruption policy | No UserNotifications permission currently required; cannot read other apps' Notification Center content |
| Optional OS notifications | Future `UNUserNotificationCenter` feature, if justified | Separate user-enabled permission; in-app fallback | Do not infer current support from historical ledger rows |
| Login/background | Optional `SMAppService.mainApp` path, live service status | User enables launch at login; registration/approval failure has manual launch fallback | No existing main-app implementation; not equivalent to the privileged LidAwake daemon |
| Overnight wake | No recommended privileged capability | Catch up on return; never modify machine power settings silently | Existing free release excludes closed-lid helper; no wake-time guarantee |

System framework declarations were checked through official docs/Context7 and installed macOS27 SDK headers for compatibility with the macOS26 minimum. Many Apple web API pages expose only JavaScript to the retrieval tool; declarations were verified from SDK headers where needed. None of this substitutes for packaged TCC behavior. References: [Apple AX](https://developer.apple.com/documentation/applicationservices/axuielement_h), [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).

## Integrate with existing setup; keep AI optional

The working setup system is `NotchiumPackage/Sources/NotchiumCore/OnboardingState.swift`, `NotchiumFeature/OnboardingModel.swift` and `OnboardingView.swift`, `NotchiumServices/OnboardingPermissions.swift` (`NativeOnboardingPermissions`), and `NotchiumPersistence/OnboardingStore.swift`. It persists reviewed choices/completion, not TCC grants. `OnboardingModel.canFinish` currently requires satisfaction of `SetupPermission.allCases`; existing available denials can block the base setup. The generic `RealPermissionAuthorizer` is a nonprompting scaffold.

Therefore **do not simply add AI/capture cases to the mandatory enumeration**. Proposed change in its implementation stage:

1. Preserve the base setup completion record and current mandatory requirements. Add a separate optional-capability section within the same setup/settings flow, with explicit “Not now”/disabled status and no AI activation as a side effect.
2. Define base-required versus optional-enabled requirements explicitly. Optional AI, AX/capture, connectors, document indexing and scheduled processing cannot participate in the existing mandatory `canFinish` test merely because they exist.
3. Introduce provider/egress disclosure before API-key connection or first Send. First-release text AI requests no AX/Screen Recording grants. Later capture options explain exact scope/purpose/provider/retention before an explicit request.
4. Add versioned optional-consent state carefully: `OnboardingModel` currently treats schema versions greater than 1 as read-only. Coordinate decoder/model/store migration without clearing `completion`, losing user choices or triggering a first-launch loop. Preserve future-version/corrupt records for recovery.
5. Query OS truth without prompting on startup/settings activation; prompt only when a user enables a capability and the OS state permits requesting. Already granted/denied statuses are not reasons for repeated requests. Denial remains denial; a Skip acknowledgment is not a grant.
6. Revalidate before capture/use, respond to revocation, stop active work and clear buffers. Optional capability failure leaves the base app and manual text assistant usable. Revocation does not reset onboarding completion.

Reusing the same visual components and status vocabulary avoids a disconnected AI wizard; separate authority/persistence avoids making optional permissions mandatory. Do not broaden or remove base onboarding requirements incidentally during AI work.

## Credential and local data protection

Create separate Keychain service/account namespaces for provider keys, Google refresh tokens and any future managed-session credential. Prefer short-lived access tokens in memory and non-synchronizing secret storage. Mask keys in UI; never put secrets in UserDefaults, prompt content, crash attachments, environment dumps, URL query strings or source fixtures. Never bundle a shared vendor production key in the app.

Clipboard provides an existing example of authenticated encrypted storage and fail-closed recovery in `NotchiumClipboardFeature/ClipboardEncryption.swift` and `ClipboardKeychainAccess.swift`. Reuse its invariants, not its payload key or private feature implementation. Non-Store builds currently use login Keychain; Store behavior uses a separate backend. A locked Keychain, canceled authorization, missing entitlement and missing item are different outcomes. Do not create a new key over unreadable encrypted task/artifact data.

Ad-hoc updates change executable identity and can produce per-item Keychain reauthorization; a bundle identifier is not a trusted signing identity. Preserve the OS ACL/security requirements rather than “trust all apps,” disable authentication or delete/recreate secrets to suppress prompts. The stated goal is no unnecessary app prompts; OS identity transitions cannot be promised away. Test upgrade/relaunch with populated encrypted data and the exact artifact identity.

Default chat/context is memory-only; explicit saved artifacts and later TaskStore are encrypted with independent keys/schemas. Store minimum source evidence, source revisions, task state and suppression receipts. Raw screen images are not an ambient archive. Keep indexed text/embeddings encrypted or use an explicitly reviewed encrypted-payload approach; ordinary FTS databases otherwise leak plaintext. Short-lived files need private permissions, path containment and symlink-safe access. No private content belongs in general diagnostic logs.

## Provider data transmission and retention

Show destination/provider, content scope and purpose before egress. API calls must use fixed allowlisted HTTPS hosts, bounded sizes, redacted error categories and credential-safe redirect behavior. Do not fetch remote images/URLs returned by the model automatically; a displayed link is not approval to send data to its host. Changing provider or adding context requires renewed applicable disclosure/consent rather than an invisible fallback.

OpenAI documents API data controls, default abuse-monitoring retention, endpoint-specific application state and eligibility limits. Use `store: false` for the initial Responses path and keep conversation state locally, but **do not describe that flag as zero data retention**. Background mode, files, caches and hosted tools have separate retention behavior; avoid them in the first release. [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data).

Anthropic's normal commercial API retention and special ZDR arrangements differ, and designated Covered Models have additional retention requirements. Do not promise a single universal “no training/no retention” statement across consumer products, API features/models and customer agreements. The selected provider/model/account terms must be checked before release and reflected in disclosure. [Anthropic API retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention), [commercial retention policy](https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data), [Covered Models](https://privacy.claude.com/en/articles/15425996-data-retention-practices-for-covered-models).

A consumer ChatGPT/Claude login is not authorization for unlimited third-party API requests. Anthropic currently offers claimable capped Console API credits to some Max/Team plans; users still need legitimate developer API credentials/quota and applicable terms. No consumer-cookie/token reuse. [Subscriber API credits](https://platform.claude.com/docs/en/about-claude/api-credits-for-subscribers).

## Gmail and extension release gates

`gmail.readonly` and `gmail.compose` are restricted; compose is send-capable, so application tool policy must forbid sending even where the OAuth credential permits it. A public app needs the applicable verification process. Google states that server storage/transmission of restricted data triggers a security-assessment requirement; direct BYOK client-to-model transmission must be evaluated, not presumed exempt. Confirm exact current project applicability and cost with Google before committing to launch. [Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes).

Workspace Limited Use governs appropriate use, consented transfers, retention and model-training restrictions. A user checkbox alone does not override provider policies. Include the AI processor, derived tasks, deletion and incident procedures in the data-flow review; do not transmit data under an ineligible arrangement. Chrome/Firefox extension extraction is not a recommended technique for evading Gmail API requirements: separate browser/service terms and privacy obligations still apply. [Workspace policy](https://developers.google.com/workspace/workspace-api-user-data-developer-policy).

An extension needs narrowly granted page access, verified extension identity/native origin, bounded schema and message sizes, session nonce/expiry and tab/composer/account binding. `activeTab` comes from extension invocation, not any native hotkey. Keep credentials native; no unauthenticated localhost control server, permissive bridge origin or `eval` channel. DOM text is untrusted. See [Chrome permission behavior](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab) and [native transport](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).

## Prompt injection, actions and sensitive information

The model is an untrusted proposer. A source may ask it to ignore rules, reveal secrets or perform unrelated actions. Separate user instruction from source observations, use evidence IDs, validate schemas/semantics, and restrict tools in executable policy. Prompt wording/redaction classifiers alone are insufficient. Initial read-only AI has no tool execution authority. Later action approvals bind exact normalized destination/content/revision/tool/session and are invalidated by change or expiry.

Require concrete final-step review for sending, sharing, purchases, deletion and other high-impact operations; exclude those from the first execution lane. Authorization to read a PDF is not authorization to upload it elsewhere. Unknown network outcomes require readback/reconciliation before retry. Rollback is tool-specific and often unavailable; do not promise universal undo. Details and failure-injection requirements are in [05](05-computer-use.md).

Offer excluded-app/source controls and exact egress preview; do not claim automatic redaction can find all secrets, health data, student records, corporate content or credentials. Secure/password fields and OS consent/password dialogs are excluded from capture/automation. Do not add generalized “compliance” claims from a model/vendor feature alone.

## Direct distribution, notarization and sandbox alternatives

**Confirmed current profile:** `Config/Release.xcconfig`, `scripts/release.sh` and `scripts/verify-release.py` require arm64, ad-hoc signature, no Hardened Runtime, no runtime entitlements, no bundled `.appex`/launch daemons and one expected Mach-O executable. The verifier does not categorically reject every browser-extension format or executable script; adding any bridge/runtime still requires a deliberate security and packaging review. Release has no paid certificate, notarization or updater. A `.dmg` filename does not imply trusted signing. Manual quarantine/Gatekeeper flow and managed-Mac restrictions remain material limitations.

**Potential Developer ID alternative:** trusted signing/notarization would require the appropriate Apple developer identity/program access, Hardened Runtime, correct entitlements for protected operations, nested-code signing, notary submission/stapling and new artifact/upgrade testing. Apple explicitly requires Hardened Runtime for notarization. That is a separately funded release-policy change, **not included under the user's zero-cost constraint**. Accessibility/Screen Recording/Automation still require user consent after notarization. [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime).

**App Sandbox alternative:** `Config/Notchium-AppStore.entitlements` is a reduced future profile, not an accepted Store product. Network client, selected-file/bookmark, Calendar and automation constraints must be considered feature by feature. An entitlement/TCC grant is not proof that arbitrary cross-app automation will be allowed by sandbox/review. Do not promise feature parity, broad desktop execution or Mac App Store eligibility. Current file permissions do not authorize arbitrary document writes.

Basic HTTPS/text AI can preserve the current distribution shape, subject to real credential/network acceptance. Browser extension bundles/native bridges/embedded runtimes require reviewed changes to the executable/extension/dependency inventory and are conditional. No private APIs, SIP changes, TCC database edits, root power helper or weakened helper signing requirements are recommended. Keep the existing LidAwake exclusions.

## Auditability, retention and deletion

| Data class | Default policy proposal | Delete/revoke behavior |
|---|---|---|
| Raw supplied context/screens | Session-only, screenshots released after request/cancel | Clear session; no guarantee of physical RAM zeroization; provider copies follow provider policy |
| Explicit saved answers/artifacts | Encrypted, user-managed with clear source/time | Delete local artifact and derived index references; exports outside Notchium are independent |
| Source cache/excerpts | Bounded by selected source, necessity and applicable service policy | Purge on disconnect/revoke/forget; invalidate ongoing generations |
| Tasks/feedback | Durable minimum normalized state; explicit retention review, separate suppression semantics | User can delete source/tasks/history; show that resetting suppression may allow future suggestions |
| Credentials | Separate Keychain items, not cloud-synced by default | Revoke provider/OAuth where supported, remove local secret, cancel work; distinguish failed remote revocation |
| Action receipts | Encrypted minimal operation/approval/verification evidence | User retention/delete controls; never resurrect actions from replayable logs |
| Diagnostics | Fixed event classes/counters, no content | Local export preview; redact and allow delete; no remote telemetry dependency initially |

Deletion cannot recall already delivered API content, overwrite exported files elsewhere or promise erasure from backups. If future hosted file/vector resources are introduced, track resource IDs and remote deletion outcomes rather than merely deleting local references. Deletion and Keychain-key removal need deliberate ordering so “disconnect” does not strand unrelated encrypted histories.

## Required qualification and unresolved risks

Use mocks for CI and a real test artifact/account for native permission qualification. Record OS version, architecture, artifact hash, signing/profile, fresh vs returning user, grants/denials and observed behavior. Test macOS26 minimum separately from the current macOS27 development environment. Do not reset the owner's TCC, Keychain or real account data to manufacture test results.

Required cases include optional setup skip, base completion persistence, allowed/denied/restricted/revoked statuses, reactivation without duplicate prompts, Keychain cancel/locked/update recovery, source removal, screenshot consent/scope, AX unsupported/hung target, shutdown cleanup, provider failure/quota and plaintext/secret log scans. Extension/agent qualification adds bridge identity, origin isolation, injection, approval forgery, stale state and partial external outcomes.

Open risks remain: ad-hoc identity persistence across updates; fresh-user Gatekeeper/TCC behavior on macOS26; real browser AX/editor compatibility; Google assessment/transfer requirements and costs; future browser isolation/packaging; measurable extraction accuracy. Any failed gate narrows or defers that capability. It must not lead to weakening OS protections or relabeling an untested feature as supported.
