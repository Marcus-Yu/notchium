# Stage 11 — Shortcuts, Quick Actions, and Quick Reminder

Keyboard Lock is removed from the header, feature catalog, service registry, package targets, flags, and tests. Its session event tap, health timer, emergency chord, permission prompts, and implementation are deleted. Shared permission contracts remain available to other integrations. Caffeine is unchanged.

## Ownership

- `NotchiumCore/QuickAction.swift`: exactly five action kinds, persistent action values, stable shortcut identity, reminder drafts, Gregorian date components, and deterministic half-hour rounding.
- `NotchiumPersistence/QuickActionStore.swift`: versioned local preferences, ordering, four-pin limit, default-off Home setting, default reminder list. Unreadable saved actions are preserved and edits fail with guidance instead of overwriting them.
- `NotchiumServices/ReminderService.swift`: EventKit reminder authorization, writable list projection, default-list fallback, creation of one EKReminder. No EKEvent is created.
- `NotchiumServices/ShortcutService.swift`: Apple CLI discovery and execution, exact name plus UUID validation, cancellation, bounded discovery, and mocks.
- `NotchiumServices/QuickActionWorkspace.swift`: native selection, bookmarks, file icons, and NSWorkspace execution.
- `NotchiumQuickActionsFeature`: reminder model/composer, action runner, native Settings list/editor, and optional Home strip.
- App composition injects services and presentation adapters; the shell knows only `NotchQuickActionsRendering`. No new major activity or page is introduced.

## Quick Reminder

The icon-only checklist header button has a Quick Reminder tooltip and accessibility label. It opens a native SwiftUI popover, enters the shell's existing auxiliary-interaction retention mechanism, and gives the title field focus. The notch remains expanded while the popover owns interaction. The popover alone requests key focus; the notch panel remains nonactivating.

Each opening defaults to today without a specific time. Enabling At Time selects the next half-hour, preserving a separately chosen day; midnight advances today's date as appropriate. Native date/time controls are used. Return saves a valid draft, Escape cancels, and an unsuccessful save retains the title with an inline error. Outside dismissal retains unsaved text for reopening.

Opening Quick Reminder or choosing Enable Quick Reminder first reads EventKit authorization. Only `notDetermined` requests access; concurrent callers share one in-flight request. Full access immediately loads writable lists; denied/restricted states never request again. macOS/TCC is the authority, with no local permission flag. The application-owned reminder model retains one service and its single event store across popovers and page changes. Active composers refresh on app activation and EventKit changes. Settings offers writable lists plus System Default. Both validation and save prefer the configured writable list, then the writable EventKit default, then the first writable list. No Settings visit is required. All-day reminders omit hour/minute/second and time zone; timed reminders include local time and time zone. Both carry a Gregorian calendar as required by EventKit. Calendar can display this same scheduled reminder when its Scheduled Reminders option is enabled.

`canSaveReminder` is computed from the meaningful title, valid due date, valid time when enabled, full access, selected writable list, and absence of an in-progress save. DEBUG diagnostics on opening and validity changes include authorization, raw/effective titles, date/time, writable-list count, selected list, saving state, and the disabling reason. Personal values remain private in unified logging. No frame polling or manually cached button state is used.

Development permission testing must use the existing Apple Development signing configuration and stable `com.marcusyu.notchium` identity. Stop older development processes before launching a new build. Do not substitute an unsigned/ad-hoc temporary app for the signed app when testing TCC persistence. The September 28 investigation found both running simultaneously, with different designated requirements and TCC signing-attribution errors for the temporary app. The old signed process reported no Reminder permission even though the TCC request returned allowed; a clean signed process loaded the list and saved successfully. This establishes the observed authorization failure, but does not prove which process or OS cache caused the stale status. The plist purpose string and calendar personal-information entitlement were already present; no unrelated entitlement or build-time permission reset was added.

### Quick Reminder refinements

The four header controls share `NotchUtilityLabel` (28-point circular surface, 13-point medium symbol, neutral light foreground) and the existing press response. Caffeine retains its hold action and active colors. Reminder uses a neutral selected surface and an Open/Closed accessibility value. The composer explicitly resets the shell's white foreground to semantic `Color.primary`; secondary guidance and native text/date/time controls adapt to appearance. Native popover sizing, focus, Return/Escape, and feedback are retained. Parsing adds no animation or confirmation card.

`ReminderNaturalLanguageParser` is local Foundation-only. It uses NSDataDetector where explicit-date detection agrees with validated calendar components, and deterministic rules for relative days, weekdays, dates, and times. It accepts a reference date and calendar; no network, AI, private APIs, or dependencies are involved. The model debounces through the injected AppClock for 250 ms, with view-task cancellation and stale-input checks. Save resolves the latest text immediately, including before debounce completion. Session revisions and cancellation invalidate pending work on dismissal; repeated Add/Return actions share one save task. Manual time defaults use a fresh clock reading and an edit revision so later edits win.

Supported confident suffixes: today/tomorrow; full English weekdays with optional this/next; English full or three-letter month plus day and optional four-digit year; month/day with optional four-digit year; 12-hour am/pm times with optional space/minutes; 24-hour hour:minute. A date may precede a time with optional “at”; “on” before a date is removed with the suffix. Text elsewhere is preserved. Unsupported, partial, and non-suffix expressions leave controls unchanged. A recognized date followed by an invalid time updates only the date, retaining the current time setting and the invalid time text. Unsupported qualifiers such as “last” and “every” are not reinterpreted as bare weekdays.

Bare weekdays always mean a strictly future occurrence, including seven days later on the same weekday. “This” means the upcoming occurrence including today. “Next” means the named day in the next calendar week, using the user's firstWeekday (for example, on Sunday September 27, next Monday is September 28 in a Monday-first calendar and October 5 in a Sunday-first calendar). Dates without years use this year, advancing one year if already past. A time alone uses Calendar.nextDate for its next future occurrence in the user's zone, advancing to the next valid time across a DST gap. An explicit date with a nonexistent DST time is not inferred.

Manual date/time/toggle edits suppress the current temporal signature, including edits made before the pending debounce resolves. Title-only edits preserve that override; a new recognized temporal phrase releases it. Temporary incomplete text and equivalent time formatting preserve the override. Date-only suggestions leave At Time off unless manually enabled. Parsing never changes visible input. Save removes only the confidently recognized suffix and connector; a temporal-only input has an empty effective title and cannot be saved. Failed saves retain the full draft. EventKit still saves exactly one EKReminder through the existing list/permission path.

Refinement review:

| Before | After | Why |
| --- | --- | --- |
| Reminder bypassed header chrome | Shared utility label and press style | Consistent size, contrast, hover, and press response |
| Composer inherited shell foreground | Explicit semantic primary text | Adapts to light/dark materials |
| Any At Time change reset the time | Defaults run only for manual enabling | Parsed times survive native picker updates |
| No temporal assistance | Debounced model/parser with manual precedence | No cursor movement or picker fighting |
| Potential decorative feedback | Native controls update without added motion | Maintains focus and restrained density |

Refinement validation is recorded separately from the original Stage 11 validation below. Regression coverage includes phrase spellings, weekday/week boundaries, invalid/Unicode input, DST, time-only rollover, manual overrides, debounce cancellation, immediate saving, and failure retention. Bitmap render fixtures do not reliably capture native control/glass layers; they are not sufficient to certify runtime contrast or VoiceOver behavior.

## Shortcuts and native actions

Discovery uses `/usr/bin/shortcuts list --show-identifiers`. It runs when Settings/editor opens, on manual refresh, or when active Settings receives app activation; there is no polling. Actions store both the UUID and exact name. Before running, discovery verifies both and execution uses the UUID with `shortcuts run -- UUID`. Renamed, deleted, or replaced shortcuts require explicit reselection. No fuzzy matching or private database access occurs. The subprocess has no shell, input stream, or retained workflow output. Discovery times out after 15 seconds; action runs remain cancellable from Settings and app shutdown.

Application, File, and Folder use NSOpenPanel and read-only security-scoped bookmarks. Resolution checks existence/type, refreshes stale bookmarks, and balances access with `defer`. Applications use `NSWorkspace.openApplication`; files/folders use their normal workspace handler. Websites accept valid HTTP(S) URLs without embedded credentials and use the default handler. The Store profile includes app-scoped bookmark entitlement; Shortcuts CLI compatibility in sandboxed distribution remains a release validation item.

Settings uses a native List, selection, sheet, Picker, Toggle, context menus, and onMove drag reordering. Actions can be named, enabled, pinned, edited/relinked, and removed. Automatic icons use NSWorkspace for local resources and symbols otherwise; users can choose a symbol override. Home has no drag/reorder behavior. Its optional fixed bottom strip displays all four pinned actions at once. Editing from Home routes to that action in Settings.

## Feedback and performance

NotificationCoordinator handles success (1.5 s), reminder creation (2 s), and failure (3 s), all low priority. Calendar reminders win. Identical visible successes coalesce without extending their deadline. Feedback has no navigation destination and does not collapse the notch. A small progress indicator appears only after 350 ms; no button pulsing or custom popover animation is introduced.

No reminder polling, shortcut polling, permanent subprocess, new frame loop, or background work from the disabled Home strip is introduced. All file scopes are balanced, running tasks are cancelled on shutdown, and discovery output files are private and removed. Idle CPU equivalence requires hardware profiling; source inspection alone is not a measurement.

## Review

Reviewed using the requested Emil Apple/design/motion guidance, Apple HIG skill, UI/UX Pro Max for density only, and Anthropic composition guidance. Native macOS conventions take precedence over web animation recipes.

| Before | After | Why |
| --- | --- | --- |
| Generic HUD destination defaulted to Audio | Utility feedback explicitly disables the default destination | Keeps the underlying page selected |
| Name-only shortcut identity | UUID plus exact name, execution by UUID | Prevents running a different shortcut after replacement or rename |
| Immediate spinner risk | Delayed small ProgressView | Avoids flashing feedback on immediate actions |
| Missing target could lose context | Configuration retained with Edit/Relink path | Supports repair without recreation |
| New visual effects unnecessary | Native controls and system popover transition | Preserves platform focus and motion behavior |

Motion code review: approve the restrained implementation; runtime focus and rendering checks are recorded below. Native controls provide standard labels, focus behavior, Return/Escape, tooltips, and context menus. Home fixtures verify fixed geometry and no NSScrollView.

## Validation

The macOS app Debug build succeeds. All 313 package tests pass, including 12 Stage 11 regression/render tests, with no compiler warnings in the final package run. `git diff --check` passes. Native XCUITest was attempted with both unsigned and locally signed runners; macOS killed the runner before it established its test connection, so these two tests remain unverified. A direct mock-app check confirmed the native popover, automatically focused title field, and Return dismissing the composer after save with Home still selected. Native Settings and four-action Home fixtures were rendered and inspected; actual system popover rendering was inspected directly because bitmap captures do not reproduce every native control layer. Regression coverage includes date-only/timed components, midnight rounding, permission denial, text retention, list fallback, persistence, reordering, pin limits, URL rejection, shortcut rename/replacement protection, native workspace dispatch, notification durations, priority, coalescing, and page retention. Debug-only UI fixtures use mock reminders/shortcuts and separate preferences; they do not create personal reminders or run user workflows.

Remaining manual release checks: real EventKit grant/revocation and actual Reminders/Calendar visibility; file relocation/relaunch under the signed shipping app; real shortcut execution/cancellation; VoiceOver and full keyboard traversal; fullscreen/Spaces popover behavior; energy profiling; reduced Store-profile CLI support.

## Changed files

Added core models, the three services, QuickActionStore, the seven files in NotchiumQuickActionsFeature, NotchQuickActionsRendering, debug-only Stage11Fixtures, two Stage11 package test files, and this document. Updated Package.swift; app Info.plist and Settings composition; App Store bookmark entitlement; feature catalog/flags/service registry/fixtures; shell header, Home, page renderer, activity destination policy and notification feedback rendering; relevant architecture/permission/Home/shell documentation; obsolete Keyboard Lock tests and new native UI tests. Removed the Keyboard Lock service and its two feature files. Fixed the existing split-token typo in NotchShellDebugModel that blocked compilation. Pre-existing Stage 9/10 and layout edits were preserved.

### Refinement files

- `Sources/NotchiumDynamicIsland/NotchSettingsButton.swift`
- `Sources/NotchiumQuickActionsFeature/QuickReminderButton.swift`
- `Sources/NotchiumQuickActionsFeature/QuickReminderModel.swift`
- `Sources/NotchiumQuickActionsFeature/ReminderNaturalLanguageParser.swift`
- `Tests/NotchiumFeatureTests/ReminderNaturalLanguageParserTests.swift`
- `Tests/NotchiumFeatureTests/Stage11QuickActionsTests.swift`
- `Tests/NotchiumFeatureTests/Stage11PresentationTests.swift`
- This document. Source/test paths above are relative to `NotchiumPackage`.

Correction validation: macOS Debug workspace build passed; 25 focused parser/model tests passed. The full package run executed 327 tests with one failure in the pre-existing `DynamicIslandPresentationTests.testRapidReversalsSettleAtLatestTarget`; that test passed on isolated rerun. No notch animation code was changed for this refinement. `git diff --check` passed. The earlier native light-appearance mock-app check verified readable composer controls, unchanged typed text, Friday October 2 at 3 PM parsing, manual Saturday override after title edits, Return save, and consistent inactive header surfaces. The final dark-appearance runtime check and VoiceOver traversal remain unverified; bitmap fixtures alone cannot certify those behaviors. Xcode emitted only the unrelated AppIntents metadata-extraction warning.

### Disabled Add correction

The prior `canSave` checked only cached permission, raw nonempty text, and `isBusy`. With nonempty input and no active save, a stale permission value was its only disabling condition. The composer did not observe permission changes after preparation. The adapter now publishes EventKit store changes and app activation; the model subscribes while composing and refreshes permission and writable lists without polling or resetting the draft. Request completion also refreshes the current service snapshot, including after errors. Default writable lists come first, with the selected list preferred and the first writable list used as fallback.

Validation and persistence share the effective title: confident parser cleanup, otherwise trimmed raw input. The parser now returns the actual empty cleanup for temporal-only input; date/time recognition and calendar semantics are unchanged. `canSave` requires that title, permission, a writable list, finite valid Gregorian due components, hour/minute when timed, and no pending save. The busy guard starts before the asynchronous clock read; failure/cancellation releases it. Add is a native prominent button, and both pointer and Return call the same guarded save path. No layering workaround was needed in source inspection: the focus bridge is a background, with no composer overlay or gesture over Add.

DEBUG-only event-driven validation logs include private title/list/date fields and a public disable reason. They run on access changes, debounced input handling, and submission, never on an idle timer. The live user's original permission snapshot was not captured, so stale access is a reproduced state-path defect rather than a confirmed diagnosis of that specific running instance.

Changed: QuickReminderModel.swift, QuickReminderButton.swift, ReminderNaturalLanguageParser.swift, ReminderService.swift, Stage11QuickActionsTests.swift, ReminderNaturalLanguageParserTests.swift, NotchiumUITests.swift, and this document.

Validation for this correction: 29 focused reminder/parser tests passed; the full Swift package suite passed all 331 tests. The macOS workspace Debug app build and UI-test target compilation succeeded. `git diff --check` passed; no lint configuration was found. Acceptance A–E pass at the model/mock-service boundary, including effective saved titles, date/time, manual entry, temporal-only rejection, permission/list refresh without reopening, failure retry, and duplicate prevention. Acceptance F has a native UI regression test, but the runner was killed before establishing its test connection (early unexpected exit). Direct UI automation also failed to operate the isolated shell reliably, so mouse/Return runtime acceptance and real EventKit writes remain unverified. No real reminders were created.

### September 28 authorization validation

- Signed Debug workspace build succeeded (Notchium / My Mac); deep/strict code-signature verification passed. XcodeBuildMCP was unavailable, so the installed Xcode CLI performed the build.
- All 333 package tests passed, including 31 focused reminder/parser tests. Coverage includes grant-to-list readiness, repeated sessions, a fresh model using existing permission, denial/restriction without requests, activation/list changes, manual overrides, failed-save retry, and duplicate prevention. `git diff --check` passed. Only the existing AppIntents metadata warning appeared in the app build.
- In the signed app, entered `presentation tuesday 6:00 pm`, activated native Add, and confirmed Apple Reminders contains `presentation`, due Tuesday September 29, 2026 at 6:00 PM local time. The composer closed and reopened empty. No additional reminder was saved during subsequent checks.
- Reopening after notch collapse and quitting/relaunching reused permission without a prompt. `buy milk` enabled Add with today's default date.
- For the separately requested first-use test, quit the app and manually reset only its Reminders permission. This was an acceptance-test action, not application/build code. The system permission-dialog host is blocked by the computer-use tool; the fresh Allow transition and live denied-to-Settings recovery still require the user's response. Those paths have automated model coverage, but are not yet certified against a fresh system grant.
