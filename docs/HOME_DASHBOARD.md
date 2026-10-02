# Home — Stage 20 customization

Home is a configurable single-screen dashboard. Default Home remains 524 × 266 with Media on the left and Calendar on the right, using a balanced 56/44 split and a subtle vertical divider. Shortcuts is an optional lower strip within the same 266 pt shell. When present, smaller artwork/date typography and tighter primary-region and divider spacing make room for the 47 pt strip footprint. Settings → Home → Customize Home is the editing entry point.

## Composition and ownership

`HomeConfiguration` is the versioned layout and shortcut value. `QuickActionStore` owns it for the application lifetime, using the existing local UserDefaults persistence approach. The configuration owns section visibility/order and shortcut metadata only. Existing Media and Calendar models, commands, provider lifetimes, progress estimators, and EventKit state remain unchanged. Home Media contains artwork, metadata, seeking, and transport only; Spotify Connect presentation and device discovery remain on the Music page.

The existing `NotchQuickActionsRendering` boundary projects enabled primary regions into the shell. Media and Calendar have fixed left/right positions; a single enabled primary region receives the available width. `HomeConfiguration.primarySections` separates those regions from the auxiliary shortcut strip. All-hidden Home offers guidance to Settings.

The shortcut strip renders only when the persisted shortcut-region toggle is enabled and at least one enabled user shortcut is pinned to Home. This condition comes directly from `HomeConfiguration.showsShortcutRegion`; there is no mirrored layout count. Zero visible pins render no strip, title, divider, placeholder, or reserved height. A fixed-height horizontal `LazyHStack` preserves compact tile styling and overflow scrolling. Media and Calendar do not gain scroll views. Stable UUIDs own shortcut identity; display names never own identity.

Home and every other page retain the shared 524 × 266 shell geometry and unchanged panel/pointer bounds. Shortcut visibility changes only interior composition: a presentation-only environment value selects compact Media/Calendar styling when the strip is present. First/last-pin changes use existing page motion, including Reduce Motion, without resizing the shell. Playback targets, seek interaction, Calendar content, and shortcut controls remain intact.

## Shortcuts and native execution

Stage 20 extends Stage 11's existing `QuickAction`, workspace adapter, Apple Shortcuts service, runner, and editor. It does not add a competing action model or execution framework.

Supported actions are Application, File, Folder, URL, Apple Shortcut, and System Action. The intentionally small system list is Open System Settings, Open Downloads, and Open Desktop. Applications use native icons and Launch Services with activation. Their bookmark plus bundle identifier supports moved/reinstalled apps without launching a different bundle at a reused path. File/folder references use bookmarks, with security scope for sandboxed builds and ordinary bookmarks for direct distribution, matching Shelf. Scope acquisition/release is balanced through the native open completion; stale references are refreshed.

URLs must have a valid scheme and target, with a host for HTTP(S). Credentials, whitespace/control characters, invalid escapes, local file URLs, and executable/script schemes are rejected. Other valid app links use the system's registered handler; unavailable handlers disable the tile. There is no embedded browser.

Apple Shortcuts uses Apple's existing fixed `/usr/bin/shortcuts` adapter with argument arrays, not a shell. Exact UUID/name identity is revalidated before execution; missing, renamed, or reused names cannot silently substitute a workflow. The existing service owns process cancellation and discovery timeout. Native Shortcuts permissions and the reduced sandbox profile remain platform qualification checks.

## Editing and reset

Customize Home uses a native Settings sheet. Primary regions have visibility toggles and fixed positions; a separate “Show shortcut row” toggle controls the auxiliary strip. Shortcuts supports add, edit, delete, enable, pin, and native list reorder with keyboard-accessible arrow alternatives. Edits retain their saved order. Existing items keep their action type; replacement is available through Add Shortcut rather than unsafe conversion. Optional SF Symbols come from a small built-in selection; files/apps use their native icons by default.

Reset Home Layout restores Media then Calendar, hides Shortcuts, and preserves every shortcut. No bulk shortcut reset or deletion accompanies layout reset. Individual removal is explicit.

## Persistence and migration

`home.configuration.v1` contains schema version, section order, enabled section IDs, and all shortcut data. No migration or rewrite is required for this refinement: legacy section order and unknown records remain stored losslessly, while the new projection places primary regions in fixed positions and shortcuts below. Stage 11's `quickActions.v1` and visibility key are migration inputs only; their bytes are retained, and the new record becomes authoritative. The independent reminder-list preference stays with Quick Reminder.

Missing optional fields receive defaults. Duplicate IDs/orders are normalized. Unknown section IDs remain stored but are not rendered. Shortcut records decode independently: malformed/unknown items stay opaque and survive subsequent saves while valid neighbors remain usable. Corrupt top-level data falls back to clean defaults and retains original bytes under a recovery key. A newer schema is read-only to prevent a downgrade from destroying configuration.

## Feedback, accessibility, and performance

Tiles use the existing dark Home surface, compact typography, consistent native/SF icons, hover/press feedback, explicit focus borders, and context menus. Success is an inline checkmark; failure includes a warning symbol, unavailable text, a descriptive hint, and editing/retry guidance. No shortcut launch creates an ActivityCoordinator event or expanded HUD. Running workflows expose cancellation.

Controls have meaningful labels, values, hints, and disabled semantics. Existing native press styling observes Reduce Motion; increased contrast strengthens borders. VoiceOver reorder actions complement the lists and buttons. Full keyboard navigation and spoken VoiceOver behavior require live macOS qualification, particularly because the notch preserves its existing non-key panel contract.

Bookmark/filesystem work runs in a dedicated actor. Icons are cached and never loaded from render bodies. Visible lazy-stack tiles prepare only when Home is open; offscreen pins do not need immediate resource resolution. Availability and Shortcuts discovery use a 60-second cache; concurrent discovery shares one owned task. Editing/explicit Refresh forces a recheck, and execution checks identity/access again. Collapse/hidden pages cancel view preparation; app shutdown cancels owned execution/discovery/feedback tasks.

## Non-interference and validation

Stage 20 makes no changes to automatic page arbitration, shell geometry, panel geometry, or activity priorities. Qualifying local Media still wins over running Pomodoro, then paused Pomodoro's exclusive 30-second grace, then Home. Manual selection remains owned by the user while open; remote Spotify and all unrelated pages retain their existing policies.

Focused tests cover defaults/hide/reorder/reset/relaunch, Stage 11 migration, per-item resilience, corrupt/newer schemas, shortcut CRUD/dense ordering, URL validation, availability/access denial, exact Apple Shortcut identity, caching, no transient/page changes, real bookmark restoration/missing resources, and native app resolution. Rendering checks cover default, Shortcuts, customization, add, unavailable, dense, and reordered states. QA images are opt-in through `NOTCHIUM_STAGE20_QA=1` and capture only default Home, one shortcut, and several shortcuts; ordinary Stage 20 tests leave no screenshots.

### Stage 20 verification results

The final focused pass runs 76 tests with no failures, including 20 new Stage 20 tests plus existing Home, Shortcuts, default-page, navigation, Pomodoro automatic-open, and display regressions. The broad package run executes 554 tests with one failure in `AudioMixerTests.testPermissionFailureIsPublishedWithoutLosingSavedGain`. A temporary baseline with all Stage 20 changes removed reproduces that same failure in its 535-test suite; its isolated AudioMixer tests pass. This pre-existing scheduler-sensitive test remains a follow-up outside Stage 20.

Debug and Release app builds use the workspace's Notchium scheme, macOS destination, isolated temporary DerivedData, and `CODE_SIGNING_ALLOWED=NO`. Native execution/signing qualification is distinct from compilation. `git diff --check` passes. Seven requested rendering states were inspected, with native live inspection supplementing compositor limitations in offscreen button captures. Live fixture checks verified Settings/customization/editor rendering, Return-to-save, accessibility labels/reorder actions, reset preserving shortcut data, and opening/canceling the native application picker. Actual app/file/folder launches, a user-approved real Apple Shortcut, spoken VoiceOver/full keyboard navigation, and live Reduce Motion/Increase Contrast still need platform qualification. Temporary baseline copies and QA screenshots are removed after inspection; the permanent regression tests remain.

### Targeted Home layout refinement — 2026-10-02

The former generic three-column composition is replaced by primary Media/Calendar regions plus an optional auxiliary shortcut strip. The visible shortcut header and Home-only Spotify Connect control are removed. Saved shortcut data, visibility, execution, editor, reorder, and legacy configuration bytes retain their existing ownership and persistence behavior.

Changed files for this refinement:

- Core and shared metrics: `HomeConfiguration.swift`, `HomeDashboardStyle.swift`, and the explicit internal design-system dependency in `Package.swift`.
- Home presentation and settings: `HomeDashboardView.swift`, `HomeMediaView.swift`, `HomeCalendarView.swift`, `HomeQuickActionsView.swift`, `HomeCustomizationView.swift`.
- Rendering projection: `QuickActionsModel.swift`, `NotchQuickActionsRendering.swift`.
- Geometry and motion: the temporary Home-specific sizing changes in `NotchPanelLayout.swift`, `NotchiumDisplayCoordinator.swift`, `NotchiumPanelController.swift`, and `NotchTransitionSurface.swift` were removed. These files retain their original shell behavior.
- Focused tests: `Stage20HomeTests.swift`, `Stage20PresentationTests.swift`, `Stage11PresentationTests.swift`, `DisplayCoordinatorTests.swift`.
- Documentation: this file and `ARCHITECTURE.md`.

Validation from the initial refinement: 139 focused tests passed, including first/last-pin changes preserving the same 266 pt shell while Home is open, dense overflow retaining one row, other-page geometry preservation, legacy persistence and shortcut execution, media controls/progress and Spotify device-transfer endpoints, Calendar rendering, and navigation/default-page ownership. Debug app build succeeds for `Notchium.xcworkspace`, scheme `Notchium`, macOS, with signing disabled and isolated temporary DerivedData. `git diff --check` passes. No linter is configured. Native fixture-window captures were inspected for zero, one, and several shortcuts; the compact primary row fits without clipped playback controls or event details and no shortcut header, empty strip, or Spotify Connect row appears. Automated geometry checks cover constant shell/pointer bounds during addition/removal; spoken VoiceOver, keyboard traversal, and live animation feel were not manually qualified in this pass.


The fixed-height follow-up removes the Home enlargement: expanded Home is always 524 × 266 pt, including zero, one, or many shortcuts. With shortcuts, artwork is 44 pt (normally 64), the date is 26 pt (normally 34), and typography/gaps/insets compact locally. The shortcut strip retains 34 pt controls and horizontal overflow. No persisted data or feature logic changes accompany this correction.

Fixed-height follow-up validation: 82 focused tests pass (Home configuration/rendering, display/coordinator geometry, Media controls/progress, Calendar rendering, and existing Home presentation), Debug app build succeeds, and `git diff --check` passes. The shared shell resolver, display coordinator, panel controller, and shell transition have no changes from their original fixed-size implementations.
