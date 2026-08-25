# Product Specification — Stage 0

**Status:** Engineering contract

**Target:** macOS 26 and later

**Canonical distribution:** Developer ID, hardened runtime, notarized direct download

**Last reviewed:** 2026-08-24

## 1. Product definition

Notch is a native macOS utility that uses the unobscured menu-bar space around the built-in MacBook display notch as a compact surface for productivity controls and short-lived system context. It is not a replacement for macOS system UI and does not claim ownership of the physical notch.

The product follows three interaction levels:

1. **Collapsed:** passive, glanceable, and visually quiet. Show only the highest-priority state that fits safely beside the physical notch.
2. **Hovered:** reveal a small amount of additional context without taking application focus.
3. **Deliberately opened:** a click or explicit keyboard action opens controls, history, or details. This state may become key when keyboard input is required.

Only the built-in notched display receives the island surface. External displays, clamshell use, and Macs without a physical notch use a persistent menu-bar item as the complete fallback. V1 does not create a synthetic island on external displays.

## 2. Product principles

- Minimal when collapsed, useful when hovered, and powerful only when deliberately opened.
- Local-first. A network connection is used only for a feature whose provider requires it, such as Spotify or MusicKit catalog access.
- No cloud storage or synchronization of clipboard, focus, browsing, shelf, or activity information.
- Apple-native controls, behaviors, accessibility, materials, and animation conventions.
- Documented public APIs by default. Private or undocumented APIs require a separately approved architecture decision record before any use.
- Permission requests are progressive and contextual. No protected-resource prompt appears merely because the app launched.
- Denial is a supported state, not an error loop. Every protected feature has a useful explanation and a safe fallback.
- No unnecessary backend and no behavioral advertising or analytics SDK in V1.
- The app never suppresses, replaces, or hides Apple system privacy indicators or HUDs.
- The app never describes inferred or unsupported data as exact.

## 3. Intended users and core use cases

### Personas

- **Focused individual contributor:** wants media, the next meeting, a timer, and file handoff without opening several windows.
- **Meeting-heavy professional:** wants upcoming-event context and a reliable Join action while retaining control of permissions.
- **Creative or technical user:** wants a temporary file shelf, camera mirror, clipboard recall, and lightweight system totals.
- **Privacy-conscious user:** wants useful automation with local retention, visible capture states, feature-level opt-in, and immediate deletion controls.

### Primary use cases

- Glance at the current supported media item and use provider-supported playback controls.
- See the next calendar event and open its Zoom, Google Meet, or Microsoft Teams link.
- Temporarily collect files, then copy, export, drag, Quick Look, AirDrop, or share them.
- Check camera framing without recording.
- Change the default audio output and adjust volume when the selected device permits it.
- Prevent idle sleep for a chosen duration.
- Suppress ordinary keyboard input while cleaning, with mouse access and a guaranteed fail-open path.
- Search recent non-sensitive clipboard items and explicitly pin useful content.
- View trustworthy system totals and the process details that public APIs can provide.
- Run a Pomodoro/focus session and review neutral, local statistics.

## 4. V1 capability classification

| Feature | V1 status | Product contract |
|---|---|---|
| 1. Media Center | **Reduced V1** | Apple Music through MusicKit and Spotify through the Web API. No generic system-wide Now Playing reader. Provider capabilities determine available controls. |
| 2. Minimal Calendar | **Reduced V1** | Upcoming EventKit events, countdowns, recognized meeting links, and Join. The app’s own notch activity replaces the requested native Mac Live Activity behavior. |
| 3. File Shelf | **Full V1 core; best-effort observation** | Multi-file managed copies, selection, drag/drop, Quick Look, copy/export, and system sharing. Screenshot and download discovery are explicitly best effort. |
| 4. Camera Mirror | **Full V1** | Live AVFoundation preview after Camera consent; no capture, recording, or microphone use by default. |
| 5. AirPods/Audio Manager | **Reduced V1** | Audio-device list, default-output switching, connection inference, and writable volume. AirPods battery and listening modes are unavailable unless Apple later documents a suitable API. |
| 6. Liquid Glass | **Full V1** | macOS 26 system Liquid Glass and standard native controls, with accessibility fallbacks. |
| 7. Caffeine | **Full V1** | Indefinite or timed idle-sleep prevention using a public IOKit power assertion. |
| 8. Keyboard Cleaning Lock | **Experimental, direct distribution** | Session event tap suppresses ordinary keyboard events while mouse input remains available. It is always fail-open and cannot block every hardware/system key. |
| 9. Clipboard History | **Full V1 with privacy gating** | Text, URLs, images, and files; search, pin, favorite, exclusions, and encrypted local payloads. Programmatic pasteboard access follows macOS 26 privacy behavior. |
| 10. System Monitor | **Reduced V1** | System CPU, RAM, and aggregate network totals plus accessible process CPU/RAM. No system-wide GPU utilization or per-process network accounting. |
| 11. Native animations | **Full V1** | Native SwiftUI/AppKit transitions with stable identity and Reduce Motion support. |
| 12. Dynamic Mac Island activities | **Reduced V1** | App-owned, event-driven notch presentations. Apple system HUDs and privacy indicators remain visible. Unsupported sensors are omitted. |
| 13. Customizable notch pages | **Full V1** | Local page order, enablement, and capability-aware composition with a deterministic fallback page. |
| 14. Focus/Pomodoro | **Reduced V1** | Timers, breaks, notifications, app tracking, neutral statistics, and opt-in browser-domain tracking through extensions. |

The feasibility basis and distribution consequences for each row are defined in [FEASIBILITY.md](FEASIBILITY.md). Permission behavior is normative in [PERMISSIONS.md](PERMISSIONS.md).

## 5. Functional requirements and acceptance criteria

### 5.1 Notch shell and application lifecycle

- The shell anchors only to a built-in screen whose public `NSScreen` geometry reports a top obstruction and usable auxiliary top areas.
- The app maintains exactly one notch surface, even with multiple displays attached.
- Disconnecting, sleeping, waking, changing display mode, entering full screen, changing Spaces, or switching Stage Manager state must recalculate placement without leaving an orphan panel.
- The collapsed and hover states do not activate the app or steal focus. A control requiring keyboard input may deliberately become key.
- When no eligible built-in notched screen is available, every feature remains reachable from the menu-bar item.
- The app runs as an accessory-style utility by default. Settings and other deliberate windows may activate normally.
- Launch at login is off by default and may be enabled only through the public Service Management flow.

### 5.2 Media Center

- Apple Music and Spotify are separate provider adapters behind a common capability model.
- Collapsed media may show artwork, title, playback state, and a waveform only when the active provider authorizes each field.
- Apple Music uses `SystemMusicPlayer`; Spotify uses OAuth Authorization Code with PKCE and least-privilege scopes.
- Play/pause, previous, next, seek, shuffle, repeat, queue, and provider volume controls appear only when the active provider reports support.
- Spotify restrictions such as no active device, private session, restricted device, Free account, rate limiting, offline state, and expired authorization produce provider-specific unavailable states.
- Apple Music does not promise enumeration of the Music app’s full Up Next queue. V1 may show the current entry and only queue operations that MusicKit exposes for `SystemMusicPlayer`.
- A real waveform requires separate, explicit System Audio Recording consent and a persistent visible recording indicator while active. Audio samples and derived windows are never written to disk.
- The waveform is disabled for Spotify until written Spotify policy clearance confirms the proposed visualization is permitted.
- Unsupported players receive an Open App action; the app does not fall back to Apple Events, scripting, or private MediaRemote APIs.

### 5.3 Minimal Calendar

- The feature reads upcoming events only after full EventKit calendar authorization.
- The next-event summary includes title according to the user’s privacy setting, start time, countdown, and calendar color when available.
- Meeting-link recognition supports documented URL forms for Zoom, Google Meet, and Microsoft Teams found in `EKEvent.url`, location, or notes.
- Join opens the recognized HTTPS URL with `NSWorkspace`; it does not automate or control the destination client.
- Invalid, ambiguous, or untrusted links require an explicit open action and are never executed as commands.
- Calendar activities are app-owned notch activities plus optional local notifications. A native macOS-originated ActivityKit Live Activity is not promised.
- Calendar denial leaves a concise setup explanation and a manual Open Calendar action.

### 5.4 File Shelf

- Every dropped or imported item is copied into app-managed temporary storage. The source remains unchanged.
- Multiple files, folders, and file promises are supported subject to available disk space and source access.
- Selection supports single, additive, range, and select-all operations appropriate to macOS.
- Export and copy use a user-selected destination or an existing valid security-scoped bookmark.
- A “move out” operation moves the app-managed copy; it never deletes or modifies the original source item.
- AirDrop and other sharing use the system sharing picker. The feature does not assume a particular service is installed or available.
- Quick Look and Reveal in Finder use public system services.
- Default shelf lifetime is 24 hours. Users may choose Until Quit, 1 hour, 24 hours, 7 days, or Manual. Cleanup applies only to managed copies.
- Recent screenshot and download suggestions are enabled only for explicitly authorized folders and are marked best effort.
- Partial copy failures, stale bookmarks, name collisions, disconnected volumes, and insufficient storage preserve already-valid source files and report per-item outcomes.

### 5.5 Camera Mirror

- Opening the mirror requests Camera permission in context if authorization is undetermined.
- The preview uses a selected available camera and reacts to device connection/disconnection.
- No microphone permission is requested and no image, video, or audio is stored by default.
- The system camera-use indicator remains visible.
- Denial or absence of a camera provides Open Camera Settings or a device-unavailable explanation.

### 5.6 AirPods and Audio Manager

- The app enumerates public Core Audio output devices and identifies the current default output.
- Selecting a capable device requests a default-output change and confirms the resulting system state.
- A volume slider appears only when the selected device exposes a writable volume control.
- AirPlay, HDMI, aggregate, virtual, and externally controlled devices may expose read-only or no volume.
- AirPods connection is inferred only from public audio-route presence; it is not presented as Bluetooth pairing truth.
- V1 omits AirPods battery percentages and Noise Cancellation, Transparency, Adaptive, and Off controls because no suitable documented public macOS API has been verified.
- Unsupported device controls fall back to opening Sound or Bluetooth Settings.

### 5.7 Liquid Glass and native animation

- Standard SwiftUI/AppKit controls and system-provided glass take precedence over custom blur or material replicas.
- Related custom glass elements share a glass container and stable transition identity.
- Collapsed, hover, expanded, page, and activity transitions preserve semantic continuity instead of rebuilding unrelated views.
- Reduce Motion replaces spatial morphs with short opacity/content transitions and removes nonessential waveform motion.
- Reduce Transparency replaces custom glass with an opaque or system material surface that maintains contrast.
- Animation never delays an emergency unlock, permission explanation, or primary action.

### 5.8 Caffeine

- The primary toggle starts or releases an idle-system-sleep assertion.
- Secondary actions offer 15 minutes, 30 minutes, 1 hour, 2 hours, until a chosen clock time, and indefinite.
- The same duration choices are available from the feature's right-click/context menu without requiring the expanded view.
- Hover reveals the remaining duration for timed assertions.
- Assertions are released when the user disables the feature and when the process exits.
- The UI states that power assertions are advisory and may not override low-power or thermal protection.

### 5.9 Keyboard Cleaning Lock

- Enabling requires a successful public session-level active event tap and the required system trust.
- Mouse and trackpad movement and clicks remain usable.
- Clicking the notch or menu-bar lock indicator unlocks immediately.
- Holding Control–Option–Command–Escape for three continuous seconds unlocks. The escape chord itself is recognized but not forwarded while locked.
- Event-tap disablement, timeout, loss of trust, callback failure, app termination, or internal watchdog failure releases the lock immediately.
- The feature never uses a root/HID event tap and never claims to suppress power, Touch ID, Secure Input, firmware, or all reserved system keys.
- If trust is denied or the event tap cannot be established, the app does not enter a visually locked state.

### 5.10 Clipboard History

- The user explicitly enables automatic history and consents to macOS 26 programmatic pasteboard access behavior.
- V1 supports text, web URLs, images, and file references. Unsupported or unreadable representations are skipped.
- Capture is fail-closed when source attribution is unavailable, Secure Event Input is active, the source app is denylisted, a value matches conservative secret rules, or policy cannot classify the item safely.
- Users can use an explicit Save Clipboard action when automatic capture intentionally skips an item.
- Source attribution based on the frontmost app is labeled best effort and is never used as proof that content is safe.
- Payloads are encrypted locally using an app-owned key stored in Keychain. Search metadata is minimized and must not contain full sensitive payloads in plaintext.
- Unpinned history expires after 30 days and is capped at 500 items. Pins and favorites are exempt until manually removed.
- Clear History deletes database records, payload files, thumbnails, and derived indexes.
- V1 acknowledges that macOS 26 includes Apple-provided clipboard history. Notch differentiates through notch access, pins/favorites, explicit privacy exclusions, and integration with shelf/OCR—not by claiming unique OS-level capture.

### 5.11 System Monitor

- System totals include CPU utilization, physical-memory pressure/usage, and aggregate interface receive/send rates.
- Process detail includes only processes and CPU/RAM values available through documented interfaces to the current user.
- Sampling intervals, unavailable values, and stale values are represented explicitly.
- Optional menu-bar statistics are independently enabled and use the same provider snapshots as the notch.
- Opening CPU or RAM reveals the accessible process breakdown; opening Network reveals aggregate interface detail and explicitly does not claim per-process attribution.
- System-wide GPU utilization and per-process network byte accounting are not shown in V1.
- The app never invokes or parses `powermetrics`, `nettop`, `top`, `ps`, or other command-line utilities.

### 5.12 Dynamic Mac Island activities

- Activities are typed, local events with priority, coalescing, expiry, and an owning feature.
- Supported sources are: capable volume changes, capability-probed display brightness, battery/charging, supported provider media, calendar meeting reminders, best-effort download/screenshot observations, clipboard smart actions, and local OCR results.
- The app does not suppress Apple’s volume, brightness, camera, microphone, or recording UI.
- Keyboard brightness, global microphone mute, AirPods battery/mode, arbitrary meeting-call control, and exact system-wide download detection are omitted or marked unavailable.
- Repeated high-frequency events coalesce so the island cannot become a continuous distraction.
- A privacy-sensitive activity uses a redacted summary unless the user explicitly permits content display.

### 5.13 Customizable pages

- Users can enable, disable, and reorder available pages locally.
- A page that loses a permission or capability remains configured but displays its denied/unavailable state.
- At least one safe summary page is always available.
- Page ordering is deterministic across launches and does not sync through cloud services.

### 5.14 Focus and Pomodoro

- Timers support work periods, breaks, pause/resume, skip, and completion notifications.
- Time behavior is derived from a monotonic injected clock so sleep/wake and clock changes do not corrupt sessions.
- Frontmost-application tracking is separately opt-in and records bundle identifier plus duration, not window titles or document names.
- Browser-domain tracking is separately opt-in and requires a Safari extension or a Chromium-compatible Chrome/Edge/Arc extension.
- Extensions report only normalized registrable domains. They never transmit full URLs, paths, queries, fragments, page titles, form content, or browsing history.
- Private/incognito sessions are never tracked, even if a browser allows an extension to be enabled there.
- Statistics expire after 90 days by default and can be shortened or cleared immediately.
- Daily and weekly views use the same neutral local aggregates and make untracked intervals explicit.
- Focus Quality, if offered, is disabled by default, explains its inputs, and uses neutral language. The product never labels time, a person, or an application as bad, wasted, or unproductive.

## 6. Onboarding and permissions

Initial launch explains the app without triggering system permission dialogs. The onboarding bundle offers Clipboard History, application tracking, recent screenshots, and download observation together for discoverability, but each option is independently deselectable.

Calendar, Camera, System Audio Recording, Screen Capture, Notifications, keyboard suppression trust, browser extension access, Apple Music, and Spotify authorization are requested only when the user enables or first invokes the corresponding feature. Revocation is checked whenever a protected operation starts and when the app becomes active.

The exact permission ledger and denial behavior are defined in [PERMISSIONS.md](PERMISSIONS.md).

## 7. Data ownership, retention, and deletion

| Data class | Storage | Default retention | Cloud/backend |
|---|---|---:|---|
| Clipboard payloads | Encrypted local records/assets; key in Keychain | 30 days or 500 unpinned items | Prohibited |
| Clipboard pins/favorites | Encrypted local records/assets | Until user deletes | Prohibited |
| Focus sessions/app/domain totals | Local database | 90 days | Prohibited |
| Browser observations | Aggregated locally as normalized domain durations | Raw events discarded after aggregation | Prohibited |
| Shelf managed copies | App-managed temporary directory | 24 hours by default | Prohibited |
| Waveform audio | Memory only | Never persisted | Prohibited |
| OCR input and output | User-provided source plus local transient result | Not retained unless explicitly saved | Prohibited |
| Calendar cache | Minimum fields needed for upcoming display | Short-lived; refreshed from EventKit | Prohibited |
| Spotify credentials | Keychain | Until disconnect/revocation | Provider only |
| Diagnostics | Redacted local logs | Bounded, user-exported only | No automatic upload |

Deleting a feature’s data is independent of revoking its permission. Disconnecting a provider deletes its tokens and provider cache. Disabling automatic observation stops new collection immediately.

## 8. Accessibility and quality bars

- Every interactive element is keyboard navigable and exposes a meaningful VoiceOver role, label, value, and action.
- Information is never communicated by color, animation, or artwork alone.
- Text truncation has a discoverable full-value path without exposing private content in the collapsed state.
- Focus order remains stable across collapsed, hover, and expanded transitions.
- Reduce Motion and Reduce Transparency are tested as first-class configurations.
- Emergency keyboard unlock is not dependent on animation, VoiceOver focus, network, or a provider.
- Energy use is bounded: passive polling backs off, event sources are preferred, and inactive features stop work.

## 9. Explicit non-goals

V1 does not include:

- A native macOS-originated ActivityKit Live Activity.
- Replacement or suppression of Apple’s system HUDs or privacy indicators.
- A generic reader/controller for every media application.
- Private MediaRemote, private Bluetooth/AirPods, private display, or private keyboard-backlight APIs.
- AirPods battery or listening-mode control without a documented public API.
- Global microphone mute; only this app’s own input can be muted through public per-process APIs.
- System-wide GPU utilization or per-process GPU/network accounting.
- Control of an existing Zoom, Meet, or Teams client call.
- Guaranteed system-wide download or screenshot detection.
- AppleScript or Accessibility scraping of browser URLs.
- A Network Extension used solely for productivity tracking or statistics.
- Cloud synchronization of clipboard, focus, browsing, shelf, or activity data.
- A synthetic notch on external or non-notched displays.

## 10. Stage boundary

This specification completes Stage 0 product scope only. Stage 1 must not begin until the feasibility, engineering, permission, and unresolved-risk contracts are accepted. No UI implementation, app target, or scaffolding is authorized by this document.

## 11. Unresolved technical risks

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
- Stage 1 requires full Xcode 26; this machine currently exposes the macOS 26.5 SDK through Command Line Tools but no full Xcode installation.
