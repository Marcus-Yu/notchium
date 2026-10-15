# Display placement and independent notches

Implemented 2026-10-15. This replaces the original Stage 21 pointer-following, single-panel placement policy.

## Behavior

Settings → General → Displays contains:

- **Built-in display (Default):** stays on the MacBook's built-in display while the pointer, active app and primary menu bar move to another monitor.
- **All displays:** one shell per connected display. Hover, expansion, page selection and auxiliary interaction belong to each shell independently.
- **A named display:** shows only on that monitor. Public Core Graphics UUIDs preserve the choice across reconnects and changed online display IDs.
- **Create a notch shape on displays without a notch:** switches notchless displays from a compact pill to a top-attached notch scaled using the MacBook notch-to-display proportions in logical points. Without physical-notch hardware, the reference is 212 × 38 pt on a 1512 × 982 pt screen. Physical notches always retain measured hardware geometry.

A disconnected saved monitor temporarily falls back to the built-in display, then the primary/first available display. Reconnection restores the saved monitor. Closing the lid uses the available external display; reopening restores the built-in default. No screens means no shell panel. Sleep closes all interaction sessions, hides the panels and retains activity data until its existing deadlines expire.

## Ownership

`NotchDisplayPlacementPolicy` computes placements from immutable snapshots and persisted preferences. `NotchiumDisplayCoordinator` owns topology, native observations, reconciliation and selected sessions. Each `NotchDisplaySession` owns a separate `DynamicIslandPresentationModel`, page model and native panel. Geometry changes on the same display retain its session; assigning a different display closes the old interaction instead of copying expansion.

There is one authoritative activity source and one set of expiry timers. Each display projects the source entries through its own fullscreen/presentation context and has its own notification gestures. Dismissals forward to the source, preserving activity identity and avoiding duplicate lifetimes. Feature models, media polling and audio capture remain shared. Media-page visibility is aggregated by presentation identity so hiding or removing one display does not mark another visible player as hidden or cancel its Up Next refresh.

All pages retain the existing fixed expanded shell and native window behavior. Simulated notches draw their entire footprint; only physical notches exclude hardware pixels. Music reserves the central notch/pill width and renders its compact flanks outside that region.

## Verification

- Regression coverage: default built-in anchoring with an external primary/pointer, independent hover/expansion/navigation, shared activity identity/dismissal/deadlines, one expiry timer, per-display fullscreen suppression, persisted preferences, reconnect with changed online ID, recycled IDs, disconnect teardown, keyboard targeting, sleep/wake, proportional geometry, menu ownership and multi-display media visibility.
- The final combined display, geometry, menu, activity and media regression run passed **121 tests, 0 failures**.
- The final full package run executed 700 XCTest tests: **695 passed, 4 skipped, 1 failed**. The unchanged `Stage15StabilizationTests.testRemoteConnectPlaybackOpensHomeAndLocalOpensMusic` expects Music for local baseline playback, while the existing `ActivityCoordinator.preferredExpandedPage` returns Home. That policy and test were not changed by this feature. The separate Swift Testing run passed 5 tests.
- Debug and Release workspace builds passed with `CODE_SIGNING_ALLOWED=NO` on the My Mac destination using the macOS 27 SDK and the existing macOS 26 minimum. This checks compilation, not distribution signing.
- Native computer-use validation opened the built app, inspected the Settings layout and choices for the built-in Retina display and HP P27h G4, applied All displays and external-only placement, toggled notch creation, inspected the rendered external simulated notch, and expanded the external shell. The built-in default and disabled notch-creation preference were restored afterward.
- A focused XCUITest was added for the picker and notch-creation toggle. Its runner was killed before bootstrapping with unsigned and ad-hoc test builds; an intervening signing attempt required an unavailable provisioning profile. The test therefore did not execute. Native inspection above is separate evidence.
- `git diff --check` passed. Physical disconnect/reconnect, lid/sleep transitions and simultaneous interaction on both real screens still require a hardware acceptance pass; deterministic tests exercise these state transitions without changing the user's display configuration.

Build and test logs for this implementation are in `/tmp/notch-display-*.log`.
