# Focus, navigation, and Caffeine ownership

## Implementation

- Reminder focus stays inside the existing native popover (`window.makeKey` and SwiftUI focus). Removed `NSApp.activate` from popover attachment and from every expanded-panel reconciliation. Reconciliation occurs after page, activity, and reminder state changes; activating there defeated the nonactivating panel. Existing collection behavior already supports all Spaces and fullscreen auxiliary presentation, so it is unchanged. EventKit saving, parsing, permissions, and notification priority/duration policy are unchanged. The existing Reminder Added renderer now also uses the existing bottom notification slot while expanded; previously the confirmation expired invisibly behind the expanded page. This does not select or close a page.
- `NotchPageModel` owns an expansion session and records manual selection. Only `beginExpansion` chooses an automatic default; repeated requests, including reversal of a closing animation, preserve the current page. The session ends when the collapse transition completes, or on explicit nonanimated collapse/reset. Previously, the closing animation's target counted as collapsed immediately, allowing a reversed transition to choose Music again. There is no playback subscription writing page selection. Explicit notification activation remains a user navigation action.
- `CaffeineControlModel` owns `CaffeinePressInteraction`. A native AppKit view forwards down/drag/up into one monotonic press session. The prior SwiftUI implementation combined `GestureState` reset, drag completion, a view-local task, and fixed-boundary cancellation. Normal movement near the 28-point button boundary could cancel the session; reset callbacks could discard it before release handling. Native input adds 10-point movement tolerance and latches cancellation after dragging away. View updates retain the active session; actual removal or shutdown cancels it.
- Progress is elapsed monotonic time divided by 750 ms. The same task updates progress and invokes the hold once at the deadline. Mouse-up resolves that same deadline if its callback arrives first. Completed holds consume mouse-up; early releases perform only the normal click. Blue captures a click-only session. The border's existing shape, stroke, color, and feedback are retained; cancellation resets progress immediately.

## Automated validation

- Debug workspace app build succeeded.
- Swift package: 339 tests passed, including collapse reversal, completed-collapse reset, latest-click ownership, notification/activity churn, reminder save model tests, threshold progress, cancellation, click consumption, and Blue click-only handling.
- Twenty native handler sequences using real elapsed time: 20/20 BASE → BLUE before release. Each sequence includes slight movement and replacement of the input configuration while held. Release never toggled back; completion count increased once per hold.
- Existing default-page tests now explicitly complete collapse before asserting a fresh default. A separate test exercises interrupted collapse with the injected test clock.

## Files changed in this task

Sources under `NotchiumPackage/Sources`:

- `NotchiumQuickActionsFeature/QuickReminderButton.swift` (only removal of global activation; existing user edits retained)
- `NotchiumDynamicIsland/NotchiumPanelController.swift`
- `NotchiumDynamicIsland/NotchiumShellView.swift`
- `NotchiumDynamicIsland/Pages/NotchPageModel.swift`
- `NotchiumDynamicIsland/DynamicIslandPresentationModel.swift`
- `NotchiumDynamicIsland/CaffeinePressButtonStyle.swift`
- `NotchiumDynamicIsland/CaffeinePressInteraction.swift` (new)
- `NotchiumDynamicIsland/NotchUtilityControlling.swift`
- `NotchiumDynamicIsland/NotchSettingsButton.swift`
- `NotchiumCaffeineFeature/CaffeineControlModel.swift`

Tests under `NotchiumPackage/Tests/NotchiumFeatureTests`:

- `NavigationOwnershipTests.swift` (new)
- `UtilityControlTests.swift`
- `DefaultExpandedPageTests.swift`
- `Stage10CoordinationTests.swift`
- `ExpandedPageCompositionTests.swift` (test double protocol conformance)
- `NotificationLifetimeTests.swift` (test double protocol conformance)

Also `NotchiumUITests/NotchiumUITests.swift` and this document. Pre-existing edits to reminder models/services, Stage11 tests, and Stage11 documentation were preserved.

## Final acceptance results (2026-09-28)

- Final package run: **339 tests, zero failures**. Final workspace UI run: **2 tests, zero failures**, with the final source compiled by Xcode.
- **Caffeine real UI: 20/20 BASE holds reached BLUE**, each followed by a successful BLUE → BASE click. XCTest delivered actual pointer holds of 0.85 seconds. The separate native-handler test covers small pointer movement and view configuration changes, progress at 375 ms, deadline resolution, early release, cancellation, and no double action. An earlier UI attempt was interrupted by a foreground switch to Codex during a reset click; the uninterrupted rerun passed all 20 cycles.
- **Reminder UI regression: passed** autofocus, Return save, visible Reminder Added confirmation, composer dismissal, reopen, and Escape cancellation.
- **Safari fullscreen live save: context preservation passed.** Typed `test tomorrow 3pm` using autofocus and clicked Add. Composer closed, Home stayed selected, Safari remained fullscreen and frontmost. The save observation interval contained no activation or active-Space-change notification.
- **Chrome fullscreen live save: context preservation passed.** Composer autofocus, typing, Add, and dismissal completed with Chrome remaining frontmost; its 45-second observation log contained only initial/final Chrome entries, with no activation or Space change. No Reminders or Calendar activation was observed during either save.
- Two real test reminders were created: `test` and `Notchium Chrome test`, due September 29 at 3 pm. They were not deleted.
- **Navigation automation: passed** fresh defaults, manual page retention through activity/notification changes, rapid latest-click selection, interrupted collapse, and ownership reset after completed collapse. Live Home retention after reminder save was also observed. A full live Spotify track-change/pause-play and combined interaction sequence was not separately completed.
- **Normal desktop and an additional ordinary desktop Space: not fully verified.** The attempted desktop run was interrupted by a foreground/Space change before a save; it is not counted as passing. Safari and Chrome fullscreen were exercised in separate fullscreen contexts.
- `git diff --check`: passed. Existing Swift package and application compile checks passed; no new dependency or notification-duration change was introduced.

Motion review: the hold border represents elapsed time, has one 750 ms deadline, and resets immediately on cancellation. No page animation queue or main shell animation was added or changed. Existing notification content styling and lifetime are reused for expanded reminder confirmation.
