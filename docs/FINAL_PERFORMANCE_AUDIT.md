# Independent SwiftUI / Swift concurrency source review

Reviewed the working tree on October 8, 2026. Read swiftui-pro (performance, performance-plus, data, views, accessibility, Swift), write-swift, ENGINEERING_RULES, Stage 22 and Stage 23. This is source evidence, not an Instruments leak/CPU certification. No production files were edited by this reviewer.

## Final change verdict

No actionable regression found in the SystemAudioMeter Observation conversion or waveform visibility boundary. Only public waveform/status/audio-activity properties are observed; task handles, intent flags and generations are ignored. Both consumers retain their injected meter. AudioMeterPermissionView reads status, so samples no longer schedule its body. MediaWaveform short-circuits before reading activity/levels when hidden, paused or Reduce Motion is enabled. The small CollapsedMediaWaveform wrapper takes the shell's existing expansion environment; notification/compact media remains eligible while collapsed. Main expansion already uses the shell's black content gate, so immediate waveform gating does not remove visible transition content. Producer cadence, 1.5 s audio grace, poll intervals, provider reconciliation, ownership and queue policy are unchanged.

Before: ObservableObject's objectWillChange notified Settings and invisible waveform consumers for every waveformLevels write. After: property reads establish subscriptions, with no level read on hidden/Reduce Motion paths. This is an eliminated-notification structural improvement; CPU/wakeup gains require like-for-like measurements.

## Recurring-source inventory

| Owner | Source / cadence | Lifetime and reason |
| --- | --- | --- |
| RealMediaProvider | One playback sleep loop; closed 5 s playing / 15 s inactive; visible Music 2.5 s playing / 5 s paused / 10 s no media | Authenticated app session. One in-flight playback path, shared cooldown, generation guards; shutdown/disconnect cancel. Home currently uses the closed cadence. |
| RealMediaProvider | Spotify desktop NotificationCenter AsyncStream; immediate + 250 ms trailing refresh; bounded post-command reconciliation delays | Connected session; coalesced signals and cancellation. No second independent playback/device loop. |
| MediaSessionController | Up Next queue refresh every 5 s; volume throttle 120 ms; inactive playback activity cooldown 2 s | Queue loop only while Up Next is visible; others are owned transient tasks. Devices refreshed on demand, cached 30 s. |
| SpotifyAudioTap / PCMAnalyzer | Core Audio IOProc; processing queue; max 30 Hz sample publication | Required by approved authenticated local playback detection, including paused signal monitoring. After 0.5 s digital silence, buffers are scanned without copy/decode/FFT. Stop destroys IOProc, aggregate and tap. |
| SystemAudioMeter | Single 1.5 s inactivity watchdog | Only after audio energy; one task reused across samples. Stop cancels watchdog and orders capture shutdown. |
| RealClipboardService | Timer 0.5 s, tolerance 0.2 s | Only while capture subscribers exist. Idle reads changeCount only; payload reads only after change. Stop invalidates timer and cancels image work. |
| RealFileTransferService | Progress subscription + KVO; mailbox actor delivery; 250 ms changed-progress flush | Subscriber-owned. Terminal evidence synchronously latches before delivery; no terminal classification change. Unpublish removes Progress/KVO/flush resources. |
| RealScreenshotService | Folder/candidate DispatchSource; Spotlight incremental updates, 0.2 s batching | Subscriber-owned. Scans/readiness work coalesce; stop closes descriptors via cancellation handlers and removes query observers. Candidate watchers and seen/captured indexes bound to 64. |
| RealCalendarService | EventKit/day/clock/timezone/active/wake notifications; 250 ms refresh coalescing; one next-boundary deadline | Subscriber-owned. Stop removes observers and cancels deadlines; latest-only snapshots. |
| CalendarReminderCoordinator | One next-reminder deadline | Calendar feature lifecycle. No per-second domain loop. |
| PomodoroModel | One authoritative deadline, paused-presentation expiry, workspace/clock notifications | Timer active independent of visibility; stop cancels tasks/observers and flushes store. |
| RealFocusService | 4 s sleep loop only when Focus-status entitlement is present | Per stream; unentitled path completes once. Cancellation terminates loop. |
| RealAudioDevicesService / RealAudioProcessesService | HAL listeners, volume-key local/global/event-tap bridge, latest-only streams | Subscriber-owned; teardown removes listeners and monitors. Volume edit uses 25 ms debounce; mixer edit uses 16 ms debounce. No idle audio-device poller. |
| RealBatteryService | IOKit main-run-loop source | Subscriber-owned; teardown removes and invalidates source. No poller. |
| CameraModel / RealCameraService | Device/runtime/sleep notifications; serial AVCaptureSession start/stop | Preview-request lifetime only. Closed preview cancels start/access tasks, removes observers, queues stop and removes session inputs. No frame output/storage. Runtime recovery bounded to one attempt/request. |
| Notch panel/display/presentation | Native pointer/display/Space/sleep/menu events; transient hover/collapse/transition/reconcile tasks | Controller lifetime; no idle timer. Event resources removed on stop. |
| Caffeine | Owned assertion and optional deadline | Enabled lease; explicit release/expiry. Header timed presentation uses 1 s Timeline only while expanded. |
| LidAwakeController / installed helper | 5 s client heartbeat while active; helper 1 s watchdog | Required lease safety; client stops heartbeat on release. Optional helper watchdog runs while the daemon is installed/running. |
| Shortcuts | On-demand subprocess, 15 s timeout, 60 s discovery cache | One operation; cancellation terminates child. No discovery poller. |
| SwiftUI display timelines | Visible media seek 10 Hz; visible Calendar 1 Hz; visible Home date 60 s; visible Pomodoro countdown 1 Hz; Today 30 s active/visible otherwise 1 h | Timing confined to local timeline subtrees. Compact countdown 1 Hz only for running countdown; device-turn animation timeline only during its finite turn. |
| Control transient tasks | Hold progress ~16 ms while pointer held; reminder parse 250 ms; copy notice 1.2 s; action feedback 0.35/1.5/3 s | Input/feedback lifetime with explicit cancellation. No new task for ordinary hover/press visuals. |

## Image/resource ownership

- Artwork: one shared deduplicating cache, at most eight 160 px decoded thumbnails and ~1 MB target cost. Data response bounded to 2 MB; requests time out in 20 s. Appearance palette uses the same resource. Views retain current small representation while mounted. Consumer cancellation rejects stale result; shared request intentionally may finish for another consumer.
- File/screenshot thumbnails: bounded 48-entry LRU includes key bookkeeping; key includes URL, size and scale. In-flight identity prevents invalidated completion repopulating cache. Quick Look requests create size-specific representations; view cancellation rejects stale assignment. Requests may finish after a consumer disappears, which avoids prematurely cancelling another consumer.
- Clipboard: full copy-back payload downsampled to 2048 px, 96 px thumbnail. Model retains metadata/thumbnails, not all full PNGs. History limit 25/50/100 plus up to ten pins; encrypted payload store owns images and set-difference cleanup. Inline NSImage creation and native file-icon lookup remain in row body (ClipboardPageView.swift:197,208); hover repeats these small operations. No measured heavy decode path; avoid adding another cache without a demonstrated cost.
- Mirror: AVFoundation preview-only session has no capture outputs. PreviewHostView owns its layer while the live branch exists; closing removes live branch and releases preview. Session input removal is ordered behind stopRunning. Source ownership is correct; physical capture-off timing and retained heap need native Allocations.
- Shelf: exact acquired security-scoped URLs retained per item and balanced at removal/restore/stop/deinit. Share/AirDrop owners retain native session only through its interaction lifetime; no source-confirmed new leak.

## Existing evidence-backed limitations / rejected optimizations

- TransferActivityModel.finishedIDs accumulates one terminal tombstone per session transfer (lines 24,38) until reset. This is the Stage 22 known retention tradeoff required to reject late samples; arbitrary eviction risks resurrection. Add a service epoch/acknowledgment only if measurement justifies the architecture change.
- PCM processing uses a serial dispatch queue with copied transient buffers. Slow-queue accumulation is possible under load; no demonstrated backlog/heap growth. Do not replace the approved FFT pipeline speculatively.
- ActivityCoordinator performs a full ranking sort per meaningful change (line 219), but skips identical upserts, compares every published slot, and uses one lifetime task. Active set is small. No measured hotspot; preserve ranking.
- MediaState remains one observed value, so playback snapshots can update hidden Home/Music metadata trees at provider cadence. Timelines and waveform sample changes are now isolated. Splitting metadata/progress authority would add invalidation complexity without established gain.
- Keeping small artwork/thumbnails while retained pages are mounted is intentional. It prevents repeated decoding and preserves page identity; it is not evidence of a leak.
- Preserve Clipboard 0.5 s supported count-only polling; no public native change event exists in the implementation. Preserve Spotify cadence and audio activity monitoring because responsiveness/local-versus-remote rules depend on them.
- New AudioMeterObservationTests uses thirty Task.yield calls as a drain. That is consistent with existing tests but does not guarantee completion under load; use condition/operation completion if it flakes. No failure was reproduced by this read-only reviewer.
- SystemAudioMeter's pre-existing watchdog promotes weak self to strong across its sleep loop; teardown therefore depends on the composition-owned stop path. App composition explicitly calls stop. A drop-owner-without-stop lifetime test would be useful before claiming deallocation safety; no application path that discards the meter without stop was found.

## Validation limits

Read-only source review and diff inspection only. Build/test/performance results belong to the parent task. No CPU/memory percentage, wakeup reduction, leak-free certification, physical camera indicator or VoiceOver claim is made here.
