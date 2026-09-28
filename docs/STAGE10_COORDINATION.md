# Stage 10 — Multi-Activity and Gesture Polish

## Coordination and restoration

`ActivityCoordinator` exposes foreground, underlying, and transient activity without
copying or replacing the persistent playback model. `ActivityPriorityPolicy` is the
semantic priority table. Notification priority is derived from its kind, so callers
cannot accidentally make a volume update urgent. Generic activity family replacement
also rejects lower-priority input; volume can no longer inherit an output-change priority.

| Layer | Activity |
| --- | --- |
| High | Calendar five-minute / meeting-at-start reminder |
| Medium | Calendar 30/60-minute reminder; output-device change |
| Low transient | Volume, mute/unmute |
| Persistent baseline | Music playback, retained independently of every transient |
| Idle | Home when there is no playing Music default |

The Stage 9 notification slot still drops suppressed notifications instead of replaying
stale feedback. Replacement publishes no empty intermediate slot. Expiry has one
cancellable notification task with an absolute deadline. Pointer hover, drag and expansion
do not change that deadline. Dismissal carries an identity so a retiring gesture cannot
dismiss a different notification. Generic developer activities retain their existing bounded family queue.

Home, Music, Calendar and Audio view trees remain mounted. Hidden pages are disabled,
excluded from pointer hit testing, and hidden from accessibility. A transient does not
change page selection. Fresh expansion still chooses playing Music or Home; explicit
notification activation opens the requested destination. Music's Player/Up Next selection
is retained instead of being reset when an unrelated shell transition settles.

Collapsed Music remains rendered during Calendar **and** Audio entry, replacement and
exit. Only the notification content uses the reveal gate; the persistent media row stays
visible. The established black-only main expand/collapse is preserved. Audio width also
accounts for media flanks on wider hardware notches.

While expanded, compact notification presentation is hidden. The canonical 524 × 266
expanded size, page identity and selection remain unchanged. The notification model
expires in the background; closing before expiry reveals only the remaining lifetime.
Escape targets the visible shell first, and notification dismissal while collapsed.

## Gestures and motion

Dismissal is a native SwiftUI `DragGesture` on the notification's **unused background**.
Title/open buttons, Join and the dismiss X retain native control interaction. Mouse drag
and trackpad click-drag work; ordinary two-finger vertical scrolling is not redefined.
The persistent X and named accessibility dismissal remain available.

| Motion | Decision and behavior |
| --- | --- |
| Upward drag | Six-point recognition; upward-dominant direction; resisted travel asymptotically below 18 pt |
| Dismiss | 32 pt upward distance, or at least 14 pt plus an upward predicted endpoint past 56 pt |
| Partial/cancelled drag | `GestureState` resets with existing response 0.20 / damping 1.0 spring |
| Completed drag | Hold the released offset through removal; no downward snap-back before exit |
| Feedback | At most 12% opacity reduction; no scaling or flicked-card trajectory |
| Page swipe | Native AppKit phased precise scroll events; one page per sequence; ignore momentum and cancellation |
| Page movement | Four-point horizontal offset and opacity; response 0.20 / damping 1.0 |
| Page buttons/VoiceOver | Immediate selection without a custom navigation animation |
| Notification shell | Existing response 0.26 entry / 0.20 exit, damping 1.0; retarget current SwiftUI presentation geometry |
| Expanded notification | Existing 0.10-second content fade within the fixed shell |
| Reduce Motion | No drag/page translation; short opacity feedback and existing 0.12-second non-spring shell transition |

Horizontal navigation is deliberately limited to empty space **beside the page buttons**,
available on all four pages. The native hit-tested `NSView` replaces the old full-page
scroll-event monitor. It cannot receive slider, event-row, playback-button or menu input.
Horizontal intent locks after eight points; a 30-point sequence changes one page. Edges
stop at Home and Audio rather than wrapping. No global monitors, idle polling or gesture
timers were added. Native page buttons and accessibility adjustment are equivalent paths.

The shell continues to own one animatable shape with generation-checked completions.
There are no close-then-reopen phases. Notification input remains enabled during entry.
The new gestures only update while an interaction is active.

## Native interaction review

Native `NSMenu` tracking notifications and the existing auxiliary interaction handler
retain the shell for menus and the Spotify device picker. Retention is keyed by source,
so closing one nested child does not release another. Escape is scoped to this panel and
defers to child interactions, then dismisses a transient before collapsing the shell.
The feature retains its native buttons, slider values, system cursor and keyboard focus;
no custom cursor, global hotkey or broad high-priority gesture was introduced.

The source review used these requested skills, in order:
[apple-design](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md),
[macOS HIG](https://github.com/dickwu/apple-design-skill/blob/main/SKILL.md),
[animate](https://github.com/emilkowalski/skills/blob/main/skills/animate/SKILL.md), and
[review-animations](https://github.com/emilkowalski/skills/blob/main/skills/review-animations/SKILL.md).
SwiftUI gesture cancellation was checked against Apple's documentation through Context7.

Relevant HIG checks: `motion.md › Providing feedback` says “Let people cancel motion”;
`focus-and-selection.md › Best practices` says “Avoid changing focus without people’s
interaction”; `pointing-devices.md › Desktop (macOS) › Pointers` identifies the arrow as
the standard selection/interaction pointer. Existing native focus and cursor behavior
are retained. The user's requirement to preserve the black shell takes precedence over
web-specific transform-only recipes and the existing main-shell spring is unchanged.

| Before | After | Why |
| --- | --- | --- |
| Whole-page scroll monitor could observe controls | Hit-tested empty navigation region | Controls own their input |
| Home was conditionally removed | Stable page trees, inactive controls disabled | Preserve state without hidden keyboard targets |
| Audio hid Music's compact row | Compatible combined presentation | Restoration is a visibility change, not a reload |
| Notification reveal gate also hid media | Separate persistent-row visibility | No media flash during entry or exit |
| Initial preservation logic could leak media during main collapse | Preserve only compatible collapsed transitions | Keep the established black-shell behavior |
| Completed drag could reset while retiring | Hold its committed displacement | No exit snap-back |
| Spotify picker did not retain the shell | Shared auxiliary retention and child-first Escape | Native interaction continuity |
| Device picker scaled even with Reduce Motion | Opacity-only transition | No unnecessary zoom |
| Expanded Home received no visible Audio feedback | Unified strip in the existing shell | Cover the expanded restoration acceptance case |
| Expanded strip could cover a child picker | Yield overlay and pointer region to auxiliary interaction | Menus/popovers retain precedence |
| Same-family lower priority could displace/borrow urgency | Reject the downgrade | Priority remains semantic |

Code/raster motion-review verdict: **Approve**, with physical feel and hardware pacing
still requiring hands-on validation. No claim of live trackpad, VoiceOver, Spaces or
fullscreen testing is made. The compact banner is now hidden while expanded; page controls and child menus remain available.

## Validation

Final command: `swift test --package-path NotchiumPackage` — **298 tests passed, zero failures**,
including 21 new Stage 10 tests. `git diff --check` passed. SwiftPM
compiles all package feature targets; it is not an app archive/signing check. XcodeBuildMCP
is not exposed in this session. No linter configuration was found. The regression tests
cover semantic priority, state/selection restoration, drag thresholds and cancellation,
stale dismissal, one-page navigation, control hit testing, nested/native menus, idle task
cleanup, expanded overlay restoration and media continuity raster samples. Existing
Calendar Join, Audio, Spotify, utilities and main-shell tests remain in the full suite.

Physical trackpad feel, actual keyboard focus/VoiceOver traversal, Spotify device handoff,
EventKit delivery, real audio hardware, full-screen/Spaces behavior and CPU/energy profiling
remain manual checks. Zero pending tasks in the idle test is an event-driven invariant,
not a measured CPU result.

## Files changed from the starting Stage 9 working tree

- `NotchiumPackage/Sources/NotchiumCalendarFeature/CalendarReminderCoordinator.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/ActivityCoordinator.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/ActivityPriorityPolicy.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/DynamicIslandPresentationModel.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/ExpandedNotificationOverlay.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchActivityKind.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchAudioRendering.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchGesturePolicy.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchNotification.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchNotificationGeometry.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchTransitionSurface.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchiumPanelController.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchiumShellView.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotificationCoordinator.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotificationDismissModifier.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/Pages/NotchPageModel.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/Pages/NotchPageSwipeSurface.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/Pages/NotchPagesView.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/UnifiedNotchNotificationContent.swift`
- `NotchiumPackage/Sources/NotchiumMediaFeature/MediaViews.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/ActivityCoordinatorTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/NotificationCoordinatorTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/Stage10CoordinationTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/Stage10GestureTests.swift`
- `docs/AUDIO.md`
- `docs/CALENDAR_ACTIVITY.md`
- `docs/NOTCH_SHELL.md`
- `docs/STAGE10_COORDINATION.md`
