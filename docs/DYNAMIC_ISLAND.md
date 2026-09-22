# Dynamic Island — Stage 3

Stage 3 adds mock-only activity and page infrastructure. It connects no real feature services and does not begin Stage 4.

## State and ownership

`DynamicIslandPresentationModel.presentationState` is the authoritative presentation decision: `passive`, `expanded`, or `activity`. The existing Stage 2 `phase` retains hover/pin intent and its transition lifecycle. `surfaceState` maps the decision onto existing Stage 2 geometry; activities reuse the open shell without becoming pinned.

The presentation model owns one `ActivityCoordinator` and one `NotchPageModel`, shared by the shell and Developer Panel. A private Combine subscription bridges activity changes into the existing Observation-based shell. It does not copy activity payloads or introduce feature expansion flags.

## Priorities and queue

| Kind | Priority |
| --- | ---: |
| systemHUD | 10 |
| media | 20 |
| charging, audioDevice | 30 |
| download, screenshot | 40 |
| calendar | 50 |
| focus | 60 |
| battery | 70 |
| meeting, clipboard | 80 |
| notification | 100 |

`present(_:)` shows an event immediately when idle. A higher-priority event interrupts the active event, appending that event to the queue. Other incoming events append to the queue. On dismissal the highest priority wins; ties preserve queue insertion order. An interrupted event receives a new queue position at interruption. Repeated delivery of an existing UUID is ignored.

`dismissActive()` promotes the next event. `dismiss(id:)` removes either an active or queued event. `clearQueue()` leaves the current event intact; `clearAll()` cancels the timeout and removes everything. `dismiss(kind:)` supports mock Stop Media without removing unrelated events.

## Timeouts

The coordinator uses cancellable Swift concurrency tasks through the existing `AppClock` protocol. Each activation receives its full configured duration, including when an interrupted event resumes. Queued time does not consume that duration. A nil duration remains until explicitly dismissed. Cancellation and a generation check prevent an old task from dismissing a replacement event.

`TestAppClock(now:automaticallyAdvances: false)` registers sleepers until tests call `advance(by:)`. `waitForPendingSleeps()` synchronizes registration without wall-clock waiting. The default immediate-advance mode remains compatible with Stage 1 fixtures. No second clock protocol was introduced.

## Manual interaction and Spaces

- Passive plus activity displays the generic title/subtitle view.
- Stage 2 hover expansion and click pinning take precedence over non-critical activities.
- A priority-100 notification may visually interrupt expanded content. It leaves the manual phase and page model intact.
- Dismissal reveals the current manual state or returns passive.
- The existing Space-change handler additionally calls `clearAll()` before its existing collapse and panel reassertion. It clears pending activity timers/queue, closes and unpins, and never recreates or repositions the panel. Existing fresh-hover-entry behavior is preserved.

Geometry, hardware exclusion, panel positioning, fullscreen configuration, spring constants, hover delays, and content timing remain Stage 2 values.

## Pages

Shell page infrastructure lives under `NotchiumDynamicIsland/Pages`; the existing `NotchiumPagesFeature` declaration remains a future feature boundary. The shell does not gain dependencies on concrete product feature modules.

The current top-level order is Music, Calendar. `NotchPageModel` owns the sole selected page and supports enabled-list replacement/reordering and a preferred default. Disabled selections fall back to the enabled default or first enabled page. Duplicate entries are removed; an empty list normalizes to Music. `selectDefaultPage()` explicitly applies the preference.

A compact icon-and-label strip selects Music or Calendar. Music retains Player and Up Next inside its own page; Calendar has no media sub-navigation. Both feature views remain mounted during top-level switches, while only the selected page receives input and accessibility focus. Horizontal trackpad swipes and VoiceOver adjustable actions use the same page model. Settings and Close remain separate utilities. The expanded surface is 560 × 302 points inside a 740 × 322 host panel; collapsed geometry and the existing click-to-pin interaction remain unchanged.

## Developer Panel and future publishers

The DEBUG-only Activities tab contains every requested mock event, Stop Media, Clear Active Activity, Clear Queue, and live activity/priority/queue/page/pin/expanded values. Every event passes through the same coordinator. The prior disconnected synthetic-event buttons are replaced by this live harness. Mock definitions, controls, and the developer scene compile out of Release.

Future services should receive the coordinator through composition and publish immutable values on the main actor, using an injected UUID generator:

```swift
let id = await uuids.next()
activityCoordinator.present(NotchActivity(
    id: id,
    kind: .charging,
    title: "64% · Charging",
    subtitle: nil,
    priority: NotchActivityKind.charging.priority,
    duration: .seconds(3)
))
```

Services must not own shell expansion flags, control panels, or bypass queue/timeout policy. Real provider work and feature-specific activity designs remain later-stage work.

## Stage 3 verification

- 80 package unit tests pass, including priority/FIFO behavior, fake-clock expiry and cancellation, manual/page preservation, Space reset, page invariants, and activity-driven panel reconciliation.
- Debug and Release app builds pass with the installed Xcode toolchain. Release symbol inspection finds no developer-panel or mock-control types.
- Direct app inspection confirms normal launch, the expanded HOME placeholder, accessible navigation to MEDIA, and the existing close control.
- The Xcode UI suite could not execute: its runner was killed before establishing a connection, both unsigned and with local ad-hoc signing. This is an outstanding automated UI verification gap, not a passing UI-test result. Physical trackpad/Space/fullscreen hardware qualification remains manual.
