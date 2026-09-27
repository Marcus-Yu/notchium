# Stage 9 — Unified Calendar + Audio notifications

## Architecture

`ActivityCoordinator` owns `NotificationCoordinator` and remains the global arbiter for
persistent media and all activities. Calendar's boundary scheduler and Audio's existing
HAL snapshot callback submit `NotchNotification` values. The notification coordinator
owns one active value, one cancellable timeout, priority, coalescing, replacement, and
hover retention. Its activity has no duration, preventing a second expiry task in the
global coordinator. Global preemption/reset synchronously clears notification state.
Preempted and suppressed notifications are not queued for later replay.

The model contains identity, kind, priority, duration, dismissibility, coalescing key,
action, presentation style, and value content. Kinds are reminder60/reminder30/reminder5,
volume/mute/outputDeviceChanged. Calendar's existing meeting-at-start behavior maps to
reminder5 with its existing Now/Join Now text. There are no Music notification kinds.
Music's persistent media presentation, page, Home controls, and services are unchanged.

`UnifiedNotchNotificationContent` hosts the existing feature action adapters inside the
one persistent black `NotchTransitionSurface`. Animation presentation geometry stays in
that existing view layer; notification state does not introduce a global state machine.

## Priority and expiry

| Notification | Priority | Timeout | Coalescing |
| --- | --- | --- | --- |
| Calendar 5 minutes / Now | High | 10 seconds | Event ID |
| Calendar 30 / 60 minutes | Medium | 10 seconds | Event ID |
| Output device | Medium | 3 seconds | audio.output |
| Volume / mute / unmute | Low | 1.25 seconds | audio.level |

Higher/equal priority replaces directly without publishing an empty intermediate slot.
Lower priority is dropped without resetting the visible notification's deadline. Repeated
volume/mute values keep identity and layout, refresh content immediately, and reset the
single expiry task. A later volume event cannot inherit output-change priority.

## Geometry and motion

One opaque black, top-anchored path fills both the hardware region and notification.
Its 12 pt concave shoulders meet the screen edge and its 34 pt lower radii soften the
silhouette. No card border, separate backing, full-surface glass, or NSPanel resize is
introduced. Calendar uses the existing bounded width (356 pt on the built-in fixture;
340–380 pt unless hardware/media is wider), with 88 pt content below the hardware.
Audio uses at least 292 pt width and 56 pt content. Shared geometry determines pointer
retention too. Calendar uses 24 pt horizontal / 16 pt vertical padding, restrained system
type, a two-line title, a separate countdown, a trailing Join control, and a 28 pt X target.
Location and detailed information stay on the Calendar page.

| Motion | Parameters | Reason |
| --- | --- | --- |
| Notification entry / resize | interactiveSpring response 0.26, dampingFraction 1.0, blendDuration 0 | Physical continuity without bounce |
| Notification exit | interactiveSpring response 0.20, dampingFraction 1.0, blendDuration 0 | Faster upward contraction |
| Content reveal | Immediate at 75% of height growth | Readable before settling; fixed-size content |
| Content dismissal | Immediate | Never shrink/retract text |
| Equal-size content replacement | easeOut 0.10 seconds, opacity only | Avoid closing/reopening shell |
| Volume/mute repeats | Immediate content update | Frequent keyboard feedback must stay responsive |
| Reduce Motion | easeOut 0.12 seconds geometry | Short, non-spring feedback; no bounce |
| Main expansion | Existing response 0.40 / dampingFraction 0.80 | Unchanged |

Spring response is not a guaranteed wall-clock settling duration. Reversals retarget the
same SwiftUI animatable shape from its presentation geometry; generation tokens reject
superseded completion callbacks. No queued animation phases, scale transform, content
zoom, per-frame observable publication, or perpetual timer is introduced.

## Interaction and accessibility

The existing AppKit pointer monitor retains the whole notification, including its top
attachment, rather than just hardware bounds. It is the single pointer authority for
expiry; child hover events only change appearance. Entry pauses the remaining timeout;
leave resumes that remainder. Replacement while hovered remains paused. Join and X own
their clicks, while ordinary main-shell behavior remains unchanged outside notifications.
Calendar Join uses the existing validated URL opener and dismisses the shared slot.

X remains reachable without hover; the shell also exposes a named dismissal action.
Buttons have VoiceOver labels and Audio exposes its percentage/mute value. Five-minute
Join is white with black content. Early Join uses black text over a controlled 90%-white backing with clear glass as an
accent; Reduce Transparency omits glass. The black shell stays opaque.
No press or hover scale is used by the notification views.

## Separate design / animation review

Applied the requested skills in order:
[apple-design](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md),
[Apple HIG review](https://github.com/dickwu/apple-design-skill/blob/main/SKILL.md),
[animate](https://github.com/emilkowalski/skills/blob/main/skills/animate/SKILL.md), then
[review-animations](https://github.com/emilkowalski/skills/blob/main/skills/review-animations/SKILL.md).
The user's native SwiftUI shape requirement takes precedence over web-specific transform
recipes and their blanket keyboard-animation rule: initial shell expansion is retained,
while repeated volume updates do not animate the shell.

| Finding | Fix |
| --- | --- |
| Notifications inherited the main shell's bouncier spring | Dedicated critically damped entry/exit tokens; main motion unchanged |
| Old target mask could clip directly to an endpoint during reversal | Keep only the live interpolated geometry mask |
| Dismissal was hover-only and hidden from accessibility | Persistent restrained X plus named accessibility dismissal |
| Separate child and panel hover callbacks could disagree | One full-shell AppKit pointer authority |
| Early Join glass rendered too light for white text | Controlled light backing, black text, and a raster contrast regression |
| Calendar title/location changes could resize the banner | Fixed height, two title lines, details remain on the page |
| Cross-family replacement could replay stale feedback | Atomic replacement and no notification queue |

Native raster review covers Calendar 5/30 minutes, long titles, Join Now, Music flanks,
volume, mute, and output. Code/tests verify reveal threshold, current-shape clipping,
no content scaling, priority/coalescing, and stale-completion rejection. Raster tests
and synthetic samples cannot certify live animation feel or hardware frame pacing.

## Validation

Final result: **277 tests passed, zero failures** using `swift test --package-path
NotchiumPackage`. SwiftPM built every package feature target. `git diff --check` passed.
Dedicated tests cover priority without deadline reset, stable volume/mute identity,
hover remainder and replacement, global preemption/reset, atomic replacement, new input
after dismissal, connected rounded geometry and pointer bounds, reveal before settling,
exact Join URL dispatch, compact Audio rendering, and Calendar typography at 1×/2×.

XcodeBuildMCP is not exposed in this session; validation uses `swift test --package-path
NotchiumPackage`. No app archive/signing or live hardware acceptance is claimed. Real
volume keys/output switching, EventKit permissions and meeting-app handoff, VoiceOver,
notched-screen motion/interruptions, Spaces/fullscreen, and energy profiling remain manual
release checks. No linter configuration was found; `git diff --check` checks patch whitespace.

## Files changed

- `NotchiumPackage/Sources/NotchiumCalendarFeature/CalendarReminderCoordinator.swift`
- `NotchiumPackage/Sources/NotchiumCalendarFeature/CalendarReminderView.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/ActivityCoordinator.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/DynamicIslandPresentationModel.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/ExpandedTopSurface.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchAudioHUDView.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchNotification.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchNotificationGeometry.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchPanelLayout.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchReminderGeometry.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchTransitionSurface.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchiumPanelController.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchiumShellView.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotificationCoordinator.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/UnifiedNotchNotificationContent.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/CalendarReminderRenderingTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/CalendarReminderTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/ExpandedTopSurfaceTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/NotificationCoordinatorTests.swift`
- `docs/AUDIO.md`
- `docs/CALENDAR_ACTIVITY.md`
- `docs/NOTCH_SHELL.md`
- `docs/STAGE9_NOTIFICATIONS.md`
