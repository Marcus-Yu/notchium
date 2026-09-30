# Stage 12 — Unified Live Activities

One arbitration system for every collapsed-notch activity. Provider truth stays in each
feature; `ActivityCoordinator` owns presentation policy only.

```
provider/service → feature state → NotchActivity / NotchNotification
  → ActivityCoordinator (key, priority, lifetime, primary/secondary)
  → DynamicIslandPresentationModel → shell (compact slot, banner, secondary chip)
```

## Model

- `NotchActivity.key` (`NotchActivityKey`) is the stable identity. Repeated events with the
  same key update one activity; they never stack. Notifications use their `coalescingKey`
  (`audio.level`, `audio.output`, `battery`, `calendar.<event>`, utility keys); Music uses `media.spotify`.
- `lifetime`: `.transient` (absolute deadline), `.persistent` (Music), `.condition`
  (reserved for provider conditions). Only transients have coordinator-owned deadlines.
- `minimal`: the secondary representation (`.artwork` or a compact glyph). Music publishes it
  only while its collapsed flanks are really visible (playing + live local audio).

## Arbitration (`ActivityPriorityPolicy`)

1. Transients interrupt baselines (Music). Music is never recreated by an interruption.
2. Among transients: higher priority wins; equal priority → latest meaningful update.
3. Interrupted and lower-priority transients stay live underneath until their own absolute
   deadline, then resume if time remains. Nothing expired is ever replayed.
4. Stable key breaks remaining ties.

Priorities are unchanged from Stage 9–11 (reminder5/lowBattery high; reminder30/60, output,
charging medium; volume/mute/utility low).

## Lifetimes

One generation-checked task serves every transient deadline. Deadlines are absolute
(`createdAt`/`expiresAt` from the injected clock), stamped per meaningful update, never paused by
hover, drag, expansion or page selection. Identical resubmissions do not extend them. Any
change reschedules under a new generation, so a stale wake-up cannot remove newer state.
Durations are the previously tuned `NotchNotification.Kind.defaultDuration` values.

`NotificationCoordinator` no longer owns a timer: `active` is the primary activity's notification.

## Primary + secondary

- Primary: the best-ranked live activity, or a user-promoted one.
- Secondary: one chip (`NotchSecondaryActivityChip`) beside a compact primary or visible Music
  flanks. Never beside downward banners (Music already stays in the top row) or replaceable
  low-priority HUDs (volume), never while expanded.
- Clicking the chip promotes it (role change only; no page change, no identity change). A promotion
  holds until the promoted activity ends or a new transient arrives.

## Navigation

Activity arrival, expiry and promotion never write `NotchPageModel.selectedPage`. Only clicking the
primary activity (explicit user navigation) opens its destination.

## Adding a future activity (downloads, screenshots, clipboard)

1. Provider/service emits typed state.
2. Feature maps it to a `NotchActivity` (or a compact `NotchNotification`) with a stable key,
   priority, lifetime and optional `minimal`.
3. Submit to `ActivityCoordinator`. No shell changes are needed for compact/side content.

## Not in Stage 12

Focus/DND and display brightness have no real providers in the current product
(`RealFocusService` is an unavailable skeleton), so no activity was invented for them.
Caffeine state is already visible in the expanded header; a permanent collapsed indicator would
add idle clutter and a toggle transient would be invisible (toggling happens while expanded).
