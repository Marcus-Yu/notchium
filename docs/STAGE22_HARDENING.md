# Stage 22 — performance and reliability hardening

Audit date: October 3, 2026. Baseline: `d5694fc`. Host: MacBook Air, 16 GB, macOS 27.0.1. Swift language mode 6, complete concurrency checking. No geometry, layout, activity-ranking, animation constants, or feature flags changed. Stage 23 was not started.

## 22A — Baseline and measurement limits

The initial unchanged package suite passed 592 tests; the unchanged Debug workspace build passed. Source inspection covered the activity/presentation coordinators, panel/display controllers, media/provider/API/event paths, audio devices/processes/mixer/tap, transfers, screenshots, Clipboard, Shelf, Calendar, Pomodoro, Focus, Mirror, Home/Shortcuts, Caffeine and persistence. Resource declarations and recurring work were inventoried before fixes.

Instruments captures used Time Profiler, Activity Monitor and Allocations. The initially launched trace selected another installed build through LaunchServices and was excluded. Subsequent captures attached to the verified executable in the task's build directory. The user's existing running app was not stopped.

| Observation | Result and interpretation |
| --- | --- |
| Early 15 s fixture resource capture | Duration-weighted CPU 0.435%; footprint 37.89–37.91 MiB; 2 additional idle wakeups over 14.46 s. |
| Later baseline fixture capture | CPU 0.970%; footprint 38.75–38.86 MiB; 73 additional idle wakeups over 14.51 s. |
| Hardened fixture capture | CPU 0.641%; footprint 36.14–36.20 MiB; 129 additional idle wakeups over 14.54 s. |
| Baseline Home Time Profiler | 19 samples: 17 on the Core Audio IO thread, 2 elsewhere; silence checking/tap callbacks appeared in those samples. |
| Hardened Time Profiler | 305 samples, predominantly Main Thread. This was a different presentation/system-state window, not a comparable steady-state profile. |
| Closed-notch Time Profiler | No samples exported. This does **not** establish zero CPU. |
| Allocations | Recording completed, but no allocation tables were available in the exported capture. No leak-free or retained-allocation conclusion is claimed. |

These are short Debug-fixture observations, not production budgets or evidence of an idle CPU/energy improvement. The fixtures use mock services and do not enable every production feature; their media composition can still create a real Spotify audio tap. The older baseline process and fresh hardened process also had different lifetimes. The desktop locked during the session; accessibility could inspect/change some model state, but normal pointer actions failed and panels could collapse between observations. Accordingly, the captures do not certify smooth rendering or equivalent expanded Home states. Raw trace bundles, including recorded process environments, were removed after extracting aggregates.

### Requested scenario coverage

| Scenario | Evidence obtained; remaining measurement |
| --- | --- |
| Closed notch / expanded Home | Partial native CPU/footprint/wakeup captures above; repeat unlocked with stable presentation. |
| Spotify playing / paused | Real-provider scripted request, cadence, cooldown and reconciliation tests; live API/energy profiles remain. |
| One / concurrent downloads | Real Foundation Progress burst and existing terminal-order stress; sustained real-browser CPU/IO profiles remain. |
| Screenshot idle | Watcher/scan ownership audit and real temporary-directory detection tests; production filesystem counters remain. |
| Clipboard idle | Count-only polling audit, stale-decoder tests and storage counters; production wakeup profile remains. |
| Pomodoro running | Deadline/visible-cadence audit and deterministic timer suite; energy profile remains. |
| Mirror active / closed | 100 mock open/close cycles, deallocation, sleep/reopen and bounded runtime recovery; live camera/Allocations profile remains. |
| Sleep → wake | Notification-driven display/camera and existing system-change tests; physical sleep/wake remains. |
| Repeated open/close | 100 mixed presentation cycles and 100 overlapping NSPanel sharing/drag ownership cycles; pointer/Allocations verification remains. |
| Prolonged idle | Baseline fixture remained running for roughly 45 minutes; no continuous production long-session trace was obtained. |

## 22B — Performance and recurring-work audit

| Owner / work | Existing cadence and reason | Decision |
| --- | --- | --- |
| Spotify provider playback | Closed: playing 5 s, paused 15 s. Expanded: playing 2.5 s, paused 5 s, no media 10 s. Failures back off; 429 cooldown shared. | Preserve cadence and desktop-event coalescing. Session guards prevent obsolete reads/cleanup. |
| Spotify queue / devices / artwork | Queue refresh only on visible Up Next, 5 s; devices cached 30 s; small downsampled artwork cache. | Preserve caches and one provider truth. Reserve transfer before discovery so concurrent clicks cannot duplicate the command. |
| Clipboard | 0.5 s changeCount check, 0.2 s tolerance; payload only read on a change. | Preserve supported polling. Cancel stale image work; skip unchanged persistence and image cleanup. |
| Focus | 4 s only with the entitlement; unavailable one-shot otherwise. | Preserve public-API fallback; no private observer mechanism. |
| Pomodoro | Authoritative end timestamp; deadline task; 1 Hz visible timer/countdown presentation. | Preserve accuracy and approved grace periods; no hidden page timer added. |
| Transfers | KVO plus 250 ms progress flush only while changed/active. | Coalesce queued MainActor deliveries before creating Tasks; terminal evidence remains synchronous. |
| Screenshot | DispatchSource directory/candidate events plus incremental Spotlight updates; scans coalesce. | Reject replaced watcher/query callbacks. Directory name enumeration remains off-main because directory DispatchSource does not identify changed filenames. |
| Audio / battery | HAL listeners, local/global volume events and IOKit power source callback. Audio capture is required by playback activity policy. | Teardown listeners/event monitors/run-loop source; do not remove the tap's approved local playback signal. |
| Calendar | EventKit/day/wake events and next event boundary, 250 ms coalescing. | Add clock/timezone invalidation; subscriber-owned observation with latest-only snapshots. |
| Mirror | Capture only while preview is requested; blocking start/stop ordered on session queue. | Remove device/runtime/sleep observers when closed; cancel tasks and bound recovery. |
| Panel/display | Native pointer/display/Space/sleep events and transient gesture/deadline tasks. | No idle polling. Reject reconciliation while stopped/asleep. |
| Caffeine | Assertion/deadline; optional lid helper heartbeat every 5 s while its lease is active. | Preserve required heartbeat and explicit lease teardown. |
| Shortcuts/Home/Shelf | Shortcuts discovery cache 60 s, bounded 15 s process timeout; Shelf bookmarks resolved at restore/change. | Preserve event/on-demand work; balance every acquired security scope. |

Measured controlled improvements:

- 100 unchanged Clipboard page visits on baseline production code: **101 writes + 101 cleanup calls**. Hardened model: **0 writes + 1 initial cleanup**. Disk cleanup now indexes image IDs once and deletes set differences instead of enumerating on every save.
- A 10,000-write Progress burst queues **one mailbox delivery** while the MainActor is unavailable, rather than one Task per KVO update. Terminal results latch before any actor delivery. Single-run burst times were 69.336 ms baseline and 56.227 ms hardened; this is diagnostic evidence, not a statistical CPU benchmark.
- Clipboard/Pomodoro encoding and atomic file writes execute on dedicated utility serial queues. Saves enqueue immediately without a debounce; ordered reads and explicit shutdown flushes wait for preceding work. Stores should be flushed before handing their files to another store instance. An enqueued save is not a durability acknowledgment: abrupt process death before the queue drains can lose the newest update. Critical transaction-style callers need an explicit completion/durability boundary; graceful relaunch is tested.

No speculative FSEvents rewrite, polling-interval reduction, waveform redesign or broad rendering refactor was introduced.

## 22C — Concurrency and lifecycle

Mutable UI/application state stays on MainActor; provider state stays in its actor; synchronous KVO evidence stays in a Mutex mailbox; persistence state stays on its store queue; blocking AVFoundation operations stay on the serial session queue. No new unchecked Sendable escape hatch or detached task was added. Existing platform bridges retain their documented invariants.

Confirmed fixes:

- Invalidated Quick Look work could repopulate the cache after invalidation. Each in-flight request now has an identity; stale completion cannot populate or remove its replacement.
- Older Clipboard image decoding could overtake newer text or the app's own pasteboard write. Owned cancellation and generation/changeCount checks reject it.
- Camera sleep observation disappeared after stop/reopen. Observation now belongs to the requested preview lifetime and is reinstalled on reopen. Start/permission tasks are owned, runtime notifications identify the current session, and a broken camera receives one recovery attempt per explicit request/device.
- Repeated Shelf restore leaked security scopes: baseline 101 acquisitions / 1 release versus hardened 101 / 101. Teardown releases the exact URL acquired, even after bookmark resolution changes its path.
- Spotify transfer control was reserved after a suspending device lookup, allowing two simultaneous writes. Reservation precedes that suspension; post-await work and cleanup check session generation. A preceding shutdown is explicitly awaited before reconnect, and successive shutdowns are ordered.
- Calendar teardown/start now has an owned sequencing task. Last-subscriber teardown cancels deadlines/coalescing and removes observers. Audio device, transfer subscription and screenshot watcher callbacks carry lifecycle identity. Audio process/HAL, battery and panel owners clean up resources on destruction.

## 22D — Reliability and invariants

The existing activity authority, ranking policy and page-selection ownership were retained. A new 100-cycle test mixes Music, download progress, a persistent Pomodoro activity, Calendar, volume, screenshots, Focus suppression and expansion/collapse. It checks stable baseline IDs, Calendar priority and explicit Calendar-page ownership. Existing deadline, suppression, minor-HUD coalescing, secondary ranking and restoration suites also run.

Transfer coverage includes the existing **5,040 callback permutations / 15,120 transfers**, duplicate-name identities, completed/stopped/failed outcomes, metadata/finalization readiness, source reuse and unpublish races. The new real Progress burst checks that completion cannot become stopped after subsequent reset/cancel/unpublish. The synchronized terminal latch is unchanged in meaning; coalescing changes only delivery work.

Display tests ensure queued presentation changes cannot reshow a sleeping panel and restart clears obsolete sleep state. The native NSPanel test performs 100 overlapping Share/AirDrop/file-drag ownership cycles and checks restoration from current owners, rather than saved levels. It does not present actual system sharing sheets.

Camera tests perform 100 open/close cycles and verify model deallocation stops capture; sleep observation survives reopen; repeated runtime failure stops retrying; explicit reopen recovers. Permission/device-loss existing tests pass. Screenshot generation checks prevent scans from old targets and Spotlight notifications from old queries mutating current state. Missing/renamed watched directories are re-evaluated on their filesystem events. Calendar refresh also responds to clock/timezone changes.

## 22E — Memory

The thumbnail cache previously bounded NSCache values but retained an unbounded path-key index. The replacement LRU bounds both values and bookkeeping to 48 representations, includes scale in identity, and invalidates pending work. Tests cover eviction, scale and stale completion. The explicit bound trades away NSCache's automatic memory-pressure eviction; it retains only small Quick Look representations and does not change visible quality.

Existing artwork and Clipboard image downsampling/limits remain. Shelf scope leaks and camera/observer/task lifetimes were corrected. No Instruments Leaks or long-session retained-heap pass is claimed.

## 22F — Architecture cleanup

Changes clarify existing ownership rather than introduce another coordinator/state system. Provider generation owns request locks; stores own disk serialization; thumbnail cache owns bounded keys and request identity; preview owns camera observers; subscribers own native service observation. The obsolete unbounded thumbnail index and detached Clipboard decoder were removed. No duplicate geometry, new feature, dependency, cosmetic mass rewrite, or unrelated mixer change was made.

## 22G — Validation

Commands used the existing workspace/scheme, since the app's local package products are resolved through the workspace. The dedicated XcodeBuildMCP tool was unavailable; Xcode CLI was used. No configured standalone lint task was found. Debug and Release both compile in Swift 6 complete concurrency mode. Existing Focus async-alternative and AppIntents metadata warnings remain.

| Check | Result |
| --- | --- |
| Initial baseline full suite | 592 passed, 0 failed |
| Hardened full run before final three regression additions | 605 passed, 0 failed |
| Hardened 607-test full run | 605 passed; 2 intermittent mixer assertions failed |
| Full suite excluding mixer | 596 passed, 0 failed |
| Additional bounded camera recovery/lifecycle suite | 8 passed, 0 failed |
| Final full suite | 608 passed, 0 failed, 47.58 s |
| Mixed activity + cache stress | 15 passed, 0 failed at that revision |
| Unchanged baseline mixer repeated | Permission assertion reproduced in 4/20 runs; reset assertion reproduced in a separate unchanged-baseline run |
| Untouched baseline full suite plus counter fixture | 593 passed, 0 failed |
| Final Debug workspace build | Passed |
| Final Release workspace build | Passed |
| `git diff --check` | Passed |

The baseline mixer assertions wait exactly four `Task.yield()` calls, which do not establish completion of their asynchronous work. Both observed assertions were reproduced against unchanged production/test code. They were not hidden, suppressed in the full run, or fixed by changing mixer behavior.

Temporary benchmark logging, snapshot sources, raw profiling data and task-created processes were cleaned up. Regression fixtures remain only in the test target. Pre-existing untracked workspace files were preserved.

## Remaining issues

- The pre-existing mixer test synchronization failures remain (`testPermissionFailureIsPublishedWithoutLosingSavedGain`, line 163; `testResetRemovesTargetAndRestoresDirectAudio`, line 103). Passing runs do not resolve their intermittent behavior.
- `TransferActivityModel.finishedIDs` retains one tombstone per completed transfer until feature reset. Its five-item visible history is bounded, but the session tombstone set is not. Removing tombstones without a service acknowledgment/epoch contract would violate the no-resurrection invariant; no unsafe arbitrary eviction was added.
- Screenshot directory events still require coalesced name enumeration, and persistence reads/shutdown barriers can still block their caller. Their worst-case cost on very large directories/history or slow storage was not quantified.
- The requested complete Instruments/energy/network/retained-memory scenario matrix remains unverified because of locked-desktop access and unusable allocation exports. No general idle improvement, task-count reduction across the whole app, or leak-free certification is claimed.

## Manual checks

Use an unlocked desktop and the production configuration to verify stable closed/Home/active Media Time Profiler windows; idle, paused Spotify, running Pomodoro and Clipboard wakeups; live Spotify request/device/artwork counts; sustained concurrent browser downloads and target rename/disappearance; and a prolonged idle session.

Record Allocations/Leaks while actually switching Shelf/Clipboard, opening/closing Mirror, and presenting/cancelling Share/AirDrop. Verify the camera indicator turns off, real permission/device-disconnect paths, physical Finder drag-in/Shelf drag-out, full-screen/multiple-display panel behavior, hardware audio changes, network recovery, and real sleep/wake with clock/timezone changes. These require native system behavior beyond the deterministic fixtures.
