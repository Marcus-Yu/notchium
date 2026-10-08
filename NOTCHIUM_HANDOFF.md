# Notchium Handoff

Prepared September 29, 2026 against repository HEAD `bc3ec7e` (`Marcus-Yu/notchium`). This is an implementation handoff, not a new exhaustive audit. Current source was spot-checked against repository implementation/validation notes; historical test results below are attributed to those notes, not rerun for this document. No application code was changed. Prior conversations are not available in this chat, so undocumented historical decisions are not invented.

Paths are repository-relative. In the file map, module paths are relative to `NotchiumPackage/Sources/`. Current source wins over older stage documents. In particular, `docs/ROADMAP.md` still describes Stage 2; historical paragraphs in `ARCHITECTURE.md`, `MEDIA_CENTER.md`, and other documents contain superseded geometry, timers, and ownership claims.

## 1. Product Summary

Notchium is a native macOS notch utility: Swift, SwiftUI, AppKit, EventKit, Core Audio, IOKit, and a small C real-time audio module. The package uses Swift tools 6.2, Swift 6 language/concurrency conventions, and macOS 26 minimum deployment. The canonical distribution is a signed/notarized direct app; a reduced sandboxed Store configuration exists but is not fully qualified.

Implemented pages are Home, Music, Calendar, and Audio, plus Settings and header utilities. Music is Spotify-only. Calendar reads selected EventKit calendars; Quick Reminder writes Apple Reminders. Audio controls output devices/system volume and experimentally attenuates individual local applications through process taps. Caffeine provides public idle-sleep assertions, with a separate experimental privileged closed-lid option.

This is a functioning development app with substantial deterministic and native UI coverage, not a fully hardware/release-qualified product. Stage 11 Quick Actions/Quick Reminder already exists. A focused pre-Stage-11 stability pass was completed September 29; a broader code/bug/performance audit remains the next requested step before substantial additional Stage 11 work.

## 2. Current Architecture

- `Notchium/NotchiumApp.swift` is the executable entry; `Notchium.xcworkspace` contains the app project, UI tests, and local Swift package.
- `NotchiumFeature/AppEnvironment.swift` assembles service, persistence, clock, logging, mock, and distribution dependencies. `NotchiumApplicationController` composes long-lived feature models and coordinates lifecycle.
- `NotchiumCore` contains value models/contracts; `NotchiumServices` contains platform adapters and mocks; `NotchiumPersistence` owns local persistence boundaries.
- Feature modules own feature state and views. `NotchiumDynamicIsland` owns activities, presentation, display selection, the panel, geometry, and navigation. Renderer protocols (`NotchMediaRendering`, `NotchCalendarRendering`, `NotchAudioRendering`, `NotchQuickActionsRendering`) keep the shell independent of concrete feature services.
- Service updates generally cross boundaries as typed snapshots/`AsyncStream`; UI/AppKit models are main-actor isolated. Injected `AppClock` supports deterministic scheduling. There is no global mutable event bus.
- Existing skeleton targets for Shelf, Clipboard, Camera, Focus, monitoring, battery, etc. are not evidence those products are implemented. Check composition/feature flags before treating a service called “Real” as functional.

The important separation is provider truth → feature presentation state → activity/presentation policy → shell. Do not move provider I/O into views or create another playback manager.

## 3. Current UI Structure

Confirmed icon-only header:

| Left navigation | Right utilities |
| --- | --- |
| Home, Music, Calendar, Audio | Caffeine, Quick Reminder, Settings, X/Close |

Native tooltips and accessibility labels identify controls; permanent captions are absent. `NotchUtilityLabel` provides common utility chrome. The header is 32 pt high with 28 pt controls and a separate gap before Close. Empty header space is the only page-swipe surface.

All four pages use one **524 × 266 pt outer expanded shell**, inside a stable **740 × 322 pt hosting panel**. Those are different measurements, not competing sizes. Page switches do not resize the shell. Music contains Player/Up Next subnavigation. Calendar and Audio may scroll their own lists; Home cannot scroll in either direction and has no carousel.

All page trees stay mounted; hidden pages are disabled, excluded from hit testing, and hidden from accessibility. A menu-bar fallback and Settings remain available when the physical-notch panel is unavailable.

## 4. Stage / Feature Status

“COMPLETE” below means implemented, not universally hardware-certified. Stage numbering changed; this table describes actual features rather than the obsolete roadmap sequence.

| Stage/feature | Current status |
| --- | --- |
| Early media: Spotify auth/session, metadata/artwork, playback controls, collapsed media, real waveform | COMPLETE implementation; live reliability/energy qualification remains |
| Seek and Spotify volume | COMPLETE with September 29 corrections; current live API/device acceptance PARTIAL |
| Spotify Connect picker and Up Next | COMPLETE; device capabilities and Web API limits apply |
| Calendar: EventKit, primary/upcoming, Join, reminders, overlaps, two-column layout | COMPLETE implementation; live calendar/link scenarios PARTIAL |
| Audio: output devices, writable volume/mute, transient HUD | COMPLETE implementation; hardware matrix PARTIAL |
| Per-app audio/process-tap mixer | PARTIAL qualification; implemented experimental capability-probed path |
| ActivityCoordinator / multi-activity restoration | COMPLETE for current production producers |
| Home Music/Calendar dashboard | COMPLETE; old configurable dashboard removed |
| Stage 9 unified Calendar/Audio notifications | COMPLETE; Stage 11 adds utility feedback |
| Stage 10 interaction/gesture polish | COMPLETE implementation; physical feel and accessibility qualification PARTIAL |
| Caffeine | COMPLETE public assertion controls; closed-lid extension PARTIAL/experimental |
| Stage 11 Quick Actions / existing Apple Shortcuts | COMPLETE implementation; real workflows/bookmarks/Store profile PARTIAL |
| Quick Reminder / offline parser | COMPLETE implementation with recent fixes; fresh TCC/denial recovery still PARTIAL |
| Apple Music, Battery page, Keyboard Lock | REMOVED from current product; legacy battery scaffolding remains |
| Window Snapping | DEFERRED; earlier Home snapping implementation removed |

No feature is labeled BROKEN solely because a historical bug was reported or a live test is missing.

## 5. Music

**Spotify-only. Apple Music support was removed/is outside current scope.** There is no current MusicKit provider to extend accidentally.

`MediaProviding` is the canonical service protocol. `MediaService`, `MediaProvider`, `RealMediaService`, `MockMediaService`, and `MediaFeatureModel` include compatibility aliases; the principal implementations are `RealMediaProvider`, `MediaState`, and `MediaSessionController`.

Authentication uses browser OAuth, random state, S256 PKCE, a single-use loopback callback at `http://127.0.0.1:8888/callback`, and Keychain access/refresh tokens. The public client ID is a preference; there is no embedded client secret. Scopes are `user-read-playback-state`, `user-modify-playback-state`, and `user-read-currently-playing`. Cold restoration and interactive authorization are distinct states. Refreshes are shared; generation cancellation prevents obsolete restoration overwriting a newer login. An authenticated 204/no-player response is not disconnection.

`RealMediaProvider` owns authoritative playback observations. Polls, commands, desktop events, explicit refresh, and Connect transfers converge on `readPlayback(reason:)`. One accepted snapshot contains track identity/title/artist/artwork URL/duration, elapsed baseline/rate, device/capabilities, receipt time, monotonic sample time, and request-start ordering information. `MediaSessionController` exposes presentation state, immediate optimistic feedback, cached paused presentation, and feature lifecycle. It does not own another independent authoritative playback pipeline.

`SpotifyPlaybackAPI` sends commands. `PlaybackReconciliation` is a bounded provider-owned expectation; observation/input revisions reject obsolete responses. Unconfirmed reads retry at 250 ms, 500 ms, and 1 s, with a 10 s safety bound. Confirmation or budget exhaustion releases the expectation; normal polling cannot stay blocked indefinitely. HTTP 429 imposes one shared Retry-After gate across playback/queue/commands, preserving authentication. Cooldown is not persisted across process exits.

Controls and presentation:

- Current artwork/title/artist come from Spotify. The last valid track is persisted for paused/inactive Home and expanded presentation. Cache never proves live/local playback.
- Progress is the accepted elapsed baseline plus monotonic elapsed time × rate, clamped to duration. Local redraw is not network polling. Seeking has a local drag session; releasing commits through the provider. Track changes cancel the drag, and release requires an active session.
- **Current paused seek intentionally seeks then resumes playback**, using one combined position/playing reconciliation condition. Previous/restart retains its separate existing semantics.
- Previous restarts with seek-to-zero above 3 seconds; at/below 3 seconds it skips backward. Next skips forward. Play/Pause captures explicit intent. Shuffle and repeat are capability-aware; repeat cycles off/context/track.
- Spotify volume is separate from system volume. Local optimistic drag feedback is serialized/throttled; final drag completion triggers an authoritative read. A successful PUT alone must not fabricate authoritative volume. Unsupported/restricted Connect devices disable controls.
- Device picker refreshes devices on opening, marks active/restricted devices, and transfers through the Web API while preserving playback intent. It is an in-shell overlay with auxiliary-interaction retention, not a second manager. Device IDs are refresh-scoped.
- With a cached track but no device, Play can launch Spotify via nonactivating `NSWorkspace.openApplication`, wait for a local Connect device, transfer with playback enabled, and reconcile. Failure restores paused presentation.
- Up Next is bounded to 20 items. Opening refreshes immediately; a 5 s cadence exists only while visible. Passive same-track cache is 15 s. Track/skip work is visibility-gated; enqueue has explicit refresh handling.

`SpotifyDesktopPlaybackEvents` observes `com.spotify.client.PlaybackStateChanged` as an empirical desktop refresh hint. Optional event metadata never becomes authoritative track/device data. First refresh is immediate with a 250 ms trailing coalescing window; Web API polling remains the fallback. There is no AppleScript transport or global media-key interception.

`SystemAudioMeter` uses Spotify-only `SpotifyAudioTap`/`SpotifyProcessFinder`, public Core Audio taps, a serial analysis queue, 2,048-sample Hann FFT, and seven frequency bands. Publication is capped at 30 Hz; non-silent activity expires after 250 ms without qualifying samples. Authenticated paused/inactive sessions keep the monitor warm to wake stale Spotify state, with a 2 s refresh cooldown. Disconnect/shutdown stops capture. Up Next suppresses hidden waveform publication while detection continues.

**Preserve these rules:** collapsed artwork/waveform requires a playing Spotify track AND current real local audio activity. Paused/remote/silent/unavailable/cached playback does not produce fake flanks or a decorative waveform. Reduce Motion removes the waveform. Home transport must stay on Home. There are no Music notification banners. Main shell expansion/collapse never scales or morphs media content.

## 6. Home

`HomeDashboardView` is a fixed one-screen Music/Calendar composition, approximately 62%/38% with a 24 pt gutter. It reuses the same media/calendar models and renderer seams; it does not create services or an EventKit store.

Home Media shows artwork, title/artist, progress, Previous, Play/Pause, and Next. **Current code uses the shared interactive seek control**; `docs/HOME_DASHBOARD.md` still calls progress read-only and is superseded by the September 29 fix. Metadata/background navigation uses separate hit regions so controls do not open Music.

Home Calendar shows date/month context and one relevant event with Today/Tomorrow/date/time, or a truthful empty state. Permission/unavailable states navigate to Calendar rather than claiming the day is free. Its date projection updates each minute and excludes ended events.

Fresh expansion chooses Music only under the active Music priority policy; otherwise Home. Once expanded, manual selection stays authoritative until completed collapse. Starting playback from Home must not switch pages.

Settings → Home → Show Quick Actions is off by default. Up to four enabled pinned actions occupy a fixed 30 pt bottom strip with 8 pt spacing above it. There is no Home drag reordering, scrolling, carousel, old slot model, or saved customizable layout. Editing actions routes to Settings.

## 7. Calendar

`RealCalendarService` owns its long-lived event `EKEventStore`, authorization, selected calendar IDs, queries, value projection, and event-change observation. `CalendarActivityModel` owns page state and `selectedEventID`; `CalendarReminderCoordinator` owns reminder thresholds. Reminder creation uses a separate long-lived Reminder service/store, not this event store.

Calendar full access is requested at startup. Selected calendars are persisted; event content is not. Queries cover the next 14 days including active/overlapping non-cancelled events. Refresh triggers include launch, EventKit changes, day changes, wake, foreground activation, calendar selection, and event timing boundaries, rather than continuous database polling.

Two columns: primary event left, upcoming list right (54%/46%, 14 pt gap and Calendar-specific 24 pt horizontal insets). Upcoming events remain individually accessible, including overlaps; only one secondary row expands inline. Stable projected identity combines calendar/event/occurrence information; selection survives refresh/reordering and clears when no longer secondary. Join resolves the selected ID against the latest snapshot. The list scrolls internally without resizing the shell.

`MeetingLinkDetector` searches event URL, location, then notes. It accepts credential-free HTTPS only:

- Zoom: `zoom.us` or subdomains, `/j/`, `/my/`, `/wc/join/`.
- Google Meet: `meet.google.com`, meeting-code path or `/lookup/`.
- Teams: `teams.microsoft.com`, `teams.live.com`, `teams.cloud.microsoft`, `/l/meetup-join/` or `/meet/`.

Join uses injected URL opening backed by `NSWorkspace`. No generic meeting/call control exists.

Timed-event reminders occur 60/30/5 minutes before start; supported meetings can show Join Now at start. Thresholds are consumed once per event within the running process. Launch/wake catch-up emits one meaningful reminder with actual remaining time and consumes older thresholds. Soonest event wins; suppressed stale reminders do not replay. A single next-boundary task handles reminder scheduling; expanded countdown display uses a one-second timeline.

## 8. Audio

`AudioFeatureModel` composes three distinct services:

- `RealAudioDevicesService`: Core Audio output enumeration, default output, writable channel volume/mute, and property listeners. Device change is confirmed by HAL observation, not successful setter return. Output names/capabilities are cached until topology changes.
- `RealAudioProcessesService`: process/running-output/route observation and eligibility probes. The page filters to foreground-capable owning apps with a verified current-output route. Internal Notchium processes/private aggregate devices and uncontrollable apps are hidden. A running silent stream may still appear; running I/O does not prove audible samples.
- `RealAppAudioMixerService`: per-app gain/mute persisted by bundle ID. At 100% unmuted, audio stays direct. Apps needing attenuation/mute get stereo Float32 process taps scoped to the output, combined with the physical output in a private aggregate device.

The taps use `mutedWhenTapped`: direct audio is suppressed only while the IOProc reads. Stopping/failing the graph releases suppression. Process exit/replacement and output changes rebuild topology off the real-time thread; gain-only edits update preallocated atomic slots. `NotchiumRealtimeAudio.c` performs bounded Float32 stereo mixing/clipping with lock-free 32-bit atomics, no allocation, locks, logging, UI publication, or I/O in the callback. Do not generalize that guarantee to every separate waveform-capture callback without inspection.

Tap creation, including eligibility probes, can trigger System Audio Recording consent. Failed/denied probes are not advertised as controllable. Mixer permission failures expose retry/Settings guidance while preserving direct audio. This is an experimental capability-probed mixer, not universal per-app control.

Audio sliders use `NotchiumSlider`'s native local pointer responder. Output feedback handles confirmation arriving before mouse-up; route changes invalidate old writes. Native menus/popovers and the Spotify picker retain the notch through source-keyed auxiliary interactions.

## 9. ActivityCoordinator

`ActivityCoordinator` owns one persistent baseline and a bounded transient dictionary keyed by activity family. Exposed state includes `primary`, `secondary`, `persistentActivity`, `activeTransient`, `liveActivities`, queue count, and presentation mode. Foreground is transient if present, otherwise persistent. Media state itself is never copied into a notification queue.

Generic activity kinds include media, systemHUD, charging, audioDevice, download, screenshot, calendar, focus, battery, meeting, clipboard, notification. Many are skeleton/debug possibilities, not current production features. Generic semantic priorities are low (media/systemHUD), medium (charging/audioDevice/download/screenshot/calendar), high (focus/battery/meeting/clipboard), critical (notification). Actual unified notifications derive their own priority from notification kind.

Generic same-family replacement rejects lower priority; higher priority preempts and can retain a previous generic family entry. Generic transient timers can pause on hover and expire pending entries. **Do not confuse those generic timers with unified notification lifetimes:** notifications have no second activity duration and use their own absolute non-pausing timer.

A stable media activity can survive paused/cached state, while collapsed media visibility is separately gated by live local audio. Music is the fresh expansion default only for playing media or an explicitly Music-targeting transient; otherwise Home.

Music + Calendar reminder: Calendar becomes foreground, Music remains underlying and its eligible collapsed flanks remain visible; expiry exposes the same Music without provider restart. Home + Audio HUD: page selection remains Home; the compact notification is hidden while expanded and expires normally. Closing shows only remaining unexpired feedback, then the underlying state.

Ownership remains distributed deliberately: activities choose presentation priority, `NotchPageModel` chooses the page, `DynamicIslandPresentationModel` chooses interaction/presentation state, and `NotchTransitionSurface` chooses visual reveal phase. Keep their boundaries explicit; generic activities plus specialized notification arbitration are the main overlapping policy area to understand before altering it.

## 10. NotificationCoordinator

`ActivityCoordinator.notifications` owns the single-slot `NotificationCoordinator`; the global activity arbiter remains above it. Calendar/Audio are original producers. **CURRENT CODE additionally supports Stage 11 `actionSucceeded`, `actionFailed`, and `reminderAdded`.** There is still no Music producer/kind.

| Kind | Priority | Duration |
| --- | --- | --- |
| reminder5 / meeting-at-start mapped to reminder5 | High | 5.0 s |
| reminder30, reminder60 | Medium | 5.0 s |
| outputDeviceChanged | Medium | 2.5 s |
| volume, mute | Low | 1.75 s |
| actionSucceeded | Low | 1.5 s |
| actionFailed | Low | 3.0 s |
| reminderAdded | Low | 2.0 s |

Equal priority can replace; lower priority is dropped rather than replayed. Non-Calendar matching coalescing keys preserve identity; unchanged content returns without extending expiry. Meaningful volume/mute changes update one `audio.level` notification and refresh its deadline; output uses `audio.output`. Calendar reminders have discrete identities. Dismissal is identity-checked so retiring gestures cannot dismiss a replacement.

One cancellable task per accepted update captures injected clock time and stores `createdAt`/`expiresAt`; generation checks reject obsolete completion. Hover, drag, page selection, expansion, and collapse do not extend it. Opening at t=1 during a five-second alert and closing after t=5 cannot replay that alert.

Compact Calendar/Audio feedback is hidden while expanded. **Current exception:** `NotchiumShellView` renders `reminderAdded` in an existing bottom slot while expanded, without selecting or closing the page. Older Stage 10 descriptions of a general expanded Audio strip are superseded; do not assume all utility feedback is visible while open.

Visual contract: the physical black notch appears to grow downward as one continuous silhouette, not a notch plus rectangular card. Black shell, soft concave shoulders, rounded lower corners, restrained spacing/motion, minimal glass accents. Calendar content height is 88 pt; Audio 56 pt; notification shoulders 12 pt and lower radius 34 pt. Music flanks persist during compatible collapsed notification transitions, but main expansion/collapse still uses the black content gate.

## 11. Notch Window / Animation

`NotchiumDisplayCoordinator` selects a verified built-in hardware notch via public display geometry and manages one `NotchiumPanelController`. Current production behavior hides the panel without a qualifying notch and retains the menu fallback; do not assume an old virtual-pill roadmap promise is enabled.

`NotchPanel` is borderless, nonactivating, transparent/nonopaque, shadowless, immovable, cannot become key/main, and uses `.screenSaver` level. Collection behavior is `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, `.ignoresCycle`. It does not hide on deactivation. The frame stays stable; SwiftUI animates the internal shape. AppKit frame constraints are overridden to permit the menu-bar/notch region.

Hover entry is 120 ms; exit grace 200 ms. Click pins; pinned ignores pointer exit; outside click/appropriate Escape closes. Space change collapses/unpins using the existing animation and reasserts the existing panel without resetting services. OS Space-change notification timing does not guarantee first-frame swipe behavior.

Source-keyed auxiliary retention protects nested `NSMenu` tracking, picker, and reminder popover interactions. Escape defers to children; ordinary notch activation remains usable during a notification. Reminder focus uses only the native child popover/key window and SwiftUI focus, not `NSApp.activate`.

`DynamicIslandPresentationModel` owns collapsed/hovered/pinned target state and timer bookkeeping. `NotchTransitionSurface` separately owns `collapsed → openingBlack → expanded → closingBlack → collapsed` visual phases:

- Open: hide collapsed content immediately; black geometry expands; reveal full-sized expanded content at 75% of height growth under the moving clip.
- Close: hide expanded content immediately; black shell contracts; reveal collapsed content only after animation removal/completion, including the spring tail.
- Generation tokens reject stale completion and support reversal without close/reopen queues. Content stays mounted at final dimensions; hidden children do not inherit unwanted animation transactions.

Main geometry spring: response 0.40, damping 0.80, blend 0. Reduce Motion: 0.12 s ease-out. Content hide/reveal is binary/0 ms, not a scale or media cross-morph. No media zoom, shrinking page, matched geometry, or content retraction into the notch. The concept was inspired by BoringNotch; repository notes record independent implementation without copied GPL source.

## 12. Navigation State

`NotchPageModel.selectedPage` is authoritative. Header buttons, Home links, explicit notification activation, and the empty-header page-swipe surface are legitimate user writers. Playback streams do not write page selection.

`beginExpansion(default:)` runs automatic selection only when a new expansion session begins. It sets the Music/Home default and resets `manualSelectionDuringExpansion`. Subsequent explicit writes mark manual choice; repeated expansion and closing-animation reversals preserve the existing session/page. `endExpansion()` runs on completed collapse or explicit nonanimated reset, not merely when the animation target becomes collapsed.

The session guard, not just the Boolean flag, prevents automatic overwrite. A user clicking a notification destination is intentional navigation, not notification arrival stealing selection. Enabled-page normalization/fallback can also change selection; preserve validity without adding activity-driven writers.

## 13. Caffeine

| Start | Short click | 0.75 s hold |
| --- | --- | --- |
| BASE/off | GREEN/system | BLUE/system + display |
| GREEN/system | BASE/off | BLUE/system + display |
| BLUE/system + display | BASE/off | Click-only session; release turns off |

`CaffeineControlModel` owns mode presentation and `CaffeinePressInteraction`. `RealCaffeineService` owns `IOPMAssertionID`: GREEN uses `kIOPMAssertionTypePreventUserIdleSystemSleep`, BLUE uses `kIOPMAssertionTypePreventUserIdleDisplaySleep`; off/shutdown releases. A replacement assertion is created before releasing the old one. These ordinary assertions do not override lid-close sleep.

The native AppKit header input forwards down/drag/up into one monotonic press session. Hold border progress is elapsed/750 ms; a ~16 ms task updates only during a press. Mouse-up resolves the same deadline if needed; a completed hold consumes release exactly once. Movement tolerance is 10 pt; leaving latches cancellation. Configuration/view updates retain the session; removal/shutdown cancels it. The former combined SwiftUI GestureState/drag/task implementation could cancel prematurely.

Separate implemented experiment: Settings closed-lid keep-awake registers a signed `SMAppService` daemon, requires administrator approval, defaults off each launch, and leases privileged `pmset -a disablesleep 1`. It is system-wide, including manual Sleep, not a normal idle assertion. XPC peer signing checks, a root-owned recovery journal, 5 s renewals/15 s lease, and battery/thermal failure recovery constrain it. See `docs/LID_AWAKE.md`, `LidAwakeController.swift`, `LidAwakeProtocol.swift`, and `Helpers/`. Physical lid qualification is still required; do not conflate ordinary Caffeine success with helper qualification.

## 14. Quick Reminder

Keyboard Lock was intentionally removed and replaced by Quick Reminder. Its service/feature files are deleted; historical documentation may still mention them. Do not restore it.

`QuickReminderButton` opens a compact native popover with text, native date, At Time toggle, native time control, Add, Return-to-save, and Escape-to-cancel. `QuickReminderModel` owns the draft, validity, parsing, access/list state, and guarded save. Today/all-day is the default; manual At Time enabling chooses the next half-hour with midnight handling. Outside dismissal preserves an unsaved draft; successful save clears it; failure retains text and shows an inline error. Auxiliary interaction keeps the notch open.

`EventKitReminderService` owns **one long-lived EKEventStore for Reminder access**. Saving creates **exactly one EKReminder, never a duplicate EKEvent**. Apple Calendar may show this same object through Scheduled Reminders; Notchium does not duplicate it into Calendar. All-day due components omit time/timezone; timed components include local time/timezone; both include Gregorian calendar components.

Permission authority is `EKEventStore.authorizationStatus(for: .reminder)`. Model states are notDetermined/allowed/denied/restricted (writeOnly maps denied). Only notDetermined requests full access; concurrent callers share one in-flight request. No UserDefaults permission flag is authoritative. Open/enable refreshes access and writable lists; active composers observe EventKit changes and app activation. Save checks fresh access again.

List choice is configured writable list → writable system default → first writable list. No writable list is a real error, not an invitation to save an event instead. Add validity includes effective title, valid date/time, permission, resolved writable list, and no in-progress save. Add/Return share a guard established before asynchronous work, preventing duplicates.

`ReminderNaturalLanguageParser` is offline Foundation-only, combining deterministic suffix rules and constrained `NSDataDetector`. No external LLM/network. Model debounce is 250 ms through `AppClock`; save parses latest input immediately, even before debounce. Session revisions/cancellation reject stale completion.

Supported confident suffixes: today/tomorrow; full English weekdays with this/next; full or three-letter English month + day + optional four-digit year; month/day + optional year; am/pm with optional minutes/space; 24-hour hour:minute; optional “on”/“at” connectors. Examples `test friday 3pm`, `presentation tuesday 6:00 pm`, and `dentist tomorrow 10:30am` update controls without rewriting editing text. Save alone strips confidently parsed suffix/connector. Temporal-only text has no effective title and cannot save.

Bare weekday means strictly future (same weekday → +7 days); “this” includes today; “next” means next calendar week according to firstWeekday. Yearless past dates advance a year; time-only finds the next valid occurrence, including DST handling. Unsupported/partial/non-suffix expressions remain text; invalid time after a recognized date can update only the date. “last”/“every” are not silently treated as plain weekdays.

Manual date/time/toggle edits win over the same temporal signature, including pending debounce. Title-only edits and equivalent time formatting retain the override; a new recognized temporal phrase can release it. Do not strip unsupported text or fight the native picker.

## 15. Quick Actions / Apple Shortcuts

Implemented types: `QuickAction`, `QuickActionStore`, `QuickActionRunner`, `ShortcutService`, `QuickActionsModel`, native Settings/editor, optional Home strip. Kinds: existing Apple Shortcut, Application, File, Folder, HTTP(S) URL. Notchium does not author workflows or offer arbitrary shell commands, command launching, keyboard macros, or mouse macros.

Shortcuts discovery uses `/usr/bin/shortcuts list --show-identifiers` on Settings/editor opening, refresh, or active Settings activation. Stored UUID AND exact name must match fresh discovery before execution via `shortcuts run -- UUID`; rename/replacement requires reselection. It uses direct subprocess arguments without shell interpolation, stdin, or retained workflow output. Discovery timeout is 15 s; runs are cancellable through Settings/shutdown.

Native `NSOpenPanel` obtains app/file/folder targets and read-only security-scoped bookmarks. Resolution validates type/existence, refreshes stale bookmarks, and balances scope access. `NSWorkspace` opens the resource; URLs reject credentials/non-HTTP(S). Settings supports names, enabled/pinned state, icons, edit/relink/remove, and list reorder. Home shows at most four pinned actions with no drag reordering. A spinner appears only after 350 ms. Utility notifications carry no page destination.

Remaining qualifications: real shortcut execution/cancellation, relocated bookmarks after signed-app relaunch, full keyboard/VoiceOver, and Store sandbox CLI support.

## 16. Permissions

| Capability | Why / request owner | Configuration / optionality |
| --- | --- | --- |
| Spotify OAuth | Playback, queue, Connect; SpotifyAuthorization/browser + loopback | User connects; public client ID and Keychain tokens. Store profile network.client/network.server. No Automation TCC path |
| Calendar | Read selected events; RealCalendarService startup request | `NSCalendarsFullAccessUsageDescription`; personal-information.calendars entitlement in both profiles. Denial leaves other features usable |
| Reminders | Create user-entered EKReminder; EventKitReminderService only when notDetermined | `NSRemindersFullAccessUsageDescription`; current configs use personal-information.calendars. Optional Quick Reminder; system status is authority |
| System Audio Recording | Spotify waveform/activity and controllable-app probes/mixing | `NSAudioCaptureUsageDescription`; Core Audio tap creation owns consent, no separate reliable preflight API. Denial degrades capture/mixer |
| File access | User-selected action targets/bookmarks | NSOpenPanel; Store user-selected.read-only and bookmarks.app-scope entitlements |
| Caffeine | Idle sleep/display assertions | Public IOKit; no Accessibility/TCC grant required |
| Experimental lid helper | System sleep override lease | SMAppService/admin approval, signed daemon/XPC; direct distribution only |

Current four-page product/Quick Reminder does not require Accessibility permission. Legacy permission enums/future scaffolding are not a reason to request it. No microphone, Notification Center reader, or current AppleScript Automation feature is implied.

**Documentation conflict:** older media notes claim waveform permission is only explicitly requested. Current `SystemAudioMeter` attempts its Core Audio capture lifecycle while authenticated; tap creation/probes may prompt and retry is explicit. Follow actual capture/TCC behavior, not that stale promise.

For permission testing, preserve stable signed `com.marcusyu.notchium` identity and stop old instances. September 28 found signed and ad-hoc/unsigned builds running together with different designated requirements and TCC attribution errors. A clean signed instance loaded lists/saved; the notes do not conclusively attribute the stale OS state to one cause. Do not add runtime permission resets or a local permission-authority flag.

## 17. Design System / Skills

Native macOS, restrained hierarchy, deliberate whitespace, semantic text where appropriate, SF Symbols/system typography, and minimal glass. Music hierarchy: identity → progress → transport → volume/output. Native controls, menus, List/Form, popovers/sheets, NSOpenPanel, and NSWorkspace are preferred. Avoid mobile navigation, excessive glass pills, decorative motion, and unnecessary custom control behavior.

`ExpandedPageStyle`: spacing 4/8/12/16/24; outer inset 30, top 8, bottom 12, group gap 12, column gap 24; header 32/control 28; normal control 32/compact 24; control radius 6/selection 8/artwork 12; title 16 semibold/body 12/caption 11/section 11 medium. Feature-specific overrides exist (e.g. Calendar insets/type); there is not one perfectly universal typography implementation. `NotchiumSlider` is an intentional custom SwiftUI drawing/native AppKit pointer bridge adopted for non-key panel correctness, retaining accessibility.

Retain these user-specified design references; they are guidance, not claimed dependencies or newly reviewed sources:

- Primary: Emil Kowalski skills, https://github.com/emilkowalski/skills — apple-design, emil-design-eng, animate, review-animations.
- macOS/HIG: Dick Wu apple-design-skill, https://github.com/dickwu/apple-design-skill.
- Supporting: UI/UX Pro Max for spacing/hierarchy/density; Anthropic frontend-design for composition/negative space/anti-generic design; Vercel design guidelines for final usability/accessibility review.
- Later: platform-design-skills/macOS, design-swiftui-interfaces, swiftui-liquid-glass, guide-swiftui-animations, Emil improve-animations/find-animation-opportunities, swiftui-design-skill, TCA state/testing concepts. TCA is not the current architecture.

Native macOS conventions override generic web/mobile recipes. Main shell geometry and black-content choreography are established product constraints.

## 18. Timing / Constants

| Mechanism | Current value |
| --- | --- |
| Canonical expanded shell / host | 524 × 266 / 740 × 322 pt |
| Hover enter / exit grace | 120 / 200 ms |
| Main shell | spring 0.40 response / 0.80 damping / 0 blend |
| Reduce Motion shell | 120 ms ease-out |
| Opening content reveal | 75% height growth; immediate visibility switch |
| Notification entry / exit | 0.26 / 0.20 response, damping 1.0 |
| Same-size notification content change | 100 ms opacity |
| Calendar / Audio notification content | 88 / 56 pt; shoulders 12/lower corners 34 |
| Calendar thresholds | 60/30/5 minutes; meeting start; 5 s display |
| Output / volume-mute feedback | 2.5 / 1.75 s |
| Action success / failure / reminder added | 1.5 / 3 / 2 s |
| Previous restart boundary | >3 s restart; otherwise Previous |
| Spotify reconciliation retries / bound | 250, 500, 1,000 ms / 10 s |
| Spotify volume throttle | 120 ms; final read confirms final command |
| Local audio wake-up cooldown / stale activity | 2 s / 250 ms |
| Caffeine hold / movement tolerance | 750 ms / 10 pt |
| Reminder parse debounce / delayed action spinner | 250 / 350 ms |
| Shortcut discovery timeout / OAuth listener timeout | 15 s / 5 minutes |
| Notification upward dismiss | 6 pt recognition; 32 pt distance, or 14 pt + predicted >56 pt; resisted movement <18 pt |
| Page swipe | horizontal intent 8 pt; change at 30 pt; one page/sequence, no wrap/momentum |
| Calendar inline disclosure | 250 ms smooth; Reduce Motion 120 ms |

Older 520 × 250/560 × 302 shell sizes, 340/300 ms main animations, 500 ms media polling, read-only Home progress, and old permission/static-waveform descriptions are historical, not current specifications.

## 19. Performance / Polling

| Work | When/frequency | Stops/optimization |
| --- | --- | --- |
| Spotify fallback | One authenticated provider poller: collapsed playing 5 s, otherwise 15 s; expanded playing 2.5 s, paused 5 s, inactive 10 s; failures 30 s | Disconnect/shutdown cancels; shared Retry-After supersedes cadence; no catch-up bursts |
| Spotify desktop hints | Event-driven immediate + 250 ms trailing coalescing | One listener; lifecycle teardown; no global keyboard monitor |
| Up Next | Immediate on opening, then 5 s visible-only | Hidden page stops cadence; passive cache 15 s; bounded/coalesced reads |
| Device picker | One discovery when opened | No polling loop |
| Progress | Shared view timeline up to 0.1 s while playing/visible | Paused/hidden/drag states suspend timeline; no provider writes |
| Spotify audio meter | Capture callbacks, FFT output ≤30 Hz; one 250 ms inactivity watchdog | Avoid unchanged/silent publications; hidden waveform suppressed; disconnect/shutdown tears down |
| Calendar | Event/boundary-triggered EventKit refresh; one next reminder timer | No constant EventKit polling; expanded countdown 1 s; Home date context 1 minute |
| Notifications | One lifetime task per accepted update | Cancelled on replacement/dismissal; no idle ticker or expansion pause |
| Audio output/processes | HAL property listeners/probe cache | Listener teardown; topology rebuild off RT thread; gain changes atomic; direct path at unity gain |
| Caffeine | Hold progress ~16 ms only during hold | No ordinary idle polling; assertions live until release |
| Lid helper (optional) | Renewal 5 s; helper watchdog 1 s, 15 s lease; pmset deadline 3 s | Separate opt-in experimental lifecycle |
| Reminder / Shortcuts | 250 ms edit debounce / on-demand discovery | No background polling or disabled-Home-strip work |

Artwork is bounded (eight decoded thumbnails/~1 MB cache, ≤160 px downsample, ≤2 MB HTTPS Spotify-CDN input); queues/streams are bounded. Meter lifecycle is serialized so rapid stop/resume does not overlap capture ownership.

Known performance debt/qualification: authenticated paused monitoring keeps a tap warm; process eligibility probes/topology rebuilds need realistic hardware profiling; live simultaneous mixing, active playback, long-duration memory/wakeups/energy and frame pacing remain unmeasured. A historical ~10.9 s idle sample (28 ms vs 13 ms sampled CPU) is not a controlled energy result. No new profiling was performed for this handoff.

## 20. Known Bugs

Distinguish a code correction from exhaustive live acceptance. Current notes do not establish an outstanding universally reproducible high-severity bug in these paths.

| Historical issue | Current classification / evidence |
| --- | --- |
| Playback/seek bar unreliable | FIXED at reproduced native-pointer and provider reconciliation boundaries; UNKNOWN/NEEDS RETEST for current live Spotify/API/device propagation |
| Music volume unreliable | FIXED fabricated acknowledgement and final confirmation path; UNKNOWN/NEEDS RETEST on real supported device (observed live iPhone correctly lacked volume capability) |
| Audio slider gesture conflicts | FIXED shared native pointer input; automated clicks/drags pass; physical trackpad/hardware gain UNKNOWN/NEEDS RETEST |
| Paused seek/resume Home–Music glitch | FIXED seek-then-play combined expectation and page ownership; combined live Spotify sequence UNKNOWN/NEEDS RETEST |
| Page choice overridden | FIXED expansion-session/reversal ownership; automated activity churn and latest-click coverage; full live playback churn UNKNOWN/NEEDS RETEST |
| Caffeine hold sometimes fails | FIXED native/model press session; documented 20/20 then 5/5 physical-pointer automated holds; broad hardware/movement acceptance incomplete |
| Add disabled with valid Reminder input | FIXED stale access/list refresh and effective-title validity; signed live Add documented; fresh grant/denial recovery UNKNOWN/NEEDS RETEST |
| Repeated Reminder permission prompt | FIXED/request discipline present and signed relaunch reuse documented; earlier signing/TCC attribution issue not conclusively diagnosed; fresh system transition UNKNOWN/NEEDS RETEST |
| Reminder save switches fullscreen/Space | FIXED removal of global activation; September 28 Safari/Chrome live saves preserved context. Ordinary desktop/additional Space not fully verified; September 29 smoke check is weaker evidence |
| Notification blocks expansion | FIXED interaction/absolute lifetime path with regression coverage; continuous physical gesture matrix UNKNOWN/NEEDS RETEST |
| Rapid-reversal unit test | INTERMITTENT historically: one failure in 327-test run, isolated rerun passed; later 339-test suite passed. Do not report as a current confirmed UI failure |

Additional limits: no broad hardware qualification for per-app tap audio, hot-plug/Bluetooth, physical lid helper behavior, VoiceOver/full keyboard traversal, dark Reminder contrast, signed sandbox Shortcuts/bookmarks, or 60 fps main-shell/Space-swipe recording. These are verification gaps, not invented defects.

## 21. Previous Fix Attempts

- Spotify first accumulated controller-specific seek/track intent guards; these were consolidated into provider-owned `PlaybackReconciliation`, observation revisions, request-start barriers, and bounded retries. Do not recreate the old competing controller state machines.
- Previous/restart conflicts were addressed by mutually exclusive expectations and atomic progress/time rebasing. The latest paused seek correction reserves seek+play together and ignores intermediate paused/desktop observations until combined confirmation.
- Home originally disabled progress hit testing over an Open Music background; shared interactive seeking replaced it. A real pointer test then showed SwiftUI drag handling ineffective in the non-key panel; local AppKit first-mouse down/drag/up fixed the actual input boundary.
- Volume PUT acknowledgements incorrectly released optimistic state using fabricated snapshots. Current final-command read is intentional; older “no confirming GET at all” optimization notes are superseded. Fixed percentage label space prevents layout movement during dragging.
- Output volume optimistic state could remain pinned if HAL confirmed before release. Release now clears already-confirmed feedback; route change cancels obsolete work.
- `manualSelectionDuringExpansion` alone was insufficient when closing immediately counted as collapsed. Expansion session now lasts until completed collapse; reversal preserves manual choice. Playback does not subscribe to page selection.
- Notification hover/expanded lifetime problems were replaced with absolute `createdAt`/`expiresAt` and one generation-checked task. Do not reintroduce relative remaining-time pause for unified notifications.
- Caffeine moved from view-local task/GestureState resets to model-owned monotonic native press handling, tolerance, latching cancellation, and release consumption.
- Quick Reminder uses a retained service/store, not per-popover EventKit construction. Request coalescing, authorization/list refresh, shared validation/save fallback, immediate latest-text parsing, and early duplicate guard address stale Add/permission/save problems. Stable signing is part of testing discipline, not an app workaround.
- Removed `NSApp.activate` from Reminder popover attachment and repeated panel reconciliation; only child focus is requested. Added visible expanded Reminder Added confirmation without page navigation.
- Full-page scroll interception was replaced by a hit-tested empty-header swipe surface. Notification drag is on unused background, not on Join/buttons/sliders. Auxiliary retention is keyed by source to protect nested children.

## 22. Removed / Deferred Features

**REMOVED:** Apple Music/current MusicKit support; Battery page; Keyboard Lock (including its service/two feature files); configurable Home slots/module sizes/layout persistence; Home snapping/favorites/window presets and related `HomeLayoutModel`, `HomeSettingsSection`, `HomeWindowLayouts`, `WindowLayoutService`, `WindowLayoutPreset`.

Battery service/monitoring and other early skeleton files still exist. Generic activity kinds/feature IDs, historical docs, or placeholders do not restore a removed page. Keyboard Lock is not a suggested follow-up.

**DEFERRED/out of scope:** Window Snapping, advanced Home customization, broader notification sources, additional action/workflow features, lyrics, Ambient Edge and other roadmap experiments, and final release/accessibility/performance polish. Existing Apple Shortcuts integration is implemented; a custom workflow builder/arbitrary command or macro system is expressly out of scope. Ordinary idle Caffeine and the implemented optional lid helper must not be confused with these deferred features.

## 23. Important Files / Types

The grouped entries below are an orientation map, not an exhaustive source inventory. Prefix source paths with `NotchiumPackage/Sources/`.

| Area | Entry point → responsibility |
| --- | --- |
| App | `Notchium/NotchiumApp.swift` (repo root) → lifecycle/scenes |
| Composition | `NotchiumFeature/AppEnvironment.swift` → dependencies/fixtures |
| Composition | `NotchiumFeature/NotchiumApplicationController.swift` → long-lived feature/panel wiring |
| Settings | `NotchiumFeature/NotchiumSettingsView.swift` → native configuration composition |
| Shell | `NotchiumDynamicIsland/NotchiumDisplayCoordinator.swift` → selected display/panel lifecycle |
| Shell | `NotchiumDynamicIsland/NotchiumPanelController.swift`, `NotchPanel.swift` → AppKit window/input/retention |
| Shell | `NotchiumDynamicIsland/DynamicIslandPresentationModel.swift` → interaction/presentation targets |
| Shell | `NotchiumDynamicIsland/NotchiumShellView.swift`, `NotchTransitionSurface.swift` → shape/content choreography |
| Geometry | `NotchiumDynamicIsland/NotchPanelLayout.swift` → canonical shell/host dimensions |
| Activities | `NotchiumDynamicIsland/ActivityCoordinator.swift`, `ActivityPriorityPolicy.swift` → baseline/transients/priorities |
| Notifications | `NotchiumDynamicIsland/NotificationCoordinator.swift`, `NotchNotification.swift` → slot/deadlines/kinds |
| Navigation | `NotchiumDynamicIsland/Pages/NotchPageModel.swift`, `NotchPagesView.swift` → selection/session/mounted pages |
| Home | `NotchiumDynamicIsland/Home/HomeDashboardView.swift` → fixed composition |
| Media contract | `NotchiumServices/MediaService.swift` → MediaProviding, MediaState, commands |
| Spotify | `NotchiumServices/RealMediaProvider.swift` → authoritative reads/commands/poll lifecycle |
| Spotify | `NotchiumServices/PlaybackReconciliation.swift` → bounded command confirmation |
| Spotify | `NotchiumServices/SpotifyPlaybackAPI.swift`, `SpotifyAuthorization.swift` → HTTP/cooldown/OAuth/Keychain |
| Spotify | `NotchiumServices/SpotifyPlaybackEvents.swift`, `SpotifyLoopbackCallback.swift` → hints/callback listener |
| Music | `NotchiumMediaFeature/MediaFeatureModel.swift` → MediaSessionController/cache/optimistic controls |
| Music UI | `NotchiumMediaFeature/MediaProgressView.swift`, `MediaViews.swift`, `HomeMediaView.swift` → shared controls/views |
| Waveform | `NotchiumMediaFeature/SystemAudioMeter.swift`, `SpotifyAudioTap.swift`, `AudioSpectrumAnalyzer.swift` → capture/activity/FFT |
| Calendar service | `NotchiumServices/CalendarService.swift` → EventKit values and MeetingLinkDetector |
| Calendar model | `NotchiumCalendarFeature/CalendarActivityModel.swift` → page snapshot/secondary selection |
| Calendar scheduling | `NotchiumCalendarFeature/CalendarReminderCoordinator.swift` → event reminder boundaries |
| Calendar views | `NotchiumCalendarFeature/CalendarActivityView.swift`, `CalendarUpcomingEventRow.swift`, `HomeCalendarView.swift` |
| Audio UI | `NotchiumAudioFeature/AudioFeatureModel.swift`, `AudioPageView.swift` → output/mixer presentation/feedback |
| Audio adapters | `NotchiumServices/AudioDevicesService.swift`, `AudioProcessesService.swift` → devices/eligible processes |
| Mixer | `NotchiumServices/AppAudioMixerService.swift`, `NotchiumRealtimeAudio/NotchiumRealtimeAudio.c` → topology/RT mixing |
| Caffeine | `NotchiumCaffeineFeature/CaffeineControlModel.swift`, `NotchiumServices/CaffeineService.swift` → press/mode/assertions |
| Caffeine input | `NotchiumDynamicIsland/CaffeinePressInteraction.swift`, `CaffeinePressButtonStyle.swift` → monotonic press/native input |
| Lid helper | `NotchiumServices/LidAwakeController.swift`, `LidAwakeProtocol.swift`; repo `Helpers/` → privileged experiment |
| Reminder UI | `NotchiumQuickActionsFeature/QuickReminderModel.swift`, `QuickReminderButton.swift` → draft/popover/save |
| Reminder parser | `NotchiumQuickActionsFeature/ReminderNaturalLanguageParser.swift` → offline suffix parsing |
| Reminder service | `NotchiumServices/ReminderService.swift` → EventKitReminderService/TCC/lists/one EKReminder |
| Actions data | `NotchiumCore/QuickAction.swift`, `NotchiumPersistence/QuickActionStore.swift` → action models/preferences |
| Actions run | `NotchiumQuickActionsFeature/QuickActionRunner.swift`, `NotchiumServices/ShortcutService.swift`, `QuickActionWorkspace.swift` |
| Actions UI | `NotchiumQuickActionsFeature/QuickActionsModel.swift`, `QuickActionsSettings.swift`, `QuickActionEditor.swift`, `HomeQuickActionsView.swift` |
| Shared design/input | `NotchiumDesignSystem/ExpandedPageStyle.swift`, `NotchiumSlider.swift` → tokens/native slider bridge |

Read `docs/STABILITY_AUDIT.md`, `BEHAVIORAL_OWNERSHIP_FIXES.md`, `SPOTIFY_PLAYBACK_PIPELINE.md`, and `STAGE11_QUICK_ACTIONS.md` first for recent reasoning, then `NOTCH_SHELL.md`, `AUDIO.md`, and `CALENDAR_ACTIVITY.md`. Test entry points live in `NotchiumPackage/Tests/NotchiumFeatureTests/` and `NotchiumUITests/`.

## 24. State Ownership

| State | Owner | Other writers / notes |
| --- | --- | --- |
| selectedPage/manual session | NotchPageModel | Header, Home links, notification activation, header swipe; automatic default only at session start. Public writable selection/fallback deserves care |
| Expanded/hovered/pinned target | DynamicIslandPresentationModel | Panel pointer/keyboard/Space events, Close, auxiliary retention; not feature services |
| Visual transition phase | NotchTransitionSurface | Geometry observations and generation-checked completion; separate from target/bookkeeping |
| Active/underlying activity | ActivityCoordinator | Media persistent producer; notification bridge; generic/debug producers |
| Active notification/deadline | NotificationCoordinator | CalendarReminderCoordinator, Audio HUD, action/reminder results; global arbiter can preempt |
| Authoritative playback snapshot | RealMediaProvider | Unified read ingestion; revisions/reconciliation; desktop hints trigger reads only |
| Displayed/cached playback | MediaSessionController | Optimistic control updates + accepted provider samples/cache; deliberately distinct from provider truth |
| Seek drag/progress | MediaSessionController + shared MediaProgressView timeline | Local drag/optimistic rebase; provider owns confirmation. Do not add another confirmation owner |
| Spotify volume | Provider snapshot + controller pending feedback | Drag serializer/throttle and final authoritative read; separate from HAL output volume |
| System/output volume | RealAudioDevicesService | HAL/external keys/UI setter; AudioFeatureModel owns temporary feedback and stale-write guards |
| Per-app gain/mute | Mixer service/persisted targets | AudioFeatureModel controls; RT atomic slots are derived render state |
| Calendar events | RealCalendarService | EventKit/query/selection boundaries; CalendarActivityModel owns selected secondary ID |
| Reminder authorization | macOS/TCC via EventKitReminderService | QuickReminderModel caches presentation/refetches; preferences never authority |
| Reminder draft/parsed controls | QuickReminderModel | Native edits/parser with signature/manual precedence; service receives validated draft only |
| Caffeine mode/assertion | RealCaffeineService | CaffeineControlModel user commands; model also owns press session; helper has separate lease |

Most overlap is intentional optimistic-versus-authoritative state. Highest-risk boundaries for audit are playback ordering, slider pending feedback, generic-versus-notification lifetimes, and target-versus-visual collapse completion. They are not justification for a new global store.

## 25. Data Flow

```text
SPOTIFY
OAuth/Keychain → SpotifyPlaybackAPI
poll / desktop hint / command → RealMediaProvider.readPlayback
→ MediaState → MediaSessionController → Music / Home
                                      └→ persistent ActivityCoordinator entry
Spotify process PCM → SpotifyAudioTap → FFT → SystemAudioMeter
→ real local activity gate / waveform / bounded metadata refresh hint

CALENDAR
EventKit → RealCalendarService → CalendarSnapshot → CalendarActivityModel
→ Calendar / Home
→ CalendarReminderCoordinator → NotificationCoordinator

AUDIO
HAL listeners → AudioDevicesService / AudioProcessesService → AudioFeatureModel
→ Audio page + NotificationCoordinator
per-app targets → AppAudioMixerService → tap topology + atomic gains → C IOProc

NOTIFICATION / SHELL
Calendar / Audio / utility result → NotificationCoordinator
→ ActivityCoordinator arbitration → DynamicIslandPresentationModel
→ NotchiumShellView / NotchTransitionSurface inside fixed NSPanel
NotchPageModel independently owns the user's expanded page

REMINDER
QuickReminderButton → QuickReminderModel ↔ ReminderNaturalLanguageParser
→ EventKitReminderService → one EKReminder
→ reminderAdded feedback (no automatic page selection)

QUICK ACTION
Settings / optional Home strip → QuickActionRunner
→ ShortcutService OR QuickActionWorkspace → existing workflow/native resource
→ utility result notification
```

## 26. Test Status

**This handoff:** repository/doc/source inspection and document whitespace verification only. No app build, package test, UI test, live permissions, or hardware profiling was rerun; application code was untouched.

Latest recorded evidence in `docs/STABILITY_AUDIT.md` (September 29):

- Swift package build PASS; signed macOS Debug build after final source edit PASS.
- 30 distinct focused unit checks PASS; no new full hundreds-test run in that pass.
- Native pointer scenario passed Home/Music seeking, Spotify/output volume clicks/drags, and repeated page selection against fixtures. The ineffective seek click was reproduced before its native responder fix.
- Five Caffeine pointer holds passed 5/5; mock Reminder focus/save/Escape/retention and shell hover/close/relaunch scenarios passed.
- `git diff --check` passed. The final track-change seek-release guard compiled after the pointer scenario; that exact small guard was not separately rerun through pointer UI.
- Artifacts recorded under `.build/stability-audit/Logs/Test/`; final shell result `Test-Notchium-2026.09.29_09-30-39--0400.xcresult`. `/tmp` logs are temporary and may disappear.

Prior September 28 evidence in `BEHAVIORAL_OWNERSHIP_FIXES.md`: full package suite 339 tests/zero failures; workspace UI run two tests/zero failures; 20/20 native Caffeine hold cycles; mock Reminder Return/Escape regression; live signed Safari and Chrome fullscreen reminder saves with context preservation. Earlier signed Reminder validation confirmed one real `presentation` reminder for September 29 at 18:00, reuse of permission across relaunch, and valid ordinary-title Add. Those passes precede September 29 media/slider changes and are not a claim that the latest entire suite was rerun.

Current live Spotify seek/volume were not requalified end-to-end in the latest pass; physical trackpad, actual hardware/per-app gain, fresh TCC Allow/denied recovery, desktop/additional Spaces save paths, VoiceOver, and sustained energy remain gaps. Latest Reminder save test was mocked; use the earlier live evidence with its date, not as a new real write.

Relevant suites include PlaybackPipelineTests, SpotifyMediaTests, MediaProgressTests, NavigationOwnershipTests, NotificationLifetimeTests, NotificationCoordinatorTests, Stage10CoordinationTests, AudioMixerTests, CalendarSelectionTests, CalendarReminderTests, ReminderNaturalLanguageParserTests, Stage11QuickActionsTests, UtilityControlTests, and NotchTransitionSurfaceTests. Standard package command recorded by the repository is `swift test --package-path NotchiumPackage`; app validation uses workspace `Notchium.xcworkspace`, scheme `Notchium`, My Mac/Debug. No configured linter was found in the recent validation notes.

## 27. Recommended Starting Point for New Agent

Use this handoff first, then perform the requested **full code / bug / performance audit before substantial further Stage 11 development**. A focused stability audit already exists; read its fixes and coverage limits instead of repeating failed approaches or claiming an audit has never happened.

Start with current source/HEAD and repository instructions, then the recent documents identified above. Trace one playback action, one Reminder save, one notification deadline, and one expansion session across the ownership boundaries. Preserve the four-page fixed shell, Home/manual navigation contract, Spotify-only scope, one-EKReminder rule, and black-only main animation.

Audit the unqualified boundaries deliberately: real supported Spotify device seek/volume and external changes; physical slider/trackpad interaction; Audio tap route/permission/recovery; stable signed TCC and ordinary/fullscreen Space behavior; performance under actual capture/mixing. Record reproduced defects separately from code risks and missing validation. Do not silently redesign or restore removed features.

Working-tree state observed before handoff: untracked `.DS_Store`, `Notchium.xcworkspace/.DS_Store`, `Notchium.xcworkspace/xcshareddata/`, and `default.profraw`. They were left untouched. This handoff is the only newly authored repository file.
