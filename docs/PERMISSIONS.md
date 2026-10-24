# Permissions Ledger — Stage 2 Reconciliation

**Status:** Mandatory privacy and authorization contract

**Target:** macOS 26 and later

**Canonical distribution:** Stage 24 zero-cost GitHub Release; local ad-hoc signature, no Apple-trusted identity. See [RELEASING.md](RELEASING.md).

**Last reviewed:** 2026-10-23 (optional onboarding)

**Current-source contract:** A genuinely new profile sees the dedicated first-launch wizard before the shell and feature observation start. Every permission, folder selection, app choice, and review acknowledgment is optional. Finish Setup atomically saves completion even when no access is granted or reviewed. Missing and denied access retain their actual status and can be enabled later in Settings → Permissions. Clipboard monitoring stays stopped during setup and defaults off unless explicitly enabled. Calendar no longer requests authorization from its startup model. Supported requests follow individual user actions; screenshot-folder access uses a native folder chooser. Core Audio process-tap authorization, future file selections, shortcut-specific permissions, and per-item Keychain access cannot be granted universally in advance. No acknowledgment or completion action is an OS grant.

`OnboardingModel` owns the setup state; `OnboardingStore` atomically persists `Notchium/Onboarding.json` in Application Support. Existing configuration is recognized separately as `legacyRecognized`, preserving all preferences and data and providing Settings → Permissions instead of forcing a welcome loop. Completed setup is never invalidated by build changes or permission revocation. `NativeOnboardingPermissions` refreshes real statuses; it never queries personal events, creates reminders, starts camera/audio capture, reads the pasteboard, or opens Keychain items. The older ledger includes future/removed features and is historical where it conflicts with this contract. See [Stage 27B onboarding and persistence](STAGE27B_ONBOARDING_PERSISTENCE.md) for the actual inventory and validation limits.

## 1. Permission principles

- First launch presents setup before normal use. Supported upfront permission requests follow explicit, sequential user actions in the wizard.
- Native requests are never simultaneous. Already-granted and denied choices are rechecked without repeatedly requesting the same one-shot prompt.
- Education appears immediately before the system/provider prompt and accurately states the data, purpose, retention, visible indicator, and fallback.
- System wording and state remain authoritative. The app never draws a fake system prompt or claims that denial can be overridden.
- Clipboard History has a separate affirmative opt-in. Completing setup does not infer monitoring consent. OS pasteboard privacy remains independent.
- Denial, restriction, revocation, unavailable hardware/account, and cancellation are normal states. The rest of the app remains functional.
- Only requirements of implemented features are requested. There is no Full Disk Access, microphone, Contacts, Bluetooth, Input Monitoring, or Network Extension request in setup. Accessibility is used only for the implemented optional volume-key replacement.
- Direct and Mac App Store profiles share the same in-app privacy promises. App Sandbox adds entitlements; it does not relax consent or retention.
- Revocation stops protected work immediately, releases resources, clears sensitive in-memory buffers, and changes the feature state before offering a retry.

Permission behavior uses the shared `PermissionState` vocabulary from [ENGINEERING_RULES.md](ENGINEERING_RULES.md): not determined, authorized, denied, restricted, revoked, and unavailable. Provider/account cancellation is distinct from TCC denial.

## 2. Permission and capability ledger

| Permission / capability | Exact feature trigger | Usage-description key and entitlement/capability | Authorization class | Developer ID direct behavior | Sandbox / Mac App Store behavior | What remains after denial | Settings path and retry | Revocation handling | Required test cases |
|---|---|---|---|---|---|---|---|---|---|
| Calendar full access | Stage 5 app startup, after the Calendar feature is enabled in the build | `NSCalendarsFullAccessUsageDescription`; call `EKEventStore.requestFullAccessToEvents`; Store sandbox: `com.apple.security.personal-information.calendars` | TCC protected personal information | Purpose string and TCC approval required | Same TCC flow plus calendar sandbox entitlement | Shell, manual Open Calendar, manually supplied meeting URL, and all unrelated features | System Settings → Privacy & Security → Calendars; recheck on app activation and retry only from an explicit Try Again action | Cancel queries/streams, remove cached event details, redact activity, show revoked state | Not determined allow/deny; denied relaunch; Settings allow; revoke while event visible; restricted/unavailable account; recurring/time-zone changes; ensure one clean prompt at first launch |
| Camera | User opens Camera Mirror for the first time | `NSCameraUsageDescription`; Store sandbox: `com.apple.security.device.camera`; request/check through AVFoundation | TCC media capture | TCC prompt; normal system camera indicator remains visible | Same plus camera entitlement | Camera-unavailable card, Open Camera Settings, and every non-camera feature | System Settings → Privacy & Security → Camera; explicit retry after return to app | Stop `AVCaptureSession`, release preview/frame references, update state immediately | Allow/deny; no camera; camera busy; disconnect; revoke during preview; Continuity Camera; assert no microphone prompt and no frame persistence |
| System Audio Recording | Spotify playback starts the real waveform, or the user explicitly retries it after denial | `NSAudioCaptureUsageDescription`; Spotify-scoped Core Audio process tap; no microphone key/entitlement because microphone input is not used | TCC system-audio capture | First tap prompts through macOS | Same privacy flow; signing/sandbox and review acceptance must be validated before Store-profile inclusion | Media metadata, artwork, progress, controls, and static waveform fallback | System Settings → Privacy & Security → Screen & System Audio Recording; stop before guiding to Settings; retry with Enable System Audio Waveform | Stop IOProc, destroy aggregate device and process tap, release in-memory PCM, and restore static bars | Allow/deny; revoke while active; Spotify absent/quit/relaunch; tap timeout/failure; sleep/wake; no disk writes; no mic prompt; unrelated-app audio isolation; Store-profile capability gate |
| Notifications | User enables focus completion or meeting reminders and schedules the first alert | No usage-description key or special local-notification entitlement; request through `UNUserNotificationCenter` | UserNotifications authorization | Standard user authorization | Same | In-app notch/menu-bar completion state and countdown remain functional | System Settings → Notifications → Notchium; explicit Enable Notifications retry, then re-read settings | Cancel or avoid pending notifications as feature settings require; preserve timer/event state | Provisional/platform states if exposed; allow/deny; alerts off but authorization present; revoke while timer runs; notification delivered; app foreground; no launch prompt |
| User-selected shelf files and destinations | User drops, pastes, imports, exports, or chooses a destination | No usage-description key for user-selected panel/drop access; Store sandbox `com.apple.security.files.user-selected.read-write`; security-scoped bookmarks for persistent access | User-mediated file access / sandbox extension | Direct profile can access user-provided URLs under normal filesystem permissions; still stores bookmarks only when needed | Sandbox extension and entitlement required; start/stop security scope around work | Shelf still accepts accessible items and can export through a new picker; inaccessible item fails individually | No global Settings path for a stale bookmark; ask user to reselect the item/folder through `NSOpenPanel`/`NSSavePanel` | Stop access, invalidate stale bookmark metadata, preserve managed copies, never modify source | Drop/import allow and cancel; read-only source; stale bookmark; destination revoked; disconnected volume; collision; package/file promise; symlink; insufficient disk; verify original unchanged |
| Recent screenshot folder | User separately enables Recent Screenshots and selects the current screenshot destination | Prefer user-selected folder plus security-scoped bookmark and Store user-selected read-only access; if protected Desktop access is attempted outside a picker, `NSDesktopFolderUsageDescription` may apply, so V1 avoids that broad path | User-mediated/protected-folder access | Explicit folder selection; no Screen Recording permission merely to observe saved files | User-selected sandbox access; do not request broad Desktop access by default | Manual drag/import and shelf core | Reselect Folder action; Files & Folders may show relevant protected-folder access under System Settings → Privacy & Security | Stop watcher, release security scope, discard unresolved candidate metadata, keep already-managed copies | Select/cancel; custom screenshot folder; revoke/stale bookmark; filename/type variants; partial/temp writes; third-party screenshot tool; prove no Screen Recording prompt |
| Downloads-folder observation | User separately enables Recent Downloads and selects/authorizes a folder | `NSDownloadsFolderUsageDescription` for protected Downloads access where required; Store sandbox `com.apple.security.files.downloads.read-only` or narrower user-selected read-only bookmark | Protected folder / sandbox file access | TCC/protected-folder behavior applies when accessing Downloads; prefer an explicit folder choice | Downloads read-only entitlement must never become source mutation authority; broad observation is subject to review | Manual Open Downloads and drag/import | System Settings → Privacy & Security → Files & Folders when listed; otherwise Reselect Folder; retry explicitly | Stop watcher, release scope, clear pending inferences, preserve managed shelf copies | Allow/deny/cancel; user-selected alternate folder; revoke; temporary extension transitions; sparse/long-running downloads; browser atomic rename; duplicate/coalesced events; verify “best effort” wording |
| Optional direct screen capture for OCR | User explicitly chooses Capture for OCR; importing an existing image does not trigger this permission | `NSScreenCaptureUsageDescription`; ScreenCaptureKit and preferably `SCContentSharingPicker`; do **not** request `com.apple.developer.persistent-content-capture` (restricted to approved VNC use) | TCC Screen & System Audio Recording | System content picker/TCC flow; one user-selected source; no persistent/background capture | Same TCC requirements; persistent capture entitlement is out of scope | OCR on shelf, clipboard-history, or user-selected image remains available | System Settings → Privacy & Security → Screen & System Audio Recording; explicit Capture Again after authorization | Stop stream immediately, release frames and OCR input, discard transient result unless user explicitly saved it | Allow/deny/cancel picker; revoke mid-capture; protected window; display disconnect; imported-image path without prompt; no audio capture; no persistence; system picker selection |
| Safari extension host access and native messaging | User chooses Enable Safari Domain Tracking and installs/enables the packaged extension, then grants minimum website access | Safari Web Extension target/capability; manifest least `host_permissions`; `nativeMessaging` only for app bridge; App Group only where the approved bridge/shared container requires it | Extension install/enable, website host permission, native messaging capability | Signed extension is bundled with the app; app accepts only its authenticated extension messages | Safari extension review and sandbox/App Group configuration required; Store profile may include only after packaging validation | Focus timer and application-level Safari duration; no domains | Safari → Settings → Extensions, then the extension's Websites access controls; in app, Recheck Extension | Stop domain intervals, close native channel, discard unaggregated events; never downgrade to URL scraping | Not installed; disabled; no site permission; one-site/all-sites modes; profile changes; private window rejected; native channel mismatch; malformed/full URL payload rejected; revoke mid-interval |
| Chrome, Edge, and Arc extension permissions / native messaging | User independently enables domain tracking for a named Chromium browser and installs its extension/native host | WebExtension manifest least host permissions and `nativeMessaging`; browser-specific native-messaging host manifest; no Apple entitlement grants browser permission | Browser extension and native-host authorization/installation | Notarized installer/update design must install only documented browser-specific host manifests with explicit consent | Native-host packaging may not fit the Store profile; omit Chromium domain adapters if a review-compatible documented package is not established | Focus timer and application-level browser duration; no domains | Each browser's Extensions management UI plus its extension site-access controls; in-app Recheck for that browser | Close channel, end/discard unaggregated interval, show adapter revoked; never use AppleScript/Accessibility fallback | Each browser installed/absent; extension disabled; host permission denied/revoked; native manifest missing/version mismatch; profile switch; incognito rejected even if enabled; malformed/full URL rejected |
| Apple Music | User connects Apple Music or invokes its provider for the first time | `NSAppleMusicUsageDescription`; MusicKit app service/capability; request through `MusicAuthorization`; Store sandbox network client as needed | Apple service capability plus account authorization | Signed App ID must have MusicKit service; user/account/subscription state controls access | Same capability and authorization; App Sandbox outgoing network | Spotify, unsupported-player Open App, and non-media features | System Settings → Privacy & Security → Media & Apple Music when listed; Music app account settings may also be relevant; explicit Connect retry | Stop player requests, clear provider cache, remove protected metadata/activity; do not alter the user's Music library | Authorized/denied/restricted/unavailable; no subscription; signed-out account; network loss; revoke; current-entry/queue limitations; no prompt at launch |
| Spotify local control | User chooses Enable Local Control with Spotify running | `NSAppleEventsUsageDescription`; in-process AppleScript / Apple Events to `com.spotify.client`; no OAuth, client ID, callback listener, or Spotify API token | macOS Automation (Spotify) | Automation entitlement for the development/hardened profile; the free ad-hoc Release has no entitlements or hardened runtime, matching the existing distribution script | Automation entitlement and scripting targets `com.spotify.playback` / `com.spotify.library`; App Store profile remains unqualified | All unrelated features and Open Spotify remain available | Open System Settings; Privacy & Security → Automation → Notchium → Spotify; Check Access or reopen Music | Nonprompting permission checks before scripts; denial clears live media/activity and stops fallback reads; never launch Spotify for a read | Not installed/running; first Allow/Deny; repeat denial; revoke and restore; app relaunch; launch/quit; sleep/wake; actual ad-hoc DMG identity across app updates |
| Launch at login | User turns on Launch at Login in Settings | ServiceManagement `SMAppService.mainApp.register()`; no usage-description key or special entitlement | User-controlled service registration / system approval | Public registration; status can become `requiresApproval` | Same, subject to sandbox/signing correctness | App launches manually and all features work | System Settings → General → Login Items & Extensions when approval is required; re-read `SMAppService.status` | Update toggle/status; never repeatedly register or open Settings without user action | Register/unregister; requires approval; denied/disabled in Settings; app update; duplicate call; relaunch; verify off by default |
| Keychain encryption-key storage | Clipboard key creation/read | Security Keychain Services; no Spotify token access | Secure Clipboard storage | Login Keychain for both Debug and free Release; default application ACL | Data Protection access group requirements | Clipboard stays locked on key failure; unrelated features run | Clipboard Try Again, plus authenticated legacy-backend compatibility and create-only original-key promotion | Never erase or replace existing keys on retry; the local Spotify adapter does not access or delete any Keychain items | Exact OSStatus/readback tests and cross-backend ciphertext fixtures; legacy `Notchium.Spotify` / `oauth` is left unused |
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
| Caffeine | Ordinary idle-sleep assertions require no permission. Optional [closed-lid mode](LID_AWAKE.md) requires administrator approval of its SMAppService daemon; denied or unavailable helpers leave it off. |
| Keyboard Lock | The app never presents itself as locked unless the active session tap and effective keyboard mask are confirmed. Secure Input blocks activation and ends an existing lock with specific guidance. Failure means unlocked. |
| Clipboard | Automatic capture stops. Explicit user-initiated save/paste remains, subject to system behavior. Existing encrypted records remain until retention/deletion. |
| Monitoring | Unsupported samples are unavailable/stale, not zero. No permission escalation or shell fallback. |
| Activities | The source activity disappears; the core shell and unrelated activities continue. |
| Focus | Notification denial keeps in-app completion. App/browser tracking denial keeps timer-only sessions. |
| Ambient Edge | Basic visual modes require no prompt. Any denied/revoked source removes only that source's effect; the user theme, notch, menu bar, and unrelated activities continue. Audio denial always downgrades to Static or Off and tears down capture first. |
| Snap Zones | Accessibility denial prevents querying/moving other apps' windows. It does not affect Ambient Edge, the notch shell, or native window controls. |

## 6. Onboarding contract

The five screens are Welcome, Permissions Overview, sequential Permissions, Final Review, and Ready. Every supported request has its own explicit action and visible result. Continue skips a permission, and Review All opens the final review at any point in the sequence. Finish Setup requires no permissions or acknowledgments; it remains unavailable while a request/refresh is in progress or the setup record cannot safely be saved. Review separates verified grants, completed app/file choices, explicit exceptions, and unresolved requirements. Quit & Resume Later preserves the current step without enabling normal use or marking setup complete.

macOS remains the authorization authority. Setup cannot pregrant Core Audio process-tap recording (the prompt belongs to first capture), arbitrary future file selections, per-shortcut actions, or a specific Keychain item's future authorization. Those exceptions are reviewed without doing protected work to force a dialog. The release build has no Focus entitlement or closed-lid helper. Notifications are in-app; no UserNotifications prompt is invented. Existing-user migration does not claim any OS authorization. Settings → Permissions repairs current access without reopening welcome.

## 7. Privacy-safe purpose-string requirements

Localized usage descriptions must:

- Name the exact feature and protected data.
- State whether capture is continuous or only while the feature is active.
- Avoid vague text such as “to improve your experience.”
- Avoid promising unsupported detection or control.
- Match the in-app education and actual retention.

Stage 1 must add exact localized strings and review them against the final behavior. Examples may be drafted then, but signing must fail CI if a protected API is linked/used without its required nonempty localized purpose string.

## 8. Distribution checklist

### Historical Developer ID profile (deferred)

- A future trusted-signing edition would require Developer ID signing, hardened runtime, secure timestamp, and notarization. Stage 24's free edition instead follows [RELEASING.md](RELEASING.md), keeps Focus unavailable, and omits the team-authenticated closed-lid helper.
- TCC, extension, provider, pasteboard, and protected-folder consent still apply; direct distribution is not a privacy bypass.
- No Full Disk Access, root helper, private entitlement, or disabling library validation is authorized by this contract. The opt-in public volume HID tap is the narrowly scoped exception described below; it does not authorize general keyboard suppression.
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


## Stage 11 — Quick Reminder and actions

Quick Reminder requests EventKit Reminders full access only on opening its composer or explicitly enabling it in Settings. `NSRemindersFullAccessUsageDescription` describes this use. Denied/restricted access leaves the draft available and offers explicit System Settings guidance. Existing Calendar access is separate; no calendar permission is requested to create a reminder. Writable lists are read after authorization, and a missing selection falls back to the system default or first writable list.

App/file/folder actions obtain user-selected access through NSOpenPanel and retain bookmarks: read-only security-scoped references in sandboxed builds, ordinary bookmarks for direct distribution, matching Shelf. Every successful scope acquisition is balanced with release through native open completion; stale bookmarks are refreshed. Stage 20 URL actions accept HTTP(S) and validated registered app links, rejecting credentials and file/script/executable schemes. System actions are limited to opening System Settings, Downloads, and Desktop. Shortcuts use Apple’s command-line interface and the shortcut’s own system permissions; Notchium adds no Accessibility or Input Monitoring request. The removed Keyboard Lock event tap and prompt infrastructure no longer run.

## Clipboard Keychain recovery (2026-10-10)

Stage 26 uses the same versioned login-Keychain service/account (`Notchium.Clipboard` / `payload-key.v1`) for new non-Store Debug and Release histories. The sandboxed Store profile retains Data Protection. Existing encrypted indexes may use the other previously shipped backend: it is read only, and its key is accepted only after AES-GCM authentication of the existing index and validation of its image assets. If the canonical non-Store slot is absent, the fully authenticated original key is added there with create-only insertion and exact readback verification. A duplicate containing a different key fails closed. The legacy record is retained; neither record is overwritten or deleted, ciphertext is not re-keyed, and no key is exported to a file. A changed ad-hoc executable can still need file-Keychain authorization even with the same bundle identifier. Clipboard Retry runs off the main thread and preserves original ciphertext and keys on failure. Missing keys, exact Security OSStatus errors, invalid key bytes, malformed ciphertext, and encryption authentication failures have distinct messages. Retry never resets history.

An earlier installed build returned `errSecItemNotFound` (-25300). Stage 26 later verified readable original history in the repaired, normally signed development app; packaged continuity still requires its own acceptance receipt. See [Clipboard Keychain investigation and recovery hardening](CLIPBOARD_KEYCHAIN_RECOVERY.md) for evidence and the remaining release gates.

## Stage 26 — native file presentation

Opening Add Files does not enumerate Downloads or require folder-monitoring permission. Public Progress subscription likewise performs no protected-folder probe; actual completed-file actions remain subject to macOS file access. The picker grants access only to the user's selected files/folders. Shelf stores references/bookmarks and never moves or deletes the original on import or Cancel.

Picker and sharing sessions use the originating mounted Shelf view's window and the existing shell interaction lease. The picker and small ShareKit source window opt into AppKit's auxiliary fullscreen/all-app behavior. This is a native placement request, not a guarantee that every macOS version or third-party sharing service stays in a fullscreen Space. The sharing source has a visible cancel/return control. See [Stage 26 audit](STAGE26_AUDIT.md) for observed native behavior and manual hardware gaps.

## Native volume HUD replacement (2026-10-10)

The direct-distribution **Replace macOS Volume HUD** preference defaults off. Enabling it
first shows education, then explicitly requests Accessibility through
`AXIsProcessTrustedWithOptions`. Launch, preference restoration, and service observation
never request that grant. Active handling requires current Accessibility trust, event-post
preflight, a working HID tap, and readable/writable controls for the selected HAL output.
The Store profile does not construct the control boundary. No paid identity, helper,
private entitlement, Bluetooth permission, or new System Audio Recording request is required.

Only eligible volume/mute system-defined key-down events are accepted. General keyboard
text is neither read nor stored. Owned event copies exist only until their serial operation
or guarded single replay completes. Unrelated keys, releases, unsupported modifiers, and
all brightness keys retain native handling. Revocation is checked before accepting and
before executing each command; activation also rechecks permission without polling.
Failure stops new interception. A pre-write rejection may replay once; uncertain writes
are never replayed because hardware may already have changed. Abrupt revocation or process
death can prevent delivery of previously accepted input. See [System feedback](SYSTEM_FEEDBACK.md).

A changed ad-hoc-signed build may require a new Accessibility grant. Keeping a bundle ID
does not establish TCC continuity. Physical denial/revocation and changed-build permission
behavior remain hardware acceptance checks. Brightness replacement is unavailable, and
Notchium does not suppress the native AirPods banner.

## Stage 26 native watcher responsiveness

The implemented screenshot adapter observes the configured screenshot folder (Desktop by default), which can raise Files & Folders authorization. Folder resolution, initial enumeration and descriptor opening now run away from MainActor under an owned, cancellable setup task. A slow or denied folder check cannot freeze Shelf import, Settings or Clipboard recovery. Public Progress subscriptions do not enumerate Downloads. No Screen Recording permission is needed to observe screenshot files. The earlier table describes intended permission boundaries; no separate onboarding or screenshot-folder picker is claimed implemented by this repair.


## Spotify onboarding hotfix (1.0.1 / build 3)

All integrations are now optional during setup. **Continue Without Spotify** remains
a deliberate review choice recorded in the existing `reviewed` set; it never
changes the OS authorization snapshot or Clipboard preferences. Final Review can
also finish without that choice or any other permission review.
Settings → Permissions can retry Automation or refresh a later grant without
resetting completed onboarding. Normal media controls still require genuine access.

`SpotifySetupAuthorization` owns one native consent operation and one coalesced
nonprompting check. The installed app calls `AEDeterminePermissionToAutomateTarget`
with the live, finished-launching Spotify PID and wildcard events. Consent uses
`askUserIfNeeded: true` off the main thread on a queue separate from AppleScript and
preflight. Existing local AppleScript playback remains unchanged. Launch readiness
is checked for up to five seconds after LaunchServices returns. Status waits are
bounded at three seconds; request UI waits at thirty seconds. A pending OS request
continues after that wait, without cancellation or a second consent call. A later
refresh verifies current OS truth. None of these limits produce a grant.

OSStatus 0 is authorized; −1743 is denied; −1744 remains not determined; −600/−609
mean the Spotify target is unavailable; −1712 and other codes are recoverable errors.
Denied consent routes to Privacy & Security → Automation rather than repeating a
known-denied prompt. Real fresh-account dialog and packaged recovery acceptance
remain unverified; see `SPOTIFY_ONBOARDING_HOTFIX.md`.
