# Stage 5 Calendar activity

The `RealCalendarService` adapter owns `EKEventStore`, full-access authorization, calendar selection, event projection, and change notifications. It exposes value snapshots through `CalendarService`; EventKit objects never reach SwiftUI. `CalendarActivityModel` observes those snapshots and feeds `CalendarReminderCoordinator`, which schedules reminders through the shared `NotificationCoordinator`, owned by `ActivityCoordinator`. The shell receives Calendar views through `NotchCalendarRendering`, parallel to the media renderer. Music and Calendar views remain mounted across page switches; Player and Up Next stay within Music.

Calendar access is requested once at app startup through `requestFullAccessToEvents`. The app declares `NSCalendarsFullAccessUsageDescription` and the Calendar sandbox entitlement in both distribution profiles. Denial or restriction leaves Calendar empty and shows a System Settings button and the path to Privacy & Security → Calendars. Returning to Notchium refreshes authorization.

The initial selection includes calendars already configured in macOS Calendar. Identifiers are saved in UserDefaults when the user changes a selection. EventKit queries only selected calendars for the next 14 days and projects all non-cancelled events in that window, including active and overlapping events. The expanded view keeps the next event’s existing presentation and shows every remaining event in an internally scrollable list. No event content is persisted.

Calendar reminders appear at 60, 30, and 5 minutes before a timed event. A meeting can also show Join Now at its start. Each threshold is recorded once per event within the running app. On launch or wake after a threshold, the coordinator presents one reminder using the actual time remaining and marks older thresholds consumed. The soonest event wins; a higher-priority system activity suppresses a stale reminder rather than queuing it. Each banner lasts about five seconds, with the countdown paused while the pointer is over it. The reminder has foreground priority while collapsed Music remains rendered above it; dismissing it exposes the same underlying activity without restarting playback. EventKit is queried at launch, on database changes, day changes, wake, foreground activation, selection changes, and event approach/start/Now/end boundaries. The reminder coordinator uses one scheduled timer for the next threshold, and SwiftUI's one-second `TimelineView` updates only the expanded Calendar countdown.

Stage 9 routes Calendar reminders through `ActivityCoordinator.notifications`, the shared
`NotificationCoordinator`. The existing threshold scheduler, EventKit service, and Join
handler remain in Calendar. Notifications use a fixed 88 pt content area, a two-line
13 pt title, a 12 pt countdown, a trailing Join action, and a small persistent dismiss
target. Location and other event detail remain on the Calendar page. Five-minute/Now
Join uses white with black content; earlier Join uses a restrained glass control.
See [Unified notifications](STAGE9_NOTIFICATIONS.md) for geometry, motion, timing,
priority, accessibility, and validation. The older variable-height banner and its
centered action row are superseded.

Join appears only for HTTPS meeting URLs on recognized Zoom, Google Meet, or Microsoft Teams hosts with meeting-shaped paths. Detection checks `EKEvent.url`, then location, then notes. Join delegates to `NSWorkspace`.

Validation includes threshold/wake scheduling, media restoration, priority suppression,
shared hover expiry, Join URL dispatch, fixed-height title wrapping at 1×/2×, and native
SwiftUI raster fixtures. Real EventKit permission, user calendars, and external meeting
application handoff still require hardware verification.

## Inline upcoming-event selection

`CalendarActivityModel.selectedEventID` holds at most one expanded secondary event. It uses the existing UUID projection of EventKit’s calendar identifier, event identifier, and occurrence start date, never a row index. The service retains this mapping across refreshes; reordering or editing the projected title does not change selection. Snapshot reconciliation clears selection only when the event leaves the upcoming list. An event promoted to primary retains its identity and receives the existing primary presentation.

Clicking a full secondary row toggles its details; selecting another replaces the selection. Expanded rows show the time range, optional location (or meeting host), and the existing Join style when a detected meeting URL is present. The disclosure and Join are sibling buttons. Both primary and secondary Join resolve the event ID against the latest snapshot and use the same injectable URL-opening action; production delegates to `NSWorkspace`. Meeting parsing remains exclusively in `MeetingLinkDetector`. Reminders retain their existing dismissal behavior.

The selected row unfolds with a 250 ms smooth, non-bouncing animation (120 ms ease-out under Reduce Motion), a restrained background, and hover feedback. The list scrolls to reveal selection inside the unchanged 524 × 266 pt shell. No shell sizing or expand/collapse animation changes are involved.

Regression coverage models an in-progress Class, overlapping Interview with a different meeting URL, and a later Meeting without a URL. Tests cover independent selection, URL dispatch, toggling, refresh/reordering, removal, events beyond the previous list limit, and rendering inside the canonical page bounds. Live EventKit and external meeting-app handoff remain manual checks.

## Two-column expanded page

The fixed 524 × 266 pt shell is unchanged. Within 24 pt horizontal page insets and a 14 pt column gap, Calendar splits available width 54% main event / 46% upcoming events (approximately 249 / 213 pt). The left event uses a restrained clear glass surface, with an opaque Reduce Transparency fallback, a two-line 17 pt title, time range, countdown, optional location/provider, and the existing Join action. Events without Join center their content naturally within the same column.

The right column has its own scroll viewport. Light rows prioritize two-line 12 pt titles over metadata; secondary time ranges sit underneath. Selection reveals location/provider and a separate Join line, without changing either column’s frame. Titles truncate only after two lines and are never scaled down. Row expansion retains the existing selection model, animation, and latest-snapshot Join dispatch.

## Stage 10 coordination

Reminder priority comes from the centralized semantic table. An upward click-drag on
unused notification background dismisses at 32 pt, with a shorter intentional flick path;
partial/cancelled drags spring back. Join, the title button, and X retain their clicks.
Expanded reminders overlay the existing shell without resetting the page or event selection,
and yield to child menus/popovers. See [Stage 10 coordination](STAGE10_COORDINATION.md)
for gesture arbitration, motion review, restoration, and validation.
