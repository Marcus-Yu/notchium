# Product Specification — Stage 2 Reconciliation

**Status:** Engineering contract

**Target:** macOS 26 and later

**Canonical distribution:** Developer ID, hardened runtime, notarized direct download

**Last reviewed:** 2026-08-28

## 1. Product definition

Notchium is a native macOS utility that uses the unobscured menu-bar space around the built-in MacBook display notch as a compact surface for productivity controls and short-lived system context. It is not a replacement for macOS system UI and does not claim ownership of the physical notch.

The product follows three interaction levels:

1. **Collapsed:** passive, glanceable, and visually quiet. Show only the highest-priority state that fits safely beside the physical notch.
2. **Hovered:** reveal a small amount of additional context without taking application focus.
3. **Deliberately opened:** a click or explicit keyboard action opens controls, history, or details. This state may become key when keyboard input is required.

The shell prefers a display whose documented safe-area and auxiliary-area geometry verifies a physical notch. External-only, clamshell, notchless, and otherwise noneligible configurations receive one centered virtual pill on the pointer display, then the primary or first available display. Collapsed physical mode adds no software-drawn black surface outside the hardware obstruction. The persistent menu-bar item remains available in every configuration and becomes the only surface when no display is available. Stage 2 explicitly supersedes the earlier virtual-pill deferral; it does not authorize Ambient Edge or Snap Zone overlays.

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

### Product pillars

1. **Dynamic Mac Island:** a quiet, prioritized activity surface around the physical notch.
2. **Media and audio:** provider-correct media controls, honest audio capabilities, and optional analysis only with explicit consent.
3. **Productivity:** calendar, shelf, clipboard, focus, and deliberate automation through App Intents where public contracts permit it.
4. **System context:** enhanced but subordinate HUD activities, battery information, audio devices, and truthful system metrics.
5. **Window management:** optional direct-distribution Snap Zones with clear Accessibility boundaries.
6. **Presentation and appearance:** native materials, accessible motion, and the optional Ambient Edge display-edge layer.

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
| 15. Per-application audio | **Experimental, direct distribution** | Public Core Audio process/device capabilities only; no private mixer or claim that every application can be controlled. |
| 16. Enhanced volume/HUD context | **Reduced V1** | Parallel Notchium activity using supported Core Audio properties. Apple's HUD remains authoritative and visible. |
| 17. Battery management | **Reduced V1** | Public battery, charging, condition, and adapter information. Charge limiting is deferred without a verified public API. |
| 18. Snap Zones | **Experimental, direct distribution** | User-invoked window placement through public Accessibility APIs, with fail-safe behavior and no private window-server access. |
| 19. Important notification banners | **Reduced V1** | Typed events produced by Notchium features and approved integrations only; no reading of arbitrary Notification Center history. |
| 20. Synchronized lyrics | **Deferred pending provider contract** | Architecture may accept a licensed lyrics provider later; MusicKit metadata does not by itself promise synchronized lyric text. |
| 21. Ambient Edge | **Experimental, post-activity stage** | Optional per-display edge presentation for selected activity state. Static and metadata-derived modes precede any consent-gated audio-reactive mode. |
| 22. Shortcuts and App Intents | **V1.x** | Deliberate, parameterized actions through public App Intents. No hidden background access or broader permission than the equivalent in-app action. |

The feasibility basis and distribution consequences for each row are defined in [FEASIBILITY.md](FEASIBILITY.md). Permission behavior is normative in [PERMISSIONS.md](PERMISSIONS.md).

## 5. Functional requirements and acceptance criteria

### 5.1 Notchium shell and application lifecycle

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

- Three session-only states: off (neutral), system awake (green), and system plus display awake (blue).
- An ordinary click toggles off → system awake, or either active state → off.
- Holding from off or system awake for 0.75 seconds selects system plus display awake. A completed hold consumes the click.
- A continuous border fills over the hold; early release performs the ordinary click and resets the border. Dragging out or cancelling the gesture performs no action.
- The control is icon-only with a tooltip; no caption or duration selector.
- Assertions are released when the user disables the feature and when the process exits.
- Optional [closed-lid mode](LID_AWAKE.md) applies to both active states after separate administrator approval. It uses a short-lived privileged lease, defaults off at launch, and stops under low battery or high thermal pressure.

### 5.9 Keyboard Cleaning Lock

- Enabling requires a successful public session-level active event tap and the required system trust.
- Mouse and trackpad movement and clicks remain usable.
- Clicking the notch or menu-bar lock indicator unlocks immediately.
- Holding Command–Option–Escape for approximately two continuous seconds unlocks. The escape chord itself is recognized before suppression but is not forwarded while locked.
- Event-tap disablement or timeout triggers an immediate verified re-enable; failed recovery, loss of trust, callback failure, app termination, or internal watchdog failure releases the lock immediately.
- The feature never uses a root/HID event tap and never claims to suppress power, Touch ID, Secure Input, firmware, or all reserved system keys.
- If trust is denied, Secure Input is active, or the event tap cannot be established with the full keyboard mask, the app remains unlocked and explains why. Secure Input becoming active also ends an existing lock.

### 5.10 Clipboard History

- The user explicitly enables automatic history and consents to macOS 26 programmatic pasteboard access behavior.
- V1 supports text, web URLs, images, and file references. Unsupported or unreadable representations are skipped.
- Capture is fail-closed when source attribution is unavailable, Secure Event Input is active, the source app is denylisted, a value matches conservative secret rules, or policy cannot classify the item safely.
- Users can use an explicit Save Clipboard action when automatic capture intentionally skips an item.
- Source attribution based on the frontmost app is labeled best effort and is never used as proof that content is safe.
- Payloads are encrypted locally using an app-owned key stored in Keychain. Search metadata is minimized and must not contain full sensitive payloads in plaintext.
- Unpinned history expires after 30 days and is capped at 500 items. Pins and favorites are exempt until manually removed.
- Clear History deletes database records, payload files, thumbnails, and derived indexes.
- V1 acknowledges that macOS 26 includes Apple-provided clipboard history. Notchium differentiates through notch access, pins/favorites, explicit privacy exclusions, and integration with shelf/OCR—not by claiming unique OS-level capture.

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

### 5.15 Approved pre-Stage 2 additions

- Per-application audio, enhanced HUD context, battery information, Snap Zones, important banners, synchronized lyrics, and App Intents remain independent capability-gated features. Approval in the roadmap does not convert an experimental or deferred capability into a V1 promise.
- A shared activity pipeline owns prioritization, coalescing, expiry, privacy redaction, and presentation eligibility. Feature modules publish typed domain events; they do not open presentation windows.
- Important banners represent Notchium-owned events and explicitly approved provider events. The app does not inspect arbitrary notifications generated by other applications.
- App Intents expose only actions that are safe and available in the app, and inherit the same permission, denial, and distribution checks.

### 5.16 Ambient Edge

Ambient Edge is an optional appearance capability, not an RGB-lighting utility and not a second activity system. Its flow is:

`feature or provider event → ActivityCoordinator → Dynamic Mac Island → optional Ambient Edge presentation state`

Acceptance criteria:

- Ambient Edge is disabled by default. Enabling it offers Off, Static, Slow, Ambient, and Beat Reactive modes; Beat Reactive remains unavailable until its capture, provider-policy, energy, and review gates pass.
- Media lighting may derive a bounded local palette from already-authorized album artwork. The collapsed media layout and provider behavior remain unchanged.
- Users may choose colors or gradients and adjust intensity, thickness, and response strength within accessibility and safety bounds.
- Important-notification pulses and Snap Zone feedback consume presentation state from the same coordinator. They do not query notification, media, or window-management services directly.
- Each connected display can be enabled independently. The built-in display may own a physical-notch panel and an independent edge overlay; selected external displays may own an edge overlay without receiving a physical-notch island.
- Normal mode is click-through, nonactivating, and never blocks application controls, the menu bar, Dock, system alerts, or screen corners.
- Automatic suppression is best effort for user-selected applications, full-screen contexts, display sleep, presentation contexts, and known screen-sharing conditions. Because no universal public screen-sharing or full-screen-video detector is promised, manual Pause and per-application exclusions are mandatory fallbacks.
- Static mode performs no persistent frame loop. Animated modes stop when hidden or idle, degrade under Low Power Mode, and reuse one authorized audio-meter pipeline rather than starting a second capture.
- Reduce Motion changes reactive or traveling effects to static color or restrained fades. Reduce Transparency and Increase Contrast produce an opaque/high-contrast equivalent. Color is never the sole signal.
- Release requires measured CPU, GPU, frame pacing, and energy results across single- and multi-display configurations. Metal is not introduced unless profiling demonstrates a concrete need.

## 6. Onboarding and permissions

Initial launch explains the app without triggering system permission dialogs. The onboarding bundle offers Clipboard History, application tracking, recent screenshots, and download observation together for discoverability, but each option is independently deselectable.

Stage 5 Calendar requests full access at first app launch. Camera, System Audio Recording, Screen Capture, Notifications, keyboard suppression trust, browser extension access, Apple Music, and Spotify authorization are requested only when the user enables or first invokes the corresponding feature. Revocation is checked whenever a protected operation starts and when the app becomes active.

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
| Ambient Edge settings | Local preferences | Until reset | Prohibited |
| Derived artwork palette and audio amplitudes | Memory-only presentation state by default | Activity lifetime | Prohibited |

Deleting a feature’s data is independent of revoking its permission. Disconnecting a provider deletes its tokens and provider cache. Disabling automatic observation stops new collection immediately.

## 8. Accessibility and quality bars

- Every interactive element is keyboard navigable and exposes a meaningful VoiceOver role, label, value, and action.
- Information is never communicated by color, animation, or artwork alone.
- Text truncation has a discoverable full-value path without exposing private content in the collapsed state.
- Focus order remains stable across collapsed, hover, and expanded transitions.
- Reduce Motion and Reduce Transparency are tested as first-class configurations.
- Emergency keyboard unlock is not dependent on animation, VoiceOver focus, network, or a provider.
- Energy use is bounded: passive polling backs off, event sources are preferred, and inactive features stop work.
- Ambient Edge remains understandable when disabled and must respect Reduce Motion, Reduce Transparency, Increase Contrast, color-differentiation, display sleep, and Low Power Mode.

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
- A fake hardware notch or claim that the virtual pill owns display hardware. The documented virtual pill is an app window and remains visually distinct from the physical-notch bridge.
- A general RGB/peripheral-lighting utility or a guarantee of pixel-perfect edge effects on every display arrangement.
- Reading arbitrary Notification Center content or mirroring every third-party notification.
- Guaranteed detection of full-screen video, presentations, games, or another application's screen-sharing state.
- Silent or automatic system-audio capture for appearance effects.
- Spotify-derived waveform, beat, or audio-reactive lighting without written policy clearance.

## 10. Stage boundary

Stages 0, 1, and 2 are complete. Stage 2 implements only the prioritized physical-notch/virtual-pill shell, deterministic display geometry, interaction state, native Liquid Glass treatment, accessibility fallbacks, debug fixtures, and menu-bar fallback. It does not implement Ambient Edge, Snap Zones, feature UI, audio capture, permissions, providers, pages, or the later activity coordinator. The sequencing contract is defined in [ROADMAP.md](ROADMAP.md), and the shell contract is defined in [NOTCH_SHELL.md](NOTCH_SHELL.md).

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
- Ambient Edge frame pacing, GPU composition, energy use, and window ordering across multiple displays, Spaces, full-screen applications, sleep/wake, and Stage Manager.
- No universal documented signal has been verified for full-screen video, games, presentations, or another application's screen-sharing state; automatic suppression is necessarily best effort.
- Album-art palette extraction must remain visually stable, accessible, and inexpensive across rapidly changing tracks.
- Audio-reactive Ambient Edge inherits the Core Audio capture, provider targeting, permission, review, and Spotify-policy risks of waveform visualization.
