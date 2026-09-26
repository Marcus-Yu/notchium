# Home — simplified Stage 8

Home is one fixed Music-and-Calendar surface inside the existing 524 × 266 expanded notch. Navigation remains Home | Music | Calendar | Audio. There are no Home scroll views, carousels, nested pages, or size changes when switching pages. Home does not install the horizontal page-swipe surface.

## Composition and ownership

`HomeDashboardView` allocates 62% of the available content width to Music on the left and 38% to Calendar on the right, separated by whitespace. The Music surface has a subtle dark fill and artwork; Calendar uses a lighter date-and-summary hierarchy. Both fit beneath the existing navigation within the canonical shell. Expand/collapse animation and panel mechanics are unchanged.

The shell receives Home renderers through the existing `NotchMediaRendering` and `NotchCalendarRendering` boundaries. The app's existing feature models retain provider ownership and state across page changes. No new service, duplicated playback model, or EventKit store is introduced.

## Music

Home uses `MediaSessionController.state`, including its retained paused/current track, plus authoritative connection state. It shows artwork, title, artist, a read-only progress indicator, Previous, Play/Pause, and Next. Progress uses the same position estimator as Music; its one-second timeline pauses when playback stops or the notch collapses. It does not poll Spotify.

Transport commands enter the existing `send` pipeline, including Previous's three-second restart/previous-track behavior and pending-command guards. Metadata and background open Music using sibling hit regions; playback buttons do not invoke navigation. Empty and disconnected states contain no invented metadata. Shuffle, repeat, queue, waveform, device, and volume controls remain on Music.

## Calendar

Home uses the current selected-calendar snapshot. A month/year heading and emphasized current day sit above one event summary. A small date-dependent projection excludes ended events, identifies whether relevant events remain today, and selects the next event by start time. It shows the event title with Today/Tomorrow/date context and time, or “No events today / Enjoy your free time.” Permission and unavailable states offer navigation to Calendar without falsely claiming a free day. The entire panel opens Calendar. Date context updates once per minute; EventKit remains unchanged.

## Default-page policy

On fresh expansion, `ActivityCoordinator.preferredExpandedPage` selects Music only for active playback or an active Music-specific transient. Otherwise it selects Home, including when Calendar or Audio was previously selected. Manual navigation remains untouched while hovered or pinned open. Explicitly clicking a transient still opens its declared destination. This simplification does not change that established policy or activity priorities.

## Scope and settings

There are no Home settings in this phase. The previous slot model, module sizes, layout persistence, quick-access/upcoming modules, window presets, snapping adapter, favorites, and snapping settings have been removed. Old experimental preference keys are no longer read; they cannot affect the fixed composition. Future customization can extend the feature-renderer boundary when separately scoped.

## Validation

`HomeDashboardTests` covers paused/cached playback command dispatch, navigation retention, today/upcoming/expired/all-day event projection, absence of native scroll views, and fixed-size rendering for populated, long-title, empty, disconnected, and tomorrow states. `DefaultExpandedPageTests` retains the established Music/Home priority coverage. `DisplayCoordinatorTests` exercises Home → Music → Calendar → Audio while asserting identical expanded and host-panel geometry.

Dashboard-only render fixtures exclude native glass navigation because ImageRenderer cannot capture the system compositor. Live Spotify playback, physical trackpad interaction, and real EventKit permissions remain hardware acceptance checks.

## Files changed by this simplification

Updated:

- `Sources/NotchiumDynamicIsland/Home/HomeDashboardView.swift`
- `Sources/NotchiumDynamicIsland/NotchMediaRendering.swift`
- `Sources/NotchiumDynamicIsland/NotchCalendarRendering.swift`
- `Sources/NotchiumDynamicIsland/DynamicIslandPresentationModel.swift`
- `Sources/NotchiumDynamicIsland/NotchiumShellView.swift`
- `Sources/NotchiumDynamicIsland/Pages/NotchPagesView.swift`
- `Sources/NotchiumMediaFeature/HomeMediaView.swift`
- `Sources/NotchiumMediaFeature/MediaShellContent.swift`
- `Sources/NotchiumCalendarFeature/HomeCalendarView.swift`
- `Sources/NotchiumCalendarFeature/CalendarActivityModel.swift`
- `Tests/NotchiumFeatureTests/HomeDashboardTests.swift`
- `Tests/NotchiumFeatureTests/DisplayCoordinatorTests.swift`
- `docs/HOME_DASHBOARD.md` and `docs/ARCHITECTURE.md`

Removed the earlier Home/snapping wiring from `Notchium/NotchiumApp.swift`, `Sources/NotchiumFeature/NotchiumApplicationController.swift`, and `Sources/NotchiumFeature/NotchiumSettingsView.swift`, restoring those files to their pre-Stage-8 composition.

Deleted the prior Stage 8 additions:

- `Sources/NotchiumDynamicIsland/Home/HomeLayoutModel.swift`
- `Sources/NotchiumDynamicIsland/Home/HomeSettingsSection.swift`
- `Sources/NotchiumFeature/HomeWindowLayouts.swift`
- `Sources/NotchiumServices/WindowLayoutService.swift`
- `Sources/NotchiumCore/WindowLayoutPreset.swift`

`Sources/` and `Tests/` above are relative to `NotchiumPackage/`. Unrelated existing workspace changes were preserved.

Verification: all 267 package tests passed; the Release package build, app-entry type-check, and `git diff --check` passed. Five rendered fixture states were inspected for clipping and layout balance.
