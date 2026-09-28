# Notification lifetime and icon header refinements

## Behavior

| Kind | Default lifetime |
| --- | --- |
| Calendar 60/30/5 minute reminder, including Join-capable reminders | 5.0 s |
| Output device / AirPods / speaker change | 2.5 s |
| Volume, mute and unmute | 1.75 s |

`NotchNotification.Kind.defaultDuration` owns the defaults. The coordinator records
`createdAt` and `expiresAt` using the injected app clock for each accepted update and
runs one cancellable expiry task. Hover and drag tracking never reschedule it. Calendar
reminders keep discrete identities; meaningful Audio changes update the existing slot
and refresh its deadline. Identical Audio snapshots do not extend it. Priority and
persistent activity restoration remain under ActivityCoordinator.

`presentedNotification` is the single compact-presentation decision. Expanded content
hides the banner but does not dismiss, pause or refresh the model. The normal activation
area takes precedence for pointer hover and clicks. Escape collapses the expanded UI;
when collapsed it can dismiss the visible notification. The obsolete expanded overlay
was removed. The existing 120 ms normal hover-entry forgiveness remains unchanged.

The header has four 28 pt icon buttons on the left and Caffeine, Keyboard Lock, Settings
and Close on the right. Close has an 18 pt structural gap. SF Symbols, native SwiftUI
Buttons, help tags, VoiceOver labels and selected traits replace visible captions.
Caffeine colors and 0.75 s hold behavior remain unchanged. Navigation uses neutral
background/outline contrast; utility controls retain the existing glass treatment.

## Design and motion review

Applied the requested [Apple design](https://github.com/emilkowalski/skills/tree/main/skills/apple-design),
[animate](https://github.com/emilkowalski/skills/tree/main/skills/animate),
[review-animations](https://github.com/emilkowalski/skills/tree/main/skills/review-animations),
and [macOS HIG skill](https://github.com/dickwu/apple-design-skill) guidance.
Local cached copies and HIG references were available in `/tmp`.
Relevant HIG references reviewed: accessibility, layout, typography, color,
designing-for-macos, buttons, motion and pointing-devices. Native `.help` and
accessibility-label behavior were checked through Context7's Apple SwiftUI documentation.

| Before | After | Why |
| --- | --- | --- |
| Banner blocks hover/click expansion | Normal activation area wins | Immediate normal interaction |
| Hover/drag retain remaining time | One absolute expiration | No stale banner after collapse |
| Expanded notification covers page controls | Compact presentation hidden while open | Full page stays usable |
| Hidden notification consumes Escape | Escape targets the visible shell | Predictable keyboard behavior |
| Labeled navigation capsules; utilities in separate overlay | Compact icon groups in one row | Clear navigation/action hierarchy |
| Glass-only selection was ambiguous in offscreen rendering | Explicit neutral background and outline | Clear selected state without saturated color |
| Utility press scales to 0.90, even with Reduce Motion | 0.97; no scale under Reduce Motion | Restrained feedback and accessibility |

Code/native-raster verdict: **Approve**. The existing interruptible shell spring,
notification geometry/reveal transitions, and Caffeine hold ring are preserved.
No new page-selection animation, stagger, blur or decorative effect was introduced.
Live fluidity and hardware frame pacing cannot be certified from code or still renders.

## Validation

- Full SwiftPM build and suite: `swift test --package-path NotchiumPackage` —
  **305 tests passed, zero failures**.
- After the final accessible grouping cleanup: `swift test --package-path NotchiumPackage
  --filter NotificationLifetimeTests` — **5 tests passed, zero failures**.
- Native AppKit-hosted header renders reviewed for all four selected pages.
- Regression coverage includes panel hover/click with Calendar and Audio, expiry while
  expanded, remaining lifetime after early collapse, output expiry under hover, Audio
  coalescing, duplicate-snapshot handling, drag expiry and discrete Calendar identities.
- `git diff --check` passed. No configured linter was found.
- XcodeBuildMCP was unavailable; SwiftPM compiled all package targets. No app archive,
  signing validation, live EventKit/audio hardware interaction, VoiceOver traversal,
  fullscreen/Spaces exercise or live animation recording is claimed.

## Files changed

- `NotchiumPackage/Sources/NotchiumCalendarFeature/CalendarReminderCoordinator.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/DynamicIslandPresentationModel.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/ExpandedNotificationOverlay.swift` (removed)
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchNotification.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchSettingsButton.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchiumPanelController.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchiumShellView.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotificationCoordinator.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/Pages/NotchPagesView.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/CalendarReminderTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/DynamicIslandPresentationTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/NotificationCoordinatorTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/Stage10CoordinationTests.swift`
- `docs/AUDIO.md`
- `docs/CALENDAR_ACTIVITY.md`
- `docs/NOTCH_SHELL.md`
- `docs/STAGE10_COORDINATION.md`
- `docs/STAGE9_NOTIFICATIONS.md`
- `NotchiumPackage/Tests/NotchiumFeatureTests/NotificationLifetimeTests.swift`
- `docs/NOTIFICATION_HEADER_REFINEMENTS.md`
