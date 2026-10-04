# Stage 21 — Display and presentation intelligence

Implemented on top of the uncommitted Stage 22 hardening work. One display coordinator, one activity coordinator, one native panel and one page session remain authoritative. No new activity types, settings, external island or unrelated UI were added.

## File map

| Boundary | Files |
|---|---|
| Display state and native identity/geometry | `DisplayPresentationState.swift`, `NotchiumDisplayModels.swift`, `NotchiumDisplaySource.swift` |
| Environment evidence | `DisplayEnvironmentSource.swift` |
| Single presentation lifecycle | `NotchiumDisplayCoordinator.swift` |
| Activity eligibility | `ActivitySurfacingPolicy.swift`, `ActivityCoordinator.swift` |
| Panel and page continuity | `NotchiumPanelController.swift`, `NotchPanel.swift`, `DynamicIslandPresentationModel.swift` |
| Existing DEBUG fixture identity | `NotchShellDebugModel.swift` |
| Verification | Four `Stage21*Tests.swift` files and updated `DisplayCoordinatorTests.swift` |
| Documentation | This report, `ARCHITECTURE.md`, `NOTCH_SHELL.md` |

Source files above are in `NotchiumPackage/Sources/NotchiumDynamicIsland`; tests are in `NotchiumPackage/Tests/NotchiumFeatureTests`. Existing Stage 22 edits elsewhere were retained.

## 21A — Display state

`DisplayPresentationState` is a deterministic value reducer consumed by `NotchiumDisplayCoordinator`. Its descriptors contain online Core Graphics IDs, public display UUIDs, frame/visible frame, backing scale, safe-area/auxiliary-area geometry, primary/built-in status and top-center anchor. Numeric display-ID reuse with a different UUID invalidates the old direct lease. No `NSScreen` escapes the AppKit adapters or is retained across topology changes.

Ownership order is an existing direct interaction lease, pointer-containing display, frontmost application's on-screen window display, surviving owner, primary display, then any remaining display. Open/pinned and auxiliary sessions hold direct ownership. Passive submissions read the pointer against cached descriptors, without rescanning screens or the window list. Removing the owner invalidates its lease and selects a valid replacement. Reconnection alone does not take ownership back.

Topology snapshots rebuild on screen-parameter changes, start and wake. Identical snapshots do not advance topology generation. One 80 ms cancellation-aware task coalesces screen/Space/activation/presentation changes. Lifecycle and reconciliation generations reject work after sleep, stop/restart or explicit ownership selection. A single wake settling reconciliation handles delayed WindowServer geometry; there are no repeating topology/fullscreen timers.

Notchless displays are represented with their own geometry and can own presentation. They use the existing menu-bar fallback, whose current content is status/settings rather than a complete feature surface. The shell remains eligible only on an owned built-in screen with a verified physical notch. Stage 21 deliberately does not implement external overlay/activity rendering.

## 21B — Fullscreen and presentation

`DisplayEnvironmentSource` observes public `NSApplication.currentSystemPresentationOptions` using documented KVO, plus the coordinator's owned Workspace activation/Space notifications. On those events it reads only frontmost PID and on-screen layer-zero window bounds via `CGWindowListCopyWindowInfo`; it never uses window titles, app-name lists, AX authorization or screen recording. Quartz coordinates convert using the **primary display's top**, not the union of all display frames.

A `.fullScreen` system option is required for fullscreen classification. A maximized or screen-filling rectangle alone is normal. Window evidence scopes the active application's context to a display, so fullscreen on another monitor does not quiet this owner. Permanent menu-bar hiding together with permanent Dock hiding or disabled process switching is a narrow `presentationLike` heuristic; ordinary automatic menu/Dock hiding is insufficient.

The model supports only evidenced states: `normal`, `fullscreenApp`, `immersiveMedia`, `presentationLike` and `sleeping`. `immersiveMedia` is a fullscreen app whose own process holds a display-sleep assertion (`PreventUserIdleDisplaySleep`/`NoDisplaySleepAssertion`, read with public `IOPMCopyAssertionsByProcess`); video players and browsers hold one only while media plays. An assertion held by a helper process, or a failed read, conservatively stays `fullscreenApp`. Playback can start or pause without a Space, activation or option change, so an activity submitted while fullscreen re-reads the evidence before it is filtered. Missing window evidence leaves the display context normal rather than inventing a display association. This is presentation-options/window evidence, not a private fullscreen-Space-ID API.

Redacted DEBUG diagnostics report evidence/context changes only; Release contains no new diagnostic logging. Apple documents [system presentation options and their KVO behavior](https://developer.apple.com/documentation/appkit/nsapplication/currentsystempresentationoptions).

## 21C — Activity policy

`ActivitySurfacingPolicy` filters presentation candidates before the existing `ActivityPriorityPolicy`. It changes no rank, baseline/transient role, coalescing key, provider state or lifetime. `liveActivities` and identity lookup retain quiet entries; their original absolute deadlines continue, preventing replay of expired notices after returning to Desktop.

Normal desktop behavior is unchanged, and a fullscreen app that is not playing media now gets the same normal policy. Activities have three tiers. *Essential* (critical priority, critical battery, 5-minute Calendar, transfer completion/failure, timer completion, volume/mute/brightness and user-action feedback) always surfaces. *Ambient* (low battery, 30/60-minute Calendar, ongoing Music/transfer/timer) is quiet only in `presentationLike`. *Routine* (output-device, charging/unplugging, screenshots, Focus-mode changes) is also quiet in `immersiveMedia`. Quieted activities keep their state. “Eligible” does not override a higher-ranked Calendar alert with a lower-ranked volume HUD. Sleep removes visible slots while retaining source data.

There is no production brightness HUD provider in this codebase; Stage 21 verifies the existing generic brightness fixture's eligibility and adds no new provider/activity type.

## 21D — Panel migration and ownership

The controller consumes the coordinator's complete panel layout. Geometry changes update the frame without coordinate animation. Display migration orders the same panel out/repositions/orders it in; it retains the hosting view and model. Missing owners use the fallback and cannot bind to another screen merely because its rectangle matches an obsolete one. DEBUG fixtures project their IDs onto the actual host display so fixture identity does not require that unsafe production fallback.

Topology/context changes never invoke `present(.collapsed)` or automatic-open navigation. Shelf sub-section, selected page, manual-selection ownership and activity identity survive migration, including when no shell is currently eligible. A genuinely new expansion still uses existing local/remote Media and Pomodoro arbitration. Sleep deliberately ends the open session and hides the panel; wake rebuilds evidence without reopening it.

Space transitions cancel pending hover work. Hover sessions close with existing motion and require fresh entry; pinned and auxiliary sessions retain their page. So does a session that native AirDrop returned to with the pointer elsewhere (the sheet's dismissal can itself switch back to a fullscreen Space): it is held until the pointer enters again, an outside click, or an explicit close. Native all-Spaces/fullscreen-auxiliary behavior stays in place. Share/AirDrop/file-drag owners continue to derive the current level; environmental changes never save or restore an old level. Migration introduces no animation and therefore requires no special Reduce Motion path or new accessibility page identity.

## 21E — Verification

The [2026-10-03 verification follow-up](STAGE21_VERIFICATION_FOLLOWUP.md) reran the current checkout: **624 tests passed, Debug and Release builds passed, and whitespace validation passed**. It records the real scaling check, native sharing checks, user-assisted fullscreen/video/HUD/Space/sleep checks, and the remaining manual matrix. Live fullscreen classification and an intermittent AirDrop return remain unresolved; the original implementation-run history below is preserved.

The focused Stage 21 tests cover topology addition/removal, clamshell return, lost/recycled IDs, resolution/arrangement/scaling, direct versus passive ownership, per-display context, maximized versus fullscreen evidence, unavailable metadata, Quartz conversion with displays above/left of primary, quiet identity/deadline retention, important activity eligibility, page preservation, automatic-page resolution on a new session, sleep/wake, non-cooperative stale callbacks and stop/restart callback rejection. A 100-event burst reconciles once without repeated topology/geometry work; 100 native `NSPanel` cycles exercise overlapping sharing/drag/context owners.

Final results:

| Check | Result |
|---|---|
| Final complete host-access package suite | **622 / 624 passed**; unchanged mixer assertions at lines 131 and 163 failed |
| Final focused display/policy/lifecycle pass | **40 passed, 0 failed** (all 16 Stage 21 tests included) |
| Earlier complete passes | 620 passed; later 624 passed before final context/fixture cleanup |
| Intermediate 623-test pass | 622 passed; existing audio-mixer timing assertion failed |
| Intermediate targeted mixer retry | Same pre-existing assertion failed at `AudioMixerTests.swift:163` |
| Debug workspace build | Passed |
| Release workspace build | Passed |
| `git diff --check` | Passed |

A later loaded run also reached the unchanged mixer output-route assertion at `AudioMixerTests.swift:131`; that test also waits exactly four `Task.yield()` calls rather than an operation completion. The new event-burst fixture was corrected to wait for completed reconciliation while advancing its controlled clock, after one loaded run exposed a race between cancellation and sleeper registration.

The intermittent permission assertion matches the pre-existing Stage 22 finding in [STAGE22_HARDENING.md](STAGE22_HARDENING.md). The earlier passing run does not establish that these synchronization issues are fixed. All 16 Stage 21 tests passed in the final complete run. No mixer code/tests were changed.

Native Xcode rebuilt and launched the Stage 21 app. The collapsed and expanded physical-notch shell were inspected through native accessibility and still screenshots: the existing hardware-aligned top edge, shared expanded geometry and single panel remained intact. The new diagnostics reported normal context and a valid display association on Desktop. Fullscreen was toggled through Xcode's native menu, which confirmed “Exit Full Screen”; the automation then refused to activate its editor with `cannotClickOffscreenElement`. Thus it did **not** verify the active fullscreen Space, fullscreen video or fullscreen surfacing. Xcode's original desktop window was restored and confirmed by the native “Enter Full Screen” command. At the last native check, the computer-use tool reported that the Mac was locked; further live UI verification requires the user to unlock it. No external monitor, lid, physical sleep or 60 fps migration acceptance was certified. Build commands use the existing `Notchium.xcworkspace`, `Notchium` scheme and My Mac destination. XcodeBuildMCP tools were unavailable, so the existing Xcode CLI workflow was used. Native tests require host access: the sandbox-only suite cannot resolve Finder. Builds use `CODE_SIGNING_ALLOWED=NO`; these validate compilation, not notarization or distribution signing.

### Performance sanity

Two 15-second `proc_pid_rusage` samples compared the existing Xcode debug process with the rebuilt app. Both reported **1 additional idle wakeup**. Interrupt wakeups were 446 before / 364 after; CPU time was 0.0876 / 0.1236 seconds; ending footprint was 67.05 / 61.77 MiB. Both used live services, but process lifetimes and playback/timer state differed and builds were running nearby. This is only an idle-wakeup sanity check, not evidence of a general CPU/memory improvement.

Source inspection and event-burst tests confirm no continuous display polling, duplicate Workspace registration across start/restart, or repeated layout work while state/geometry are unchanged. Existing feature polling remains outside Stage 21.

### Manual acceptance gate

Still screenshots and synthetic descriptors cannot certify cross-display animation seams or real WindowServer/sleep behavior. Live checks must exercise built-in/external ownership, active-monitor disconnect/reconnect, lid close/open, resolution/scaling/arrangement, repeated Space swipes, fullscreen video/presentation apps, important HUD/Calendar/transfer events, Finder drag, Share/AirDrop cancellation and physical sleep/wake. Inspect for wrong-screen/off-screen placement, duplicated shells, flashes, clipping, stale level/context, or page loss. External ownership should show the existing fallback, never a simulated island.
