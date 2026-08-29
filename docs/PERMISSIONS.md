# Permissions Ledger — Stage 2 Reconciliation

**Status:** Mandatory privacy and authorization contract

**Target:** macOS 26 and later

**Canonical distribution:** Developer ID, hardened runtime, notarized direct download

**Last reviewed:** 2026-08-28

## 1. Permission principles

- Initial launch triggers no system permission, account authorization, protected-folder, pasteboard, or extension prompt.
- A prompt occurs only after the user enables a feature and first invokes the protected operation.
- Education appears immediately before the system/provider prompt and accurately states the data, purpose, retention, visible indicator, and fallback.
- System wording and state remain authoritative. The app never draws a fake system prompt or claims that denial can be overridden.
- Clipboard History, application tracking, recent screenshots, and download observation are introduced together during onboarding, but each is independently deselectable and remains off unless selected.
- Denial, restriction, revocation, unavailable hardware/account, and cancellation are normal states. The rest of the app remains functional.
- The app requests the narrowest access. It never requests Full Disk Access, Automation/Apple Events, Bluetooth, microphone, Contacts, Reminders, or Network Extension permission for the V1 contract.
- Direct and Mac App Store profiles share the same in-app privacy promises. App Sandbox adds entitlements; it does not relax consent or retention.
- Revocation stops protected work immediately, releases resources, clears sensitive in-memory buffers, and changes the feature state before offering a retry.

Permission behavior uses the shared `PermissionState` vocabulary from [ENGINEERING_RULES.md](ENGINEERING_RULES.md): not determined, authorized, denied, restricted, revoked, and unavailable. Provider/account cancellation is distinct from TCC denial.

## 2. Permission and capability ledger

| Permission / capability | Exact feature trigger | Usage-description key and entitlement/capability | Authorization class | Developer ID direct behavior | Sandbox / Mac App Store behavior | What remains after denial | Settings path and retry | Revocation handling | Required test cases |
|---|---|---|---|---|---|---|---|---|---|
| Calendar full access | User enables Calendar and requests the first upcoming-event read or Join discovery | `NSCalendarsFullAccessUsageDescription`; call `EKEventStore.requestFullAccessToEvents`; Store sandbox: `com.apple.security.personal-information.calendars` | TCC protected personal information | Purpose string and TCC approval required | Same TCC flow plus calendar sandbox entitlement | Shell, manual Open Calendar, manually supplied meeting URL, and all unrelated features | System Settings → Privacy & Security → Calendars; recheck on app activation and retry only from an explicit Try Again action | Cancel queries/streams, remove cached event details, redact activity, show revoked state | Not determined allow/deny; denied relaunch; Settings allow; revoke while event visible; restricted/unavailable account; recurring/time-zone changes; ensure no prompt at launch |
| Camera | User opens Camera Mirror for the first time | `NSCameraUsageDescription`; Store sandbox: `com.apple.security.device.camera`; request/check through AVFoundation | TCC media capture | TCC prompt; normal system camera indicator remains visible | Same plus camera entitlement | Camera-unavailable card, Open Camera Settings, and every non-camera feature | System Settings → Privacy & Security → Camera; explicit retry after return to app | Stop `AVCaptureSession`, release preview/frame references, update state immediately | Allow/deny; no camera; camera busy; disconnect; revoke during preview; Continuity Camera; assert no microphone prompt and no frame persistence |
| System Audio Recording | User explicitly turns on real waveform for an eligible non-Spotify provider | `NSAudioCaptureUsageDescription`; Core Audio process tap; no microphone key/entitlement because microphone input is not used | TCC system-audio capture | First tap prompts through macOS; app also shows a persistent in-app recording indicator | Same privacy flow; signing/sandbox and review acceptance must be validated before Store-profile inclusion | Media metadata, artwork, progress, controls, and non-audio decorative/no waveform fallback | System Settings → Privacy & Security → Screen & System Audio Recording; stop before guiding to Settings; retry only by explicit Start Waveform | Destroy process tap/aggregate device, cancel meter stream, release in-memory buffers, remove indicator only after capture is stopped | Allow/deny; revoke while active; provider changes; tap timeout/failure; sleep/wake; indicator lifecycle; no disk writes; no mic prompt; Spotify hard-disabled; Store-profile capability gate |
| Keyboard suppression trust | User explicitly enables Keyboard Cleaning Lock and reads the failsafe explanation | Public session `CGEventTap`; use `CGPreflightListenEventAccess` / `CGRequestListenEventAccess` and Accessibility trust APIs as required by the shipping event-tap configuration; no usage-description key; never root/HID | TCC Input Monitoring and/or Accessibility trust, depending on macOS classification of the active session tap | Feature enters locked state only after all required trust checks and tap creation succeed | High review risk; compiled out or unavailable unless sandbox and review validation pass | Cleaning instructions/timer without suppression; mouse remains normal | System Settings → Privacy & Security → Input Monitoring and Accessibility; recheck when active. If macOS requires process restart after a trust change, say so instead of looping prompts | Any trust/tap loss immediately disables suppression and reports unlocked; watchdog and three-second Control–Option–Command–Escape remain independent | Not determined; each trust denied; partial trust; tap creation failure; tap disabled by timeout/user input; Secure Input; revoke during lock; mouse pass-through; click unlock; escape chord; crash/termination; Store profile excluded |
| Notifications | User enables focus completion or meeting reminders and schedules the first alert | No usage-description key or special local-notification entitlement; request through `UNUserNotificationCenter` | UserNotifications authorization | Standard user authorization | Same | In-app notch/menu-bar completion state and countdown remain functional | System Settings → Notifications → Notchium; explicit Enable Notifications retry, then re-read settings | Cancel or avoid pending notifications as feature settings require; preserve timer/event state | Provisional/platform states if exposed; allow/deny; alerts off but authorization present; revoke while timer runs; notification delivered; app foreground; no launch prompt |
| User-selected shelf files and destinations | User drops, pastes, imports, exports, or chooses a destination | No usage-description key for user-selected panel/drop access; Store sandbox `com.apple.security.files.user-selected.read-write`; security-scoped bookmarks for persistent access | User-mediated file access / sandbox extension | Direct profile can access user-provided URLs under normal filesystem permissions; still stores bookmarks only when needed | Sandbox extension and entitlement required; start/stop security scope around work | Shelf still accepts accessible items and can export through a new picker; inaccessible item fails individually | No global Settings path for a stale bookmark; ask user to reselect the item/folder through `NSOpenPanel`/`NSSavePanel` | Stop access, invalidate stale bookmark metadata, preserve managed copies, never modify source | Drop/import allow and cancel; read-only source; stale bookmark; destination revoked; disconnected volume; collision; package/file promise; symlink; insufficient disk; verify original unchanged |
| Recent screenshot folder | User separately enables Recent Screenshots and selects the current screenshot destination | Prefer user-selected folder plus security-scoped bookmark and Store user-selected read-only access; if protected Desktop access is attempted outside a picker, `NSDesktopFolderUsageDescription` may apply, so V1 avoids that broad path | User-mediated/protected-folder access | Explicit folder selection; no Screen Recording permission merely to observe saved files | User-selected sandbox access; do not request broad Desktop access by default | Manual drag/import and shelf core | Reselect Folder action; Files & Folders may show relevant protected-folder access under System Settings → Privacy & Security | Stop watcher, release security scope, discard unresolved candidate metadata, keep already-managed copies | Select/cancel; custom screenshot folder; revoke/stale bookmark; filename/type variants; partial/temp writes; third-party screenshot tool; prove no Screen Recording prompt |
| Downloads-folder observation | User separately enables Recent Downloads and selects/authorizes a folder | `NSDownloadsFolderUsageDescription` for protected Downloads access where required; Store sandbox `com.apple.security.files.downloads.read-only` or narrower user-selected read-only bookmark | Protected folder / sandbox file access | TCC/protected-folder behavior applies when accessing Downloads; prefer an explicit folder choice | Downloads read-only entitlement must never become source mutation authority; broad observation is subject to review | Manual Open Downloads and drag/import | System Settings → Privacy & Security → Files & Folders when listed; otherwise Reselect Folder; retry explicitly | Stop watcher, release scope, clear pending inferences, preserve managed shelf copies | Allow/deny/cancel; user-selected alternate folder; revoke; temporary extension transitions; sparse/long-running downloads; browser atomic rename; duplicate/coalesced events; verify “best effort” wording |
| Optional direct screen capture for OCR | User explicitly chooses Capture for OCR; importing an existing image does not trigger this permission | `NSScreenCaptureUsageDescription`; ScreenCaptureKit and preferably `SCContentSharingPicker`; do **not** request `com.apple.developer.persistent-content-capture` (restricted to approved VNC use) | TCC Screen & System Audio Recording | System content picker/TCC flow; one user-selected source; no persistent/background capture | Same TCC requirements; persistent capture entitlement is out of scope | OCR on shelf, clipboard-history, or user-selected image remains available | System Settings → Privacy & Security → Screen & System Audio Recording; explicit Capture Again after authorization | Stop stream immediately, release frames and OCR input, discard transient result unless user explicitly saved it | Allow/deny/cancel picker; revoke mid-capture; protected window; display disconnect; imported-image path without prompt; no audio capture; no persistence; system picker selection |
| Safari extension host access and native messaging | User chooses Enable Safari Domain Tracking and installs/enables the packaged extension, then grants minimum website access | Safari Web Extension target/capability; manifest least `host_permissions`; `nativeMessaging` only for app bridge; App Group only where the approved bridge/shared container requires it | Extension install/enable, website host permission, native messaging capability | Signed extension is bundled with the app; app accepts only its authenticated extension messages | Safari extension review and sandbox/App Group configuration required; Store profile may include only after packaging validation | Focus timer and application-level Safari duration; no domains | Safari → Settings → Extensions, then the extension's Websites access controls; in app, Recheck Extension | Stop domain intervals, close native channel, discard unaggregated events; never downgrade to URL scraping | Not installed; disabled; no site permission; one-site/all-sites modes; profile changes; private window rejected; native channel mismatch; malformed/full URL payload rejected; revoke mid-interval |
| Chrome, Edge, and Arc extension permissions / native messaging | User independently enables domain tracking for a named Chromium browser and installs its extension/native host | WebExtension manifest least host permissions and `nativeMessaging`; browser-specific native-messaging host manifest; no Apple entitlement grants browser permission | Browser extension and native-host authorization/installation | Notarized installer/update design must install only documented browser-specific host manifests with explicit consent | Native-host packaging may not fit the Store profile; omit Chromium domain adapters if a review-compatible documented package is not established | Focus timer and application-level browser duration; no domains | Each browser's Extensions management UI plus its extension site-access controls; in-app Recheck for that browser | Close channel, end/discard unaggregated interval, show adapter revoked; never use AppleScript/Accessibility fallback | Each browser installed/absent; extension disabled; host permission denied/revoked; native manifest missing/version mismatch; profile switch; incognito rejected even if enabled; malformed/full URL rejected |
| Apple Music | User connects Apple Music or invokes its provider for the first time | `NSAppleMusicUsageDescription`; MusicKit app service/capability; request through `MusicAuthorization`; Store sandbox network client as needed | Apple service capability plus account authorization | Signed App ID must have MusicKit service; user/account/subscription state controls access | Same capability and authorization; App Sandbox outgoing network | Spotify, unsupported-player Open App, and non-media features | System Settings → Privacy & Security → Media & Apple Music when listed; Music app account settings may also be relevant; explicit Connect retry | Stop player requests, clear provider cache, remove protected metadata/activity; do not alter the user's Music library | Authorized/denied/restricted/unavailable; no subscription; signed-out account; network loss; revoke; current-entry/queue limitations; no prompt at launch |
| Spotify OAuth and network | User selects Connect Spotify | OAuth Authorization Code with PKCE through system browser; `URLSession`; Store `com.apple.security.network.client`; access/refresh tokens in Keychain; no client secret in app | Provider account authorization plus network capability | HTTPS allowed under hardened runtime; callback must be authenticated with `state` and PKCE verifier | Outgoing-network entitlement; external browser callback must be declared/documented for target; independent Spotify review/policy obligations | Apple Music, Open Spotify, and non-media features | Disconnect in app; Spotify account Manage Apps page for provider revocation; explicit reconnect starts a fresh PKCE transaction | Cancel requests, delete access/refresh tokens and verifier/state, clear provider cache and activity immediately | User cancel; state mismatch; callback replay; expired verifier; token refresh/rotation; 401/403/429; no active/restricted device; Free/Premium differences; provider revocation; Keychain locked/error |
| Launch at login | User turns on Launch at Login in Settings | ServiceManagement `SMAppService.mainApp.register()`; no usage-description key or special entitlement | User-controlled service registration / system approval | Public registration; status can become `requiresApproval` | Same, subject to sandbox/signing correctness | App launches manually and all features work | System Settings → General → Login Items & Extensions when approval is required; re-read `SMAppService.status` | Update toggle/status; never repeatedly register or open Settings without user action | Register/unregister; requires approval; denied/disabled in Settings; app update; duplicate call; relaunch; verify off by default |
| Keychain token/encryption-key storage | First creation of clipboard encryption key or successful Spotify token exchange | Security Keychain Services; no TCC usage-description key; `keychain-access-groups` only if an approved extension/helper must share a credential | Signing capability / secure storage, not a runtime prompt | Default app Keychain access bound to signing identity; handle interaction-not-allowed/locked errors | Same; access groups must match provisioning and least scope; do not share clipboard keys with browser extensions | Feature whose secret cannot be loaded stays locked/disconnected; unrelated features run | No permission retry pane. Retry after unlock/user action; Disconnect or Reset Encrypted Data performs scoped deletion with confirmation | Stop secret-dependent operations; never fall back to plaintext; token deletion disconnects provider; lost clipboard key makes payloads unrecoverable and triggers explicit reset flow | Create/read/update/delete; locked Keychain; signing/access-group mismatch; item duplicate; corruption; token rotation; uninstall/reinstall expectations; verify no secret in logs/backups created by app |
| Clipboard programmatic access | User independently enables automatic Clipboard History and the observer reaches a new candidate | `NSPasteboard` macOS 26 access behavior/detection APIs; no usage-description key identified; app must follow system pasteboard alert/settings behavior | macOS pasteboard privacy decision plus explicit in-app consent | Programmatic reads may prompt or be denied under macOS 26; user-originated paste remains the safe explicit path | Same, with Store review scrutiny for background access and retention | Explicit Save Clipboard/Paste action, pins already stored, shelf, and native macOS clipboard history | Use the pasteboard access pane surfaced by macOS for the app; do not hard-code an unverified settings URL; offer an explicit user-initiated save path | Stop observation/reads, clear pending candidate buffers, retain previously accepted encrypted items until retention/user deletion | Default/ask/always allow/always deny behaviors; user-originated paste exemption; deny/revoke; unknown source; Secure Input; denylisted app; secret patterns; unsupported type; clear-history deletion |
| Frontmost-application tracking consent | User separately enables Application Tracking for Focus | No TCC key or entitlement; `NSWorkspace.didActivateApplicationNotification`; explicit in-app consent and visible active state are still required | Product consent / public workspace observation | Allowed technically; activity logging must meet consent/indicator/privacy contract | Review risk under Guideline 2.5.14; Store profile may omit if review guidance requires | Focus timer, breaks, notifications, and manual categorization remain | In-app Focus Privacy setting; no system pane. User can pause/disable and clear data immediately | End current interval, stop observation, aggregate/discard according to policy, never continue invisibly | Off by default; enable/disable; sleep/wake; fast app switches; terminated apps; unknown bundle ID; app relaunch; 90-day cleanup; verify no window title/document capture |

## 3. Presentation permission decisions

Ambient Edge does not receive a blanket permission. Each input retains the permission contract of its owning feature, and the presentation layer receives only redacted presentation state.

| Ambient Edge behavior | Permission decision | Denial / revocation behavior |
|---|---|---|
| Click-through overlay, custom color/gradient, thickness, intensity, Static/Slow/Ambient decorative modes | No TCC permission or entitlement beyond the app's normal signing/distribution profile | Feature remains available. If the platform cannot create a safe subordinate overlay, Ambient Edge is unavailable and the notch/menu-bar presentation continues. |
| Album-art-derived palette | No new permission. Artwork must already be available through an authorized media provider and its existing account/capability contract | Fall back immediately to the user's static theme; do not request media authorization merely for decoration. |
| Beat Reactive using an already-running authorized meter | No second prompt. It consumes bounded amplitude state from the existing `AudioMeterProvider` only | Stop reactivity immediately when the shared stream ends, is revoked, or changes provider; downgrade to Static or Off. |
| Beat Reactive that would require starting system-audio analysis | Existing System Audio Recording contract: `NSAudioCaptureUsageDescription`, contextual education, explicit user action, TCC authorization, and visible capture indication | Never start automatically. Denial, restriction, revocation, provider-policy disablement, or uncertain attribution leaves all nonreactive modes functional. |
| Snap Zone feedback | No permission for rendering. The separate Snap feature requires Accessibility only when it queries or moves another application's windows | Edge feedback disappears; Ambient Edge must not request, inspect, or retain Accessibility state itself. |
| Important-notification pulse | No permission for an in-app pulse from a typed Notchium event. UserNotifications authorization applies only when Notchium also posts a system notification | In-app activity may continue when Notifications are denied; arbitrary third-party Notification Center content remains inaccessible by design. |
| Full-screen/presentation/screen-sharing suppression | No new permission. Screen Recording and Accessibility must not be requested solely to improve detection | Use public best-effort lifecycle signals, per-application exclusions, conservative suppression, and manual Pause. Never imply exact detection. |
| Multi-display presentation | No permission | An unsupported/disconnected display loses only its overlay; all other surfaces continue. |

Related approved additions follow the same least-authority rule: battery information needs no TCC grant; charge limiting remains unavailable; enhanced HUD context adds no permission beyond its source; per-application audio requires System Audio Recording only when samples are actually captured; App Intents inherit the equivalent in-app action's capability and permission; synchronized lyrics must use a future authorized provider rather than scraping.

## 4. Trigger and retry state machine

Every permission-dependent feature follows this sequence:

1. Evaluate the compiled `DistributionProfile` and feature flag. If excluded, report unavailable without prompting.
2. Probe OS, hardware, provider/account, and entitlement capability. If absent, report unavailable without prompting.
3. Read current permission/account/extension state.
4. If not determined, show feature-specific education after the user's enable/use action. Continue only if the user confirms.
5. Invoke the documented system/provider request exactly once for that user action.
6. Re-read authoritative state; never infer authorization from a callback alone when a status API exists.
7. Start protected work only after authorization and capability checks both pass.
8. On denial/restriction, show what still works and a settings/reconnect path. Do not prompt repeatedly.
9. On revocation, stop first, clear sensitive transient data, then update UI and offer explicit recovery.

“Try Again” rechecks status. It does not call a one-shot TCC request repeatedly after denial. Settings links use documented APIs/URLs only; otherwise the app gives a textual path.

## 5. Permission-denial behavior by feature group

| Feature | Denied or unavailable behavior |
|---|---|
| Media | One provider's denial does not disable another. Unsupported players receive Open App. Waveform denial removes only the waveform. |
| Calendar | Calendar page explains access and offers Open Calendar; manual URL opening remains possible. |
| Shelf | Managed shelf remains usable when screenshot/download watchers are denied; manual drag/import remains primary. |
| Camera | Preview is absent; no blank/black fake feed and no microphone request. |
| Audio | Missing hardware properties hide or disable only those controls; Sound Settings remains available. |
| Caffeine | No permission is expected; assertion failure produces an honest unavailable state. |
| Keyboard Lock | The app never presents itself as locked unless the active session tap is confirmed. Failure means immediately unlocked. |
| Clipboard | Automatic capture stops. Explicit user-initiated save/paste remains, subject to system behavior. Existing encrypted records remain until retention/deletion. |
| Monitoring | Unsupported samples are unavailable/stale, not zero. No permission escalation or shell fallback. |
| Activities | The source activity disappears; the core shell and unrelated activities continue. |
| Focus | Notification denial keeps in-app completion. App/browser tracking denial keeps timer-only sessions. |
| Ambient Edge | Basic visual modes require no prompt. Any denied/revoked source removes only that source's effect; the user theme, notch, menu bar, and unrelated activities continue. Audio denial always downgrades to Static or Off and tears down capture first. |
| Snap Zones | Accessibility denial prevents querying/moving other apps' windows. It does not affect Ambient Edge, the notch shell, or native window controls. |

## 6. Onboarding contract

The initial explanation may show the value and privacy posture of all features, but it must not invoke protected APIs merely to determine whether a prompt would appear.

The optional-observation screen contains four independent controls:

- Clipboard History
- Application Tracking
- Recent Screenshots
- Recent Downloads

Each defaults to off unless the user affirmatively selects it. Selecting an option records intent; the relevant system prompt or folder/extension chooser waits until the user first enters or starts that feature. “Enable all” may select all four but may not collapse their disclosures or requests into one consent.

System Audio Recording, Camera, Calendar, direct Screen Capture, Notifications, Keyboard Lock trust, Apple Music, Spotify, Safari extension access, and each Chromium browser adapter are introduced and requested separately at point of use.

Enabling Ambient Edge itself never triggers a system prompt. Selecting Beat Reactive may lead to the existing System Audio Recording education only when the user deliberately starts that mode and no authorized shared meter is active. A mode preview uses synthetic fixture data until authorization succeeds. Ambient Edge never prompts for Screen Recording or Accessibility to improve suppression.

## 7. Privacy-safe purpose-string requirements

Localized usage descriptions must:

- Name the exact feature and protected data.
- State whether capture is continuous or only while the feature is active.
- Avoid vague text such as “to improve your experience.”
- Avoid promising unsupported detection or control.
- Match the in-app education and actual retention.

Stage 1 must add exact localized strings and review them against the final behavior. Examples may be drafted then, but signing must fail CI if a protected API is linked/used without its required nonempty localized purpose string.

## 8. Distribution checklist

### Direct profile

- Developer ID application signing, hardened runtime, secure timestamp, and notarization are mandatory.
- TCC, extension, provider, pasteboard, and protected-folder consent still apply; direct distribution is not a privacy bypass.
- No Full Disk Access, root helper, HID event tap, private entitlement, or disabling library validation is authorized by this contract.
- OAuth callbacks, browser native-host manifests, launch-at-login registration, and Keychain continuity must be tested across updates.

### Store-compatible profile

- App Sandbox is mandatory.
- Entitlements are least-privilege and feature-specific: outgoing network, calendar, camera, user-selected files, and Downloads read-only only when the compiled feature needs them.
- Keyboard suppression and Chromium native messaging are excluded unless a documented sandbox-compatible package passes review validation.
- No private API, Automation entitlement, Network Extension, persistent content capture, broad all-files access, or temporary exception entitlement is allowed.
- Store metadata must describe reduced capabilities accurately and must not show deferred controls.

## 9. Unresolved technical risks

- Spotify policy clearance for audio-derived waveform visualization and commercial product use.
- Apple Music system-player queue visibility and behavior changes across MusicKit releases.
- Core Audio process-tap permission UX, power cost, provider targeting, and review acceptance.
- Reliability and distribution review risk of keyboard suppression despite using public APIs.
- Clipboard source attribution and secret detection cannot be guaranteed by public APIs.
- Hardware-dependent screen brightness and output-volume support.
- Browser-extension packaging, review, installation, and native-messaging maintenance across four browsers.
- Folder-watcher inference cannot provide universal screenshot/download completion semantics.
- Window placement and activation behavior across Spaces, full-screen applications, display changes, sleep/wake, and menu-bar configurations.
- Mac App Store viability of the reduced capability profile, particularly keyboard suppression and broad observation features.
- Audio-reactive Ambient Edge may be disproportionate to appearance-only value under TCC and App Review expectations.
- Public APIs do not guarantee exact full-screen-video, presentation, game, or third-party screen-sharing detection, so suppression must remain best effort and user-controllable.
