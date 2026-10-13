# Notchium Proactive Intelligence: feasibility and implementation proposal

Planning only. Prepared October 11, 2026 (America/Toronto).

Source baseline: main, commit 3e9e340cf42b8b0686b190feaf7ad80b2f40e1b7. The working tree was clean before this study. No production source, project configuration, existing UI, permissions, user data, or distribution behavior was changed. No commit, publication, production feature, or automation was created.

## Decision

Proceed with an opt-in, deterministic MVP: Contextual Action Cards and Adaptive Suggestion Learning together, followed by narrow Return Briefs and limited prepared actions. Reuse existing provider truth, feature models, ActivityCoordinator, and Stage 21 display ownership.

The smallest useful architecture needs one proactive feature runtime, pure candidate/scoring/policy values, one bounded local store, and one composition-owned typed Action Broker. It does not need a context bus, general agent, database framework, model training system, additional window coordinator, or continuously running inference loop.

Focus status is blocked in the free build. This does not block meeting, transfer, battery, learning, return, or explicit Shortcut actions. Foundation Models text enrichment is conditional on macOS 26 and model availability. Native Foundation Models image input requires macOS 27; it cannot be a macOS 26 baseline feature.

Implementation is not approved by this study. The separate [first-stage prompt](/Users/marcusyu/Projects/notch/docs/PROACTIVE_INTELLIGENCE_STAGE25A_PROMPT.md) is ready for a later implementation request.

## Evidence and research reconciliation

The supplied [research PDF](</Users/marcusyu/Downloads/Implementing Proactive Intelligence in Notchium.pdf>) was read as product research, not as authority to implement features. Its deterministic pipeline, explicit action approval, reversible learning, narrow observation, and interruption-precision metrics are retained. Pages 2, 29–32, and 38–42 supply planning hypotheses, not measured engineering guarantees. The flowchart and metric formulas were also inspected in rendered pages.

Code-specific corrections to the research:

| Research concept | Verified repository reality | Planning consequence |
|---|---|---|
| Context bus | Domain event buses are prohibited; services already expose typed snapshots/streams. | Use explicitly injected adapters and inputs. |
| Generic Focus gate | RealFocusService checks the Communication Notifications entitlement and fails closed when absent. | Free-build Focus remains unknown/unavailable. |
| Notchium-owned downloads | RealFileTransferService observes externally published file Progress in configured folders. | Say “Notchium-observed transfers”; coverage is incomplete and there is no offline history. |
| Shelf storage | ShelfModel holds bookmarks/references, not managed copies; capacity 24, maximum age seven days on restore. | Reuse reference ownership; never assume a copied file or introduce indexing. |
| Pending Notchium reminders | ReminderService creates reminders and lists writable lists, but cannot query pending reminders or return saved reminder IDs. | Omit pending reminders from the initial Brief; do not infer pending/completed state from a successful save. |
| Notification infrastructure | NotificationCoordinator is an in-app slot, not UNUserNotificationCenter. RealActivityEventSource is a placeholder. | Add neither system notification permission nor third-party notification ingestion. |
| Shortcut name URL scheme | AppleShortcutService already lists identifiers and runs a selected identifier with Apple's CLI and argument arrays. | Reuse it; do not replace it with a weaker name-based URL scheme. |
| Broad local model abstraction | macOS 27 introduces newer model and image interfaces. macOS 26 already has the older text API. | Keep a small optional text adapter; gate every newer API independently. |
| Four top-level pages in older guidance | Current NotchPage declares Home, Music, Calendar, Focus Timer, Audio, and Shelf. | Preserve current navigation; add no proactive tab. |
| Near-zero idle cost | Stage 22 documents limited measurements and remaining hardware work, not a production energy certification. | Establish an incremental baseline; measure before release. |

Current build authority is Config/Release.xcconfig and scripts/release.sh. CLAUDE.md still calls the principal distribution Developer ID/notarized; that sentence is stale. Some older architecture/permissions prose also describes scaffolding, managed Shelf copies, or limits replaced by current code. These documents were not rewritten during this planning task.

### Skills and substitutions

Read and applied: available apple-design and emil-design-eng for interaction restraint; swift-code-review, swiftui-expert-skill and macos-patterns for ownership, native surfaces and SwiftUI invalidation; security-review for authorization/minimization; instruments-profiling for the measurement plan; xcodebuildmcp for tooling guidance; pdf for research extraction and visual inspection.

Named write-swift, swiftui-pro, stride-analysis-patterns, code-review-excellence, systematic-debugging, and verification-before-completion were not found in the available skill locations. Substitutions are the installed Swift review/SwiftUI/macOS skills, a direct STRIDE analysis, source tracing, controlled API probes, and actual build/test receipts below. No skills or dependencies were installed.

The available impeccable instructions and product guidance were inspected for accessibility, state completeness, and product restraint. Its context script reported that PRODUCT.md initialization was required. That writing workflow was not followed because this assignment explicitly prohibits unrelated project/UI work; existing Stage 23 tokens and native behavior remain authoritative. Web-specific CSS advice from design skills is not treated as an AppKit or SwiftUI API contract.

XcodeBuildMCP tools are not exposed in this session. Local Xcode tools were used without changing its configuration.

## A. Existing capabilities and ownership

All source links below point to the inspected checkout. “Available” means an existing interface can be reused, not that every proposed proactive integration already exists.

| Component | Source of truth and exact reusable interfaces | Proactive support already available |
|---|---|---|
| Activity authority | [ActivityCoordinator](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumDynamicIsland/ActivityCoordinator.swift:9): present, dismiss(id:), dismiss(key:), contains(id:), primary, secondary, liveActivities, presentationContext, reducesInterruptions. | Stable source coalescing, live-state retention, ranking, visible slots, transient expiry, baseline restoration. |
| Activity semantics | [NotchActivity](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumDynamicIsland/NotchActivity.swift), [ActivityPriorityPolicy](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumDynamicIsland/ActivityPriorityPolicy.swift:15), [ActivitySurfacingPolicy](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumDynamicIsland/ActivitySurfacingPolicy.swift). | Priority, family, destination, minimal content, persistent/condition/transient lifetimes, environmental filtering. |
| Display/presentation | [NotchiumDisplayCoordinator](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumDynamicIsland/NotchiumDisplayCoordinator.swift:8), DisplayPresentationState, AppKitDisplayEnvironmentSource. | Selected display, public geometry, topology generations, sleep/wake, fullscreen/immersive/presentation context, passive/direct ownership. |
| Native panel/session | [NotchPanel](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumDynamicIsland/NotchPanel.swift), NotchiumPanelController, DynamicIslandPresentationModel, NotchPageModel. | One nonactivating panel, intentional keyboard focus, Escape, auxiliary interaction leases, retained page selection, camera-close behavior. |
| Calendar | [RealCalendarService](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumServices/CalendarService.swift:95): updates, refresh, requestAccess, setCalendarSelected. [MeetingLinkDetector](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumServices/CalendarService.swift:297): detect, isSupported. | Selected-calendar event summaries, permission/availability, all-day flag, dates, supported HTTPS meeting URLs. Zoom, Google Meet, and supported Teams hosts/routes already work. |
| Calendar activity | [CalendarActivityModel](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumCalendarFeature/CalendarActivityModel.swift:10): snapshot, joinEvent, joinReminder, dismissReminder. [CalendarReminderCoordinator](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumCalendarFeature/CalendarReminderCoordinator.swift:11): update, dismiss, thresholds. | Existing 60/30/5-minute alerts, meeting-start boundary, source coalescing, Calendar rendering and Join. |
| Pomodoro | [PomodoroModel](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumFocusFeature/PomodoroModel.swift:24): state, records, configuration, startTimer, pause, resume, end, refresh. PomodoroEngine provides pure transitions. | Running/paused/ready state, deadlines, completion records, catch-up, explicit controls and persistent activity. |
| Caffeine | [CaffeineControlModel](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumCaffeineFeature/CaffeineControlModel.swift:9): mode, isBusy, selectedDuration, expiresAt, keepAwake(for:), cycleMode. CaffeineService.setMode, updates, shutdown. | Owned public IOPM assertions, finite 15/30/60/120-minute choices and expiry. Ordinary Caffeine works in free builds. |
| Battery | [BatteryService](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumServices/BatteryService.swift), [BatteryActivityPolicy](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumFeature/BatteryActivityPolicy.swift), application controller's startBatteryActivities. | Event-driven charge/power snapshots; 20% low/10% critical crossings, 5 percentage-point rearm margin, no startup warning. |
| Transfers | [FileTransferService](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumServices/FileTransferService.swift): updates, availability, TransferSnapshot. [TransferActivityModel](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumShelfFeature/TransferActivityModel.swift:12): receive, active, recent, finishedFiles. | Reliable publisher-reported terminal state for observed operations, optional byte totals, final URLs, one batch activity, five visible recent results. |
| Shelf/file actions | [ShelfModel](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumShelfFeature/ShelfModel.swift): items, restore, add, remove, clear, refreshAvailability. FilesFeatureModel.addToShelf; FileActionPerforming.reveal/open. | User-provided file references, bookmark resolution, existing Reveal and Add to Shelf, balanced access lifetime. |
| Clipboard | [ClipboardModel](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumClipboardFeature/ClipboardModel.swift); [FileClipboardStore](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumClipboardFeature/EncryptedClipboardStore.swift:5). | Existing opt-in encrypted local history, retention, clear controls and stale decoder protections. No proactive read is needed. |
| Mirror/camera | [CameraModel](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumCameraFeature/CameraModel.swift): openPreview, closePreview, requestAccess, status, devices. CameraService owns AVFoundation. | Explicit preview only, permission education, absent/denied/busy states, generation protection, capture stop on close/sleep. |
| Home Shortcuts | [QuickActionStore](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumPersistence/QuickActionStore.swift): actions, pinned, save, remove. QuickActionRunner.run/validate/retry/stop. [AppleShortcutService](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumServices/ShortcutService.swift:26): list, run. | Explicit pins, exact UUID/name validation, fixed executable, no shell interpolation, per-action in-flight reservation, cancellation and discovery cache. |
| Quick Reminder | [ReminderService](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumServices/ReminderService.swift:19): access, requestAccess, lists, save, changes. QuickReminderModel owns the composer. | Explicit reminder creation; no pending-reminder inventory, saved identity, completion observation, or snooze operation. |
| Focus | [RealFocusService](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumServices/FocusService.swift:31), FocusModeModel. | An explicit unavailable state in free builds; user-selected on/off Shortcuts for timer coupling. No generic named Focus access. |
| Notifications | [NotificationCoordinator](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumDynamicIsland/NotificationCoordinator.swift), NotchNotification, UnifiedNotchNotificationContent. | In-app content, hover/interaction identity, user dismissal and typed source feedback. No OS notification permission is needed for these surfaces. |
| Composition/lifecycle | [AppEnvironment](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumFeature/AppEnvironment.swift), [NotchiumApplicationController](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumFeature/NotchiumApplicationController.swift:23), [NotchiumApp](/Users/marcusyu/Projects/notch/Notchium/NotchiumApp.swift). | Dependencies constructed once; feature start/stop, task cancellation, graceful store flush and one display/presentation owner. |
| Settings/time/storage | [NotchiumSettingsView](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumFeature/NotchiumSettingsView.swift:11), HomeConfiguration/QuickActionStore, [AppClock](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumCore/AppClock.swift), PomodoroPersisting, PersistenceStoring. | Typed/versioned settings examples, injected fake clock, UUID abstraction, ordered atomic-store patterns. PersistenceStoring is not a generic event database. |

### Event, permission, async, and persistence boundaries

| Component | Existing event/lifecycle boundary | Permissions and persistence | Risk when integrating |
|---|---|---|---|
| ActivityCoordinator | MainActor; published slots plus internal presentationDidResolve emitted after assignments; one generation-checked lifetime task. | None; activities are memory-only. | Individual @Published sinks emit before assignment. A suggestion cannot infer “seen” merely from submission or liveness. Meaningful updates can renew durations. |
| Display/panel | MainActor; owned Workspace notifications, presentation-options KVO; 80 ms coalesced reconciliation; lifecycle generations. | No AX or Screen Recording. No private window titles retained. Memory-only ownership/session state. | Do not create another fullscreen, pointer, screen scan, placement timer, panel, or ownership lease manager. |
| Calendar | One shared MainActor EventKit store; bufferingNewest(1); change coalescing, boundary task, clock/timezone and wake refresh; last-subscriber teardown. | Full Calendar TCC access. Selected IDs in UserDefaults; event payloads in memory. Reads roughly previous day through next 14 days, filtered to unended events. | No second EKEventStore or history scan. stop() ends all subscribers. CalendarActivityModel already requests access on start; the proactive layer must not prompt again. UUIDs survive refresh only within the process. |
| Calendar reminders | MainActor; one boundary task, per-event shown-threshold sets, live-activity observation. | No additional permission; transient shown state only. | Do not schedule another identical five-minute notification. Cancel edits/deletions using fresh source state. |
| Pomodoro | MainActor; owned deadline/pause tasks, native wake and clock refresh. Pure engine emits PomodoroEvent internally. | No TCC. FilePomodoroStore writes FocusTimer.json atomically on a utility queue; configuration in UserDefaults. | There is no public terminal-event stream. Catch-up can create records after sleep/relaunch, and old completion UI is intentionally silent. Add an owning-boundary event hook, not a second timer engine. |
| Caffeine | Mutex-protected service state; MainActor model owns operation and expiry tasks. | Ordinary assertions need no TCC. Assertions are process lifetime; finite expiration is model-owned. | Calling the service directly bypasses model expiry. Fire-and-forget model commands cannot certify execution completion. Free build must never enable Lid Awake. |
| Battery | IOPSNotificationCreateRunLoopSource, one source shared by subscribers; controller owns consumer. | No TCC; no history. | Reuse/fan out the existing snapshot/crossing path. Do not add polling or a duplicate crossing policy. |
| Transfers | Progress subscribers/KVO with generation identities and 250 ms coalescing; terminal latch; consumer owned by FilesFeatureModel. | Existing monitoring performs a read-only Downloads-folder probe; protected-folder TCC can apply. No transfer archive. | Provider stream is unbounded; a slow new consumer can accumulate buffers. Terminal dedup must happen after authoritative reduction. Do not reuse newest-only buffering for terminal facts. |
| Shelf | MainActor reference insertion/restore/removal; on-demand availability checks. | Existing bookmark records in UserDefaults. Security scope when sandboxed; ordinary bookmarks in free unsandboxed build. | No broad scan, contents, new Quick Look preload, or second scope owner. Recheck file existence/access before an action. |
| Clipboard | Existing supported 0.5 s changeCount polling and cancellation/generation-protected decoding. | Capture defaults off in production. Current UI choices are 25/50/100 entries, default 50, default 30-day retention; pins survive. AES-GCM and login Keychain in free builds. | The old 500-item contract is not the current model limit. Do not read payloads, derive meaning, start capture, or write history for this MVP. |
| Camera | MainActor presentation model; serial AVFoundation session work; owned permission/start tasks and one recovery per explicit preview request. | Camera TCC and NSCameraUsageDescription. No microphone or frame persistence. | A suggestion must not start/prewarm capture. Keep auxiliary leases and close/sleep teardown in existing owners. |
| Shortcuts | Async process exit, cancellation handler, locked launch/cancel boundary; discovery has 15 s timeout. Runner reserves before awaits. | User selection; Shortcut-specific permissions remain managed by Shortcuts. Pins/UUID/name in Home store. Output discarded; temporary discovery file removed. | A Shortcut can prompt, take arbitrarily long, send data, or change unrelated systems. Process termination is not rollback. Renames currently fail exact name+UUID comparison. |
| Reminder | MainActor EventKit, change publisher, shared permission request task. | Full Reminders TCC; existing selected list and system reminder storage. | Save returns Void. No basis for “still pending” or “snoozed.” Do not create another EventKit read pipeline to fill a Brief. |
| Focus | Entitlement guard first; unavailable emits once and finishes. Entitled path polls cached status every four seconds. | Communication Notifications entitlement absent in free Release; Focus purpose string alone does not enable access. Preferences/pinned Shortcuts persisted. | Unknown is not false. Do not infer Focus success or current state from a Shortcut's exit. Existing timer coupling can invoke an additional Shortcut when Pomodoro starts. |
| App/settings | MainActor root and delegates; owned start/stop tasks; feature-scoped preferences and stores. | No new permission required. Some generic persistence contracts remain scaffolding. | Avoid putting the whole inference engine in the application controller or adding raw state to the shell environment. |

Two skeleton interfaces are explicitly unsuitable for reuse as live sources: RealMeetingsService still returns stageTwoRequired; RealActivityEventSource returns an unavailable/empty stream. Production meeting behavior actually comes from CalendarService and CalendarActivityModel. Media, audio, screenshot, and monitoring implementations remain outside new observation scope; only existing activity eligibility and display context are relevant.

## B. Feature feasibility matrix

Confirmed API feasibility is separate from a verified shipped integration.

| Feature | Feasible on macOS 26 free build? | Existing support | Missing work | Risk | Recommendation |
|---|---|---|---|---|---|
| Contextual Action Cards | Yes, confirmed underlying public APIs/source compilation; new UI/runtime not built. | Calendar links/reminders, battery crossing, Caffeine/Pomodoro, transfer outcomes, native shell. | Candidates, stable cross-launch identity, exposure/response semantics, conservative gate, renderer. | Moderate: duplicate/stale interruptions. | Implement first, together with learning. |
| Adaptive Suggestion Learning | Yes; local deterministic arithmetic/storage. | Clock, versioned settings and atomic-store patterns. | Feedback reducer, aggregates, reset, migration, bounded exposure history. | Moderate: wrong feedback attribution. | Required for first exposed cards. |
| Smart Return Briefs | Yes for observed sleep/session intervals and known events; full idle-return detection is conditional. | Stage 21 sleep/wake, transfer facts, Pomodoro catch-up, Calendar/battery state. | Session source, bounded ledger, coverage/cursor, ranking and temporary view. | Moderate: overstated history, wake timing. | MVP after cards/learning; omit pending reminders. |
| Prepared One-Click Actions | Yes for a narrow confirmed plan; no exactly-once guarantee for external Shortcuts. | Existing action providers and explicit UI commands. | Awaitable result contracts, consent token, broker, step state, partial failure/retry. | Medium–high: external side effects and duplicate coupling. | MVP with Ask every time. |
| Routine Discovery | Yes without additional OS permissions, but current action event coverage is incomplete. | Owned action entry points, Home pins. | Typed successful-action events, distinct-day counting, routine storage/editor. | Moderate privacy/false-pattern risk. | Post-MVP; entirely Notchium actions. |
| Local Semantic Intelligence | Conditional. macOS 26 text APIs compile; availability can fail. | Apple Foundation Models, existing structured context. | Opt-in text adapter, locale/model/error fallback and model-version evaluation. | Variable model cost/reliability. | Optional post-MVP; no cloud, no tools. |
| Explicit Screen-Aware Assistance | Capture/OCR APIs feasible on 26; full native model image understanding requires 27 and eligible model/device. | Native panel patterns; no current screen-assistance service. | Explicit source picker, scoped one-shot capture, cancellation, analysis/results. | High privacy/resource cost. | Separate experimental spike. Never MVP dependency. |

## Feature A: Contextual Action Cards

1. **User value:** Prepare for an imminent supported meeting; add useful context to an existing battery warning; offer Reveal/Add to Shelf after a significant observed transfer.
2. **Implemented dependencies:** Calendar snapshots, link allowlist, 5-minute reminder, battery policy, Caffeine mode, Pomodoro state, publisher completion, native rendering and arbitration.
3. **Missing work:** Pure generators, relevance/response state, occurrence identity, source revision, eligibility deadlines, feedback store and temporary expanded card.
4. **Public APIs:** Existing EventKit, IOKit power, Foundation Progress and NSWorkspace; no new inference API.
5. **Permissions/entitlements:** Reuse authorized Calendar and folder access. Camera only after Preview is explicitly chosen. No Focus entitlement request.
6. **Free Release compatibility:** Yes. Work Focus is an optional exact user-pinned Shortcut, not status integration.
7. **Resource cost:** Small bounded comparisons on meaningful changes; no new Calendar query, transfer scan, model, or network request. Cost is a forecast until measured.
8. **Privacy:** Copy only necessary projections into memory; no notes, attendees, clipboard, app names, window titles or file contents. No passive camera.
9. **Architecture:** Source-aligned cards enrich existing Calendar/battery/transfer semantics where possible; generic suggestions use one new low-priority category. Existing coordinator keeps ranking/lifetime authority.
10. **UI:** One reason, one primary action, up to two secondary actions; optional setup behind Preview setup. No automatic expansion, new page, or permanent feed.
11. **Failure/fallback:** No supported URL means no meeting-setup candidate; existing Calendar event/alert still works. Camera denial affects only Preview. Missing files or revoked sources invalidate actions/card. Unknown transfer size does not qualify as “significant.”
12. **Difficulty:** Medium, principally lifecycle, presentation and false-positive prevention.
13. **Effort:** Approximately 3–4 engineer-weeks for cards with initial learning/presentation, excluding shared foundation and hardening.
14. **Recommendation:** Implement now after foundation, ship only with Feature B.

### Deterministic initial rules

Meeting: authorized selected calendar, non-all-day event, supported validated URL, unended occurrence, source fresh, and starts within five minutes. A local generator must not read EventKit or fetch the URL to “verify” it. Existing supported routes are enough for the first version; Webex, FaceTime and arbitrary URLs from research examples are not currently supported and are not silently added.

Meeting eligibility ends at the earlier of event end and two minutes after start. Snooze is bounded by that deadline; do not offer a five-minute snooze that would produce a stale card. No semantic “presentation” classification in the MVP.

Battery: use the existing discharging 10% critical crossing plus active Caffeine or a running focus phase with substantial remaining duration. A proposed 20-minute remaining threshold is a fixture/product hypothesis. Enrich the existing battery event, never issue a second critical warning. Learning can hide optional work advice; it must never suppress the existing essential battery warning. Charging clears the work advice. No warning based on startup state alone.

Transfer: terminal completed, observed active operation in this process/coverage interval, readable final URL, and reported total at least 100 MiB as an initial configurable-in-code hypothesis. No semantic file-type guess and no universal download claim. Default follow-up is Reveal; opening a downloaded executable/document is outside the initial allowlist. Existing batch completion stays authoritative; do not interrupt while other transfers remain active.

### Identity, expiry and duplicate control

Separate occurrence identity, content revision, category identity, and presentation UUID. A revised title must not become a new occurrence; a different recurrence instance must. Calendar's current UUID is not durable across launch. Before exposed cards ship, add an opaque occurrence token at the existing Calendar adapter projection boundary, derived from the adapter's calendar/event/occurrence key. Recommend an install-scoped keyed digest; persist only the token and short suppression deadline, not the raw key, title or URL. That token is local pseudonymous metadata, not anonymous data.

Transfers use their provider ID within a run epoch; Pomodoro uses its session record ID. Duplicate terminal callbacks must not produce duplicate ledger events. A bounded tombstone must remain until its source epoch closes or a documented deadline makes resurrection impossible; arbitrary eviction is not safe.

Keep at most eight pending candidates and one visible proactive experience. Proposed initial global cooldown: 30 minutes; at most three unsolicited proactive exposures per day, excluding unchanged existing essential alerts and manual requests. Per-occurrence dismissal stops that occurrence. Category cooldowns/negative learning can lengthen silence, never create more exposures.

Candidate relevantUntil is absolute. Map it to remaining coordinator duration when submitting/updating so content changes cannot extend relevance. The coordinator owns visible hint expiry; the runtime owns pending eligibility and source validity. An expired hint is not automatically shown again. Opening a hint preserves the candidate token for the intentional card, even though the existing activation path consumes a transient.

## Feature B: Adaptive Suggestion Learning

1. **User value:** Repeatedly unwanted optional suggestions become quieter; good ideas at a bad time can move later.
2. **Implemented dependencies:** Injected clocks, versioned preference/store patterns and stable activity identities.
3. **Missing work:** Typed feedback, actual exposure receipts, bounded history, per-category aggregates, reset/category controls.
4. **Public APIs:** Foundation arithmetic/Codable and local storage only.
5. **Permissions/entitlements:** None; the learning toggle is product consent.
6. **Free Release compatibility:** Confirmed in principle; requires no identity entitlement or training service.
7. **Resource cost:** Constant-size aggregate updates; event-driven batched disk writes; no training loop.
8. **Privacy:** Categories, outcomes, coarse timing buckets and short-lived opaque tokens; no user content.
9. **Architecture:** Pure feedback/scoring reducer in proactive feature; storage behind an injected contract.
10. **UI:** Accept, Snooze, Dismiss; secondary Less like this/Never suggest this/Why/Settings; learning on/off and reset.
11. **Failure/fallback:** Corrupt/unsupported store does not execute actions or reactivate disabled categories. Use quiet in-memory behavior, preserve unreadable data and disclose storage failure.
12. **Difficulty:** Medium; correct exposure accounting matters more than mathematics.
13. **Effort:** Approximately 1–2 engineer-weeks within the cards/learning stage, not an additional independent estimate.
14. **Recommendation:** Ship with the first cards.

### Proposed deterministic model

Each category begins with positive weight a=2 and negative weight b=2. Affinity is a/(a+b). These are smoothing pseudo-counts, not calibrated probability of user benefit.

On a unique visible occurrence:

| Response | Proposed update | Additional behavior |
|---|---|---|
| Accept | a += 1 | Track execution completion separately; a provider failure is not a preference rejection. |
| Snooze | No negative affinity update | Increment bounded timing-bucket counts; one pending reschedule, no duplicate hint. |
| Dismiss | b += 1 | Suppress occurrence and apply category/global cooldown. |
| Ignore/expire | b += 0.25 | Only after adequate actual visible exposure; never penalize hidden/queued/sleeping/invalidated content. |
| Less like this | b += 3 | Extend category silence, proposed seven days. |
| Never suggest this | Explicit category disable | Stops generator/use immediately until user reenables it. No probabilistic override. |

Proposed relevance score, after hard validity/consent gates: clamp(0.55 × structuredEvidence + 0.20 × urgency + 0.25 × affinity − timingPenalty, 0...1). Initial threshold 0.75. Evidence and urgency are documented rule values, not LLM confidence. Three genuine dismissals of distinct otherwise-eligible occurrences additionally suspend that category for seven days. Three sufficiently exposed ignores also trigger a quiet period, rather than depending on tiny weight changes to stop nagging. These choices require fixtures and later product tuning.

Snooze timing uses a few meeting lead-time buckets, bounded within the allowed window. Change preferred timing only after at least five distinct occurrences and a clear outcome difference. Do not learn from repeat clicks on the same card. Never recommend earlier than source validity allows or explore noisier times to collect data.

Count “shown” only after the experience actually becomes eligible and is rendered on a visible shell. Submission, liveActivities membership, or queueing is not exposure. An unchanged original Calendar/battery/transfer alert does not count as a proactive exposure unless the optional proactive affordance itself is visible. Keep opened/accepted/completed separate. Source cancellation and privacy revocation are neutral, not ignore. Reset learned preferences and recent history while preserving explicit source/category opt-outs; provide a separate explicit Restore suggestion settings control.

Evaluate with controlled fixture sequences: cold start, all accepts, three dismissals, three exposed ignores, hidden expiry, snooze-then-accept, action failure after accept, duplicate responses, reset, timing shift and migration. Assert non-increasing unsolicited exposures under repeated negative feedback, and no reactivation of Never suggest.

## Feature C: Smart Return Briefs

1. **User value:** A short account of meaningful changes Notchium actually observed during a known absence.
2. **Implemented dependencies:** Display sleep/wake, typed transfer outcomes, Pomodoro records/catch-up, Calendar and battery snapshots.
3. **Missing work:** Away coverage state, session activation adapter, terminal-event hooks, ledger/cursor, dedup/ranking and temporary Brief renderer.
4. **Public APIs:** NSWorkspace sleep/wake and sessionDidBecomeActive/sessionDidResignActive notifications; existing source APIs. CGEventSource.secondsSinceLastEventType compiles, but is not needed for the initial trigger.
5. **Permissions/entitlements:** No new TCC; source-specific existing permission remains required.
6. **Free Release compatibility:** Yes for the narrow trigger. Session events are not treated as a universal unlock detector.
7. **Resource cost:** Bounded ledger scan at return; no overnight jobs, input monitor or recurring idle poll.
8. **Privacy:** Metadata only; runtime titles/URLs resolved from current owner, not archived in a Brief database.
9. **Architecture:** Compose normalized lifecycle input from existing display owner, add only missing public session observation, reduce in the proactive runtime.
10. **UI:** At most three initial items, hard maximum five; concise reason/coverage wording, explicit item actions and Got it. No feed.
11. **Failure/fallback:** No meaningful changes means silence. Missing history is omitted. Never claim completed downloads while quit/asleep if no source terminal fact was received.
12. **Difficulty:** Medium, dominated by coverage and cursor semantics.
13. **Effort:** Approximately 1–2 engineer-weeks.
14. **Recommendation:** MVP after cards/learning; workstation-wide idle return and pending-reminder inventory deferred.

Record a known away interval for sleep/display sleep or session inactivity. Wake/session activation only prepares eligibility; wait for explicit Notchium interaction before displaying a Brief. Coalesce duplicate didWake/screensDidWake/session notifications into one return identity and let Stage 21 finish its geometry reconciliation.

Use a sequence cursor plus process run epoch, not only a wall timestamp. Retain observed/receivedAt separately from occurredAt. On stop/crash/relaunch, close or mark the interval unknown. A Pomodoro deadline can be reconstructed from its own stored timer; label it “Timer ended at…” rather than evidence that the app observed everything while stopped. No cold-launch unsolicited “while away” brief.

A proposed minimum away interval is ten minutes. Deduplicate transfer results by epoch+ID, Calendar by occurrence, timer by record ID, and power by meaningful condition transition. Prefer imminent Calendar, relevant timer completion, significant transfer completion, then actionable critical power state. Do not include ordinary charger chatter, unchanged Shelf items, or fabricated peripheral battery information.

Advance the cursor to the included cutoff only when the user acknowledges/acts or consciously dismisses the Brief. On expiry, mark that return Brief consumed so it cannot nag on every open; unselected low-ranked old items expire rather than becoming an activity feed. Incoming events after the cutoff belong to a later interval.

For users who simply leave an awake Mac, there is no new observer of general keyboard/mouse activity in the MVP. A long interval between Notchium opens can support separately worded “Since you last opened Notchium” on explicit open, not a claim that the user was away. True machine-idle return detection needs a separate event/energy/privacy decision and is not a blocker.

## Feature D: Prepared One-Click Actions

1. **User value:** Preview a small exact setup sequence, then approve it once.
2. **Implemented dependencies:** ShortcutService.run, Caffeine controls, Pomodoro controls, CameraModel and current meeting Join.
3. **Missing work:** Typed plan, source/current-state preflight, approval binding, awaitable results, run/step state, cancellation and safe retry.
4. **Public APIs:** Existing NSWorkspace, AVFoundation, IOPM and Apple's Shortcuts CLI.
5. **Permissions/entitlements:** Existing per-step permissions; no blanket “automation access.” A user Shortcut can request its own permissions.
6. **Free Release compatibility:** Yes for ordinary Caffeine and user Shortcuts; closed-lid helper and generic Focus control excluded.
7. **Resource cost:** No preparation side effects; one bounded execution task after approval. Camera energy only while user-requested preview is open.
8. **Privacy:** Do not pass Calendar text/files into a Shortcut by default. Pinning a Shortcut does not prove it is local or reversible.
9. **Architecture:** Composition-owned ActionBroker; candidate generators receive no executor/provider reference.
10. **UI:** Exact ordered steps, unchecked optional additions, one Start/Prepare approval; visible running/succeeded/failed/skipped/uncertain states.
11. **Failure/fallback:** Stop remaining dependent steps after failure; retain successes; retry one failed safe step with renewed preflight/approval. No automatic external retry.
12. **Difficulty:** Medium–high, particularly existing implicit Focus coupling and result contracts.
13. **Effort:** Approximately 1.5–2.5 engineer-weeks after single-action broker support.
14. **Recommendation:** Limited MVP, Ask every time; automatic routines remain post-MVP and separate approval.

### Narrow allowlist and execution protocol

Initial actions: joinCurrentMeeting(occurrenceToken), showMirror, ensureCaffeine(duration), startPomodoro(duration), runPinnedShortcut(pinID), revealObservedTransfer(transferID), addObservedTransferToShelf(transferID). No arbitrary URL/string/file-path executor, shell/AppleScript, clipboard operation, file deletion, app UI control, or generic model tool.

The broker resolves IDs through existing owners and validates:

- Source consent, compiled capability, permission, freshness/revision and deadline.
- Pin remains enabled, explicitly selected, exact UUID/name matches; a changed definition of the external Shortcut cannot be attested by Notchium.
- Meeting URL still belongs to the current authorized occurrence and passes the supported allowlist.
- File still exists, belongs to an observed completed transfer and remains accessible; the broker does not invent access.
- Caffeine is not busy; an existing longer/indefinite user session is not silently shortened.
- Pomodoro is ready for the intended focus phase; never restart a running timer, reset a break, or change saved defaults merely to match a plan.
- Camera preview is an explicit visible step; permission UI stays with CameraModel and its native interaction lease.

For protected source preflight, a cached view snapshot is not sufficient when its freshness/authorization cannot be established. Add an awaitable owning-boundary validation/result contract that can reuse the existing source refresh and acknowledge the resulting revision before dispatch. Do not build a second query pipeline. An external event can still change between validation and URL handoff; checks minimize that race, not create a transaction across Calendar and another application.

Reserve the run ID and source/plan revision synchronously before the first await. Approval is an ephemeral broker-owned record bound to candidate, selected steps, order, parameter values and plan revision; deserialized plans cannot manufacture it. Every await checks cancellation/run generation and source revision before the next side effect. State changes that expand or materially alter the plan require a new preview.

Caffeine's current command returns Void and schedules its own task. QuickActionRunner.run also returns Void; CalendarActivityModel's opener does not expose NSWorkspace's result. Add small awaitable typed commands/outcomes at their owning boundaries before treating them as broker steps. Do not bypass models with service calls and duplicate expiry, tracking or UI state.

Pomodoro currently calls FocusModeModel automatically when timerControlsFocus is configured. A bundle that separately runs Work Focus and then starts Pomodoro can run that Shortcut twice. Explicitly choose one owner: either preview/includes the timer's configured coupling as the single step, or introduce a narrowly scoped start intent that suppresses only that already-previewed coupling for this run. Preserve manual timer behavior. This decision needs focused regression tests before bundles ship.

Do not assume a bundle can open Mirror while the notch stays collapsed: existing collapsed/panel-close behavior stops capture. Broker UI preparation must deliberately open the existing shell before showMirror. If the subsequent URL action changes app activation, preview lifecycle still follows the existing owner.

Local ensure-state actions can be idempotent. Opening a URL or running an arbitrary Shortcut is not guaranteed idempotent. CLI exit zero confirms successful Shortcut execution by Shortcuts, not that Work Focus is now on or that a meeting was joined. NSWorkspace open confirms a handoff request, not user attendance. Record those honestly as handoff/Shortcut completion, not verified world-state changes.

On cancellation, stop unstarted steps and owned waits; do not automatically undo successful actions or another user's later changes. Killing a CLI process cannot undo a dispatched Shortcut. Termination/crash produces an uncertain run receipt and no replay on launch. Persistent run records prevent Notchium from auto-retrying, but cannot provide distributed exactly-once behavior. Retrying an uncertain external step requires an explicit user choice.

Meeting Preparation example: open the expanded shell, preview user-selected steps, run the selected Shortcut if included, show Mirror if requested, then offer Join as a clearly separate final click by default. A user may explicitly include Join in the displayed sequence. Start Work: exact pinned Shortcut, finite Caffeine, requested focus session. Unchecked steps do not execute.

## Feature E: Routine Discovery

1. **User value:** Offer to save a repeated Notchium setup as a user-owned Home routine.
2. **Implemented dependencies:** Existing action entry points/pins and duration values.
3. **Missing work:** Successful action receipts, normalized sequences, distinct-day aggregates, editor and a new typed Home routine entry.
4. **Public APIs:** None beyond existing actions; future export to Shortcuts would need separately implemented App Intents.
5. **Permissions/entitlements:** Explicit product opt-in; no app/window/browser/input observation.
6. **Free Release compatibility:** Yes for internal routines. App Intents/export feasibility is a later scoped check, not current support.
7. **Resource cost:** Small short sequences and aggregate comparison after owned action completion; no background mining loop.
8. **Privacy:** Only enum action, selected opaque pin, duration bucket and local day. No titles, general app usage or Shortcut contents.
9. **Architecture:** Append broker/manual-owner completion receipts to bounded input; pure sequence matcher; same scorer/gate and user-owned storage.
10. **UI:** Show exact evidence such as five successful sequences across five days; Create routine preview/editor and explicit Save. Default manual invocation.
11. **Failure/fallback:** Deleted pin invalidates routine; ambiguous pattern produces no suggestion; synthetic/broker-generated repetitions cannot reinforce themselves.
12. **Difficulty:** Medium.
13. **Effort:** Approximately 2–4 engineer-weeks after usable real action history exists.
14. **Recommendation:** Post-MVP, opt-in; automatic triggers require a separate stage.

Proposed thresholds: same ordered 2–3 successful actions within five minutes, at least five occurrences across four distinct local days in a rolling 30-day window; maximum one discovery suggestion per pattern per 14 days. Preserve exact user-selected durations initially; avoid fuzzy routine expansion. Failed/cancelled actions, double-clicks, and executions from an existing routine do not count as discovery evidence.

Current UI commands do not all publish these events. Routine Discovery can be entirely Notchium-owned, but cannot be implemented entirely from already-exposed streams without adding event hooks at the manual action owners. Add those after the MVP, not raw action surveillance now.

HomeConfiguration currently stores QuickAction, not a multi-step routine. Extend its versioned schema deliberately rather than encoding routine JSON into a URL target. A native routine does not silently create or edit a macOS Shortcut. If exported later, users own the final Shortcut and configure any automation explicitly.

## Feature F: Local Semantic Intelligence

1. **User value:** Optional classification of a selected upcoming event or a short explanation; deterministic evidence/actions remain sufficient.
2. **Implemented dependencies:** Event summaries; available Apple on-device text API.
3. **Missing work:** Optional adapter, structured output validation, locale/model gate, bounded request/cancellation and model-version fixtures.
4. **Public APIs:** macOS 26 SystemLanguageModel, LanguageModelSession, supportedLanguages/supportsLocale, availability; guided generation can be evaluated separately.
5. **Permissions/entitlements:** No provisioned entitlement for the basic SystemLanguageModel probe; Apple Intelligence eligibility/enabled/readiness gates apply. Custom adapters and Private Cloud Compute are excluded.
6. **Free Release compatibility:** Conditional; an ad-hoc/no-entitlement availability executable succeeded on this macOS 27 host. Full packaged inference on macOS 26 remains unverified.
7. **Resource cost:** Active model/session memory, latency and energy unknown for Notchium; no model prewarm/resident session while idle. One request at a time.
8. **Privacy:** Explicitly enabled source and semantic consent; minimum title/category text, no notes/attendees/URLs by default; model output memory-only. No cloud fallback.
9. **Architecture:** Enrichment adapter only; no ActionBroker tool access and no authoritative source/priority changes.
10. **UI:** Optional setting with availability explanation; rules-based card works immediately. Avoid advertising unsupported precision.
11. **Failure/fallback:** Device ineligible, Apple Intelligence off, model not ready, unsupported locale, refusal, context limit, cancellation and timeout all return to deterministic copy.
12. **Difficulty:** Medium, including evaluation and unpredictable resource use.
13. **Effort:** Approximately 2–4 engineer-weeks plus model/runtime validation.
14. **Recommendation:** Optional post-MVP; neither required nor preloaded.

The SDK marks SystemLanguageModel and its original session/text APIs available on macOS 26.0. Model availability has deviceNotEligible, appleIntelligenceNotEnabled and modelNotReady cases. Apple Intelligence requires eligible hardware and supported language/region; Apple documents regional restrictions including China mainland. arm64 by itself is not a guarantee of model eligibility. Use runtime availability and supportsLocale; do not freeze today's OS-wide language list into app capability code. [Apple availability guidance](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [language and locale guidance](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models), [current hardware and region requirements](https://support.apple.com/en-ca/121115).

Apple describes the framework's macOS 26 introduction as access to the on-device model on eligible enabled devices. Its later image and broader model APIs are distinct versioned capabilities. Reevaluate prompts on supported OS/model updates. [Apple framework introduction](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/), [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels).

Do not equate generated “0.93 confidence” with calibrated probability. Require a constrained category, validate outputs, and restrict semantic enrichment to a small ranking/copy influence. A valid meeting URL remains necessary for Join. Calendar titles and screenshot text are untrusted model input; instructions in them cannot become authorized actions. At serious/critical thermal state or Low Power Mode, skip/defer semantic work and release owned sessions.

## Feature G: Explicit Screen-Aware Assistance

1. **User value:** At explicit invocation, share one selected window and obtain a local OCR explanation or, where supported, image interpretation.
2. **Implemented dependencies:** Native presentation/cancellation patterns; no current screen-assistance implementation.
3. **Missing work:** Source picker, capture service, pixel/text bounds, model/OCR adapter, result UI and cleanup evidence.
4. **Public APIs:** SCContentSharingPicker, SCContentFilter, SCScreenshotManager.captureImage; Vision VNRecognizeTextRequest on macOS 26. Foundation Models Attachment<ImageAttachmentContent> requires macOS 27.
5. **Permissions/entitlements:** Explicit system sharing consent; direct capture routes may require Screen Recording TCC. No Accessibility, microphone, camera, broad disk, or communication entitlement.
6. **Free Release compatibility:** Conditional for capture consent/runtime; macOS 26 fallback is bounded OCR/text interpretation, not general image understanding. No paid model.
7. **Resource cost:** Active pixel buffers/OCR/model can be expensive. One still only; cap dimensions and release buffers. No idle task.
8. **Privacy:** Nothing before invocation; default single window; display sharing an explicit broader choice. No screenshot/text persistence or logs.
9. **Architecture:** Separate optional service/feature; never feed screenshots into the proactive runtime or attach desktop tools to the broker.
10. **UI:** Choose scope, clear local-processing disclosure, Analyze/Cancel, visible progress/result; no autonomous Show me/UI manipulation.
11. **Failure/fallback:** Picker cancelled, permission denied/revoked, window removed, protected/empty content, unavailable model or OCR failure produces explanation and stops. Never silently broaden to display capture or cloud.
12. **Difficulty:** High for robust privacy/lifecycle and useful analysis.
13. **Effort:** 1–2 engineer-weeks for an isolated feasibility spike; roughly 4–8 additional weeks only if results justify a product feature.
14. **Recommendation:** Experimental, separate from MVP.

Apple recommends the native content picker for scoped selection. Picker-authorized capture can avoid a separate broad capture-permission flow, whereas direct enumeration/capture follows Screen Recording authorization. The precise picker → one-shot screenshot behavior and consent renewal on ad-hoc macOS 26/27 apps need a native spike; compilation alone does not prove the UX. [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [system picker](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker).

Proposed capture bound: longest edge 1,600 pixels and at most 2.56 million pixels; one four-byte-per-pixel image alone is about 10.24 MB before copies/OCR/model overhead. This is arithmetic, not measured resident memory. Analyze after downsampling, cap OCR output, allow one outstanding request, drop references on cancellation/close/sleep, and never retry capture without another invocation. Best-effort buffer release cannot guarantee physical erasure of every framework-owned copy or swap page; avoid promising secure memory wiping.

On macOS 26, OCR can support text-focused assistance but not full visual understanding of arbitrary charts/layouts. On macOS 27, image attachments compile with explicit availability gating; practical model quality, memory, device eligibility and packaged free-build inference remain hardware validation items. Continuous capture, session-based background capture from the report, AX inspection and autonomous desktop control are excluded from this proposal.

## C. Architecture proposal

~~~mermaid
flowchart TD
    S[Existing services and feature owners] --> A[Explicit composition adapters]
    D[Stage 21 display and presentation state] --> A
    A --> P[Consent and minimum projection]
    P --> R[Proactive runtime: bounded context and ledger]
    R --> G[Pure candidate generators]
    G --> Q[Pure scorer and interruption eligibility]
    Q --> C[ActivityCoordinator: ranking, slots and lifetime]
    C --> V[Existing shell plus temporary proactive renderer]
    V --> U[Typed user response]
    U --> L[Pure feedback reducer and local store]
    L --> Q
    U --> B[Action Broker: exact preview approval and preflight]
    B --> E[Existing authorized action owners]
    E --> L
~~~

### Small proposed component set

| Location | New responsibility | Explicit non-ownership |
|---|---|---|
| NotchiumCore/ProactiveModels.swift and focused adjacent value files | Source consent, opaque source/occurrence tokens, minimal context values, candidate/revision/deadline, action enum/plan, response/outcome/store DTO contracts. | No AppKit, service construction, persistence I/O, generic dictionary payload or callable executor. |
| New NotchiumProactiveFeature target | One MainActor runtime with owned lifecycle; pure rules, scorer, interruption decision and feedback reducer in small files; renderer later. | No platform observation, direct external API calls, copied timer/transfer/display state authority. |
| NotchiumFeature/Proactive/ProactiveComposition.swift | Translate existing model callbacks into minimal typed inputs; inject owners and broker; construct once at root. | No global event bus or all-purpose root view model. |
| NotchiumFeature/Proactive/ActionBroker.swift | Validate exact user approval, resolve allowed IDs, reserve run before awaits, manage step outcomes and cancellation. | No candidate invention, arbitrary script/URL executor, unconditional retry or inferred consent. |
| NotchiumPersistence/SuggestionStore.swift | Versioned bounded aggregates/tokens/run receipts with atomic ordered writes, migration, clear/reset. | No raw context database, Calendar/file payload archive, cloud, or unnecessary SwiftData/SQLite dependency. |
| NotchiumServices, only when needed | Missing public session/energy source; durable occurrence projection inside existing Calendar adapter. | No second EventKit store, battery watcher, folder observer, fullscreen scanner or input monitor. |
| NotchiumDynamicIsland, focused additions | Optional renderer contract and candidate token/destination; explicit suggestion eligibility/visibility/removal seam after coordinator resolution. | No provider I/O, scoring, learning, broker execution or replacement ranking. |

ContextSnapshot is an immutable projection, not another truth store. Source revision and validity accompany each field. Runtime receives only enabled projections and clears them on disable/revocation. Explicit adapter functions/callbacks are sufficient; SignalAdapter need not become a protocol per source. Rules/scoring/policy are functions, not separate long-lived services.

Observation answers what happened; inference produces a proposal; interruption decides whether to submit it; execution accepts only an exact user-authorized plan. Provider-facing protocols stay in Services; pure decisions stay outside views. Inference receives no broker or service dependency. UI forwards an explicit intent to the composition boundary.

### Coordinator integration decisions

ActivityCoordinator retains priority, coalescing, baseline/transient arbitration, redaction, primary/secondary slots and visible lifetime. NotchiumDisplayCoordinator retains display, sleep, fullscreen evidence, topology and panel continuity. DynamicIslandPresentationModel/NotchPageModel retain expansion, manual selection, auxiliary leases, page session and camera close. New code submits eligible activities; it never opens a panel directly on inference.

Use source semantics for meeting/battery/transfer enrichment, avoiding duplicate source notifications. Use one separate suggestion category only for standalone Briefs/later routine suggestions, with low priority and routine interruption importance. Do not misuse the currently critical-priority notification activity kind.

Priority alone is insufficient: ActivityPriorityPolicy ranks any transient ahead of all baselines. The proactive submission gate therefore refuses unsolicited replacement of an active transfer/running focus timer or an existing critical/high-priority transient. It also defers in expanded/manual/auxiliary/drag/Mirror sessions and by default in all fullscreen contexts. Existing fullscreen policy for other sources remains unchanged. A matching existing Calendar reminder can expose eligible optional actions without submitting a competing transient.

Focus unknown remains unknown. A manual Pause suggestions control and optionally quieting during Notchium's own running focus session are supported substitutes. A pinned Work Focus Shortcut is an action, never an observation or proof of status. No undocumented preferences, Focus databases, distributed notification names, or Focus Filter entitlement assumptions. Apple's documented communication-notification/Focus integration uses the relevant capability; the repository's runtime entitlement guard is the decisive free-build boundary. [Apple Focus integration](https://developer.apple.com/documentation/usernotifications/handling-communication-notifications-and-focus-status-updates).

Existing presentationDidResolve is internal and correctly fires after slot assignment. Add a narrow typed read/notification seam for resolved eligibility and actual proactive exposure; do not observe partially assigned @Published state as truth. Distinguish removal reasons: user dismiss, open/activate, source invalidated, timeout, stop and policy withdrawal. Learning must not live inside the coordinator.

Reevaluate only on meaningful source changes, completed presentation transitions, feedback, permission changes and the next actual eligibility boundary. Use one cancellable nearest-boundary task for pending candidates, not per-candidate loops. Deferred expired candidates are discarded silently. Visible timeout remains coordinator-owned. Generation and revision checks bracket every asynchronous read/store/action completion.

AppClock.now currently returns wall Date, despite older prose calling it monotonic. Keep absolute calendar/timer relevance in wall time; use an injected monotonic elapsed-time input for within-process cooldowns and exposure durations. Persist only wall-date bounds across runs and handle clock jumps conservatively, clearing stale candidates. Do not refactor the entire existing clock system as a prerequisite.

## Proactive UI feasibility

The existing [524 × 266 expanded shell and 740 × 322 panel](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumDynamicIsland/NotchPanelLayout.swift:42) remain fixed. Navigation consumes 32 points, leaving 234 before interior insets. Existing 30-point horizontal insets yield approximately 464 points of card content width. A card's header, explanation, controls and footer must fit inside that budget; the report's large mockups cannot be copied mechanically.

Propose a temporary interior surface using the existing Mirror-style retained-page pattern. It appears only after deliberate activation of a hint or opening an already-related source activity. It is not another navigation page, window, permanent Home section or activity feed. Returning restores the current page/session. While covered, retained pages publish not-visible and are disabled/hidden from accessibility, as Mirror already does.

| Before: current behavior | After: proposed additive behavior | Why |
|---|---|---|
| Calendar alert offers Join/open Calendar. | Same source identity can open a short contextual card with Join and optional Preview camera/setup. | Reuse timing and avoid duplicate meeting alerts. |
| Battery event reports severity. | Related work advice is available on intentional expansion; existing critical warning stays intact. | Learning cannot weaken essential safety feedback. |
| Transfer batch reports Done/Failed and Shelf destination. | Eligible completed file can offer Reveal or Add to Shelf after preflight. | No guessed semantics or duplicate completion banner. |
| Generic transient activation consumes its hint and opens a page. | A suggestion token opens its temporary interior and records Opened, without executing its plan. | Expansion is navigation, not authorization. |
| Mirror covers mounted pages and stops on close. | Proactive surface uses the same visibility discipline and yields to Mirror/native interactions. | Preserve lifecycle and avoid unnecessary hidden rendering. |
| Source/model updates may be frequent. | View reads only selected card/execution state; transfer percentage and clock ticks never invalidate the whole proactive subtree. | Preserve Stage 22 invalidation discipline. |

Use Stage 23 ExpandedPageStyle, NotchMotion and NotchAccessibilityPreferences. No new glass stack, animation numbers or looping pulse. Hint has one glyph and short reason/time, no multiple inline execution controls. Explicit buttons have press feedback and progress only for actual operations. Dismiss and Snooze are ordinary controls; secondary menu exposes Why, Less like this, Never suggest this and Settings.

Keyboard: use deliberate expanded-panel focus, Tab/Shift-Tab order, Space/Return only on the focused explicit button, Escape closes the interior or cancels unstarted work without implicitly executing/undoing anything. No new global keystroke observation. VoiceOver exposes the reason, time validity, each action, disabled reason and per-step outcome; avoid repeated speech for countdown ticks. Never auto-steal focus or announce every passive source refresh.

Reduce Motion uses existing reduced/static/crossfade paths; Reduce Transparency/Increase Contrast remain inherited. Test long localized names, right-to-left text, keyboard focus while overlay swaps, truncation and scroll/footer reachability. Brief defaults to three compact items; five is a cap requiring layout verification, not a promised simultaneous fit.

Sleep and session inactivity withhold suggestions. Wake alone does not prove unlock, and Stage 21's presentation heuristic does not prove screen sharing. Use conservative generic new hint copy and explicit interaction before a return card; disclose detection limits, provide Pause, and avoid exposing extra personal text through passive new surfaces. Existing Calendar/source presentation is not silently redesigned.

Notchless owner currently has status/Settings menu-bar fallback, not a full interactive activity surface. MVP must fail quietly there. A bounded explicit menu-bar “Review suggestion” destination may be a separately scoped enhancement; adding external overlays or changing display ownership is excluded.

## D. Permissions, data-source policy and security

Proactivity starts OFF for existing users and fresh installs. Enabling a category does not imply all data sources or action steps. Sensitive/optional sources, routine learning, semantic enrichment and screen assistance remain independently OFF until chosen.

Turning a proactive source off means “stop using it for suggestions,” not “turn off the existing Calendar/Shelf utility” or revoke macOS authorization. Settings must distinguish these operations.

| Source | Exact data used | Minimum access and request timing | Proactive persistence/retention | Disable/revocation behavior |
|---|---|---|---|---|
| Calendar | Opaque occurrence token, start/end, all-day, supported meeting URL and title only for intentional card. No attendees; no raw notes/location copied. | Full Calendar TCC; existing NSCalendarsFullAccessUsageDescription. Existing source requests on start; proactive enables no new prompt. Any future permission-flow change needs a separate task. | Context memory-only; durable dedup token at most seven days. Existing selected calendar preference remains. No new Calendar history scan. | Stop Calendar candidates, remove active enrichment and resolve no actions. Clear copied fields/tokens for disabled source. Other cards continue. |
| Focus status | Availability and optional Boolean only. | Communication Notifications capability required by current implementation; unavailable free profile. No request/poll fallback. | Memory only. | Display Unavailable; use manual pause/owned timer policy. Do not label unknown Off. |
| Shelf | Existing item ID, available state, count/time where actually relevant; resolve filename/path only for user-visible action. | Existing user drag/chooser access; security scope only where applicable. No new folder permission. | No duplicated bookmarks/files; existing 24-item/seven-day store remains. | Purge proactive projections; file actions revalidate owner availability. |
| Transfers | Epoch/ID, operation, terminal state, byte total if supplied, dates, reference to final URL. | Existing selected-folder monitoring/protected Downloads access. Current implementation probes folder on start; no new generalized folder picker/scanner. | Payload/URL memory-only for actionable ledger; terminal metadata <=24 hours and 128 entries. Cross-launch events whose resources cannot be resolved are omitted. | Clear candidates/resource handles; no retry/access escalation. Folder denial disables only file steps. |
| Pomodoro | Session/phase/run state, requested duration, deadlines and actual completion record ID/time. | No TCC; category consent. | Proactive terminal metadata <=24 hours; no duplicated statistics archive. Existing timer/history unchanged. | Stop proactive use; timer remains operational. |
| Caffeine | Current mode, finite selection/expiry, busy/result state. | No TCC for ordinary idle assertions. Explicit approval for an action. No privileged helper. | Memory only except outcome enum/run receipt. | Stop using state; disabling suggestions must not end a user's existing assertion. |
| Battery/power | Charge fraction, connected/charging, availability, known crossing; Low Power Mode/thermal state. | Public IOKit/ProcessInfo, no TCC. | Only meaningful bounded terminal/condition metadata, <=24 hours; no high-frequency sample history. | Clear optional advice. Existing battery warnings remain. |
| Shortcuts | Explicit pin ID, stored UUID/name, enabled state, per-run outcome. | Product selection; native Shortcut-specific prompts at explicit execution. Discovery only settings/preflight, no background inventory loop. | Reuse Home pins; run receipt <=24 hours; no library names/content added to learner. | Unpin disables future steps. Deleted/renamed/disabled fails preflight with relink UI. |
| App/session lifecycle | Run epoch, sleep/wake/session-active evidence, explicit Notchium interaction and coverage boundaries. | Public Workspace callbacks, no input/AX permission. | Coverage/cursor metadata <=24 hours. | Cancel pending work/observers; wake alone does not show a Brief. |
| Reminder | None for initial Brief. Optional future app-created reminder ID/due/completed projection would need new contract. | Existing Reminders full access is broader than creation. Do not request it for this MVP. | None new. | Omit pending-reminder content; Quick Reminder remains unchanged. |
| Clipboard | None. | No new pasteboard read or prompt. | None. | Existing capture/storage unaffected. |
| Camera | Authorization/status/device only on chosen Preview step; frames stay in existing preview service. | Camera TCC only at explicit first use; NSCameraUsageDescription already exists. No microphone. | No frames or device-history archive. | Existing owner stops capture on close/sleep/denial; Join still works. |
| Screen | None in MVP. Experimental single user-selected still only. | Native sharing consent/direct Screen Recording as required by tested route; never AX. | Memory only, request lifetime; no save, upload, logs or proactive ledger. | Cancel and release image/OCR/model state; never broaden capture. |

Reading Calendar events/reminders requires full access; EventKit has no read-only grant. Sandboxed macOS editions additionally need the Calendar entitlement, whereas the free unsandboxed profile still uses TCC authorization. [Apple EventKit access model](https://developer.apple.com/documentation/eventkit/accessing-the-event-store).

Apple's CLI supports selected name/identifier invocation and exit status, and input-asking Shortcuts can wait for the user. Keep Apple's fixed executable and argument arrays. Listing is supported; silent creation/modification of a person's Shortcut library is not part of the current contract. [Apple command-line Shortcuts](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac).

### Settings and storage

One Settings category, Suggestions:

- Enabled; Pause for…; Upcoming meetings / Work battery advice / Completed transfers / Return Brief.
- Data used, with each source's enabled, denied, unavailable or not-selected state and a plain explanation.
- Adapt timing and frequency; category enable controls; reset learned preferences; clear recent suggestion history.
- Exact action selections/pins, with Ask every time. No global permission to “do useful things.”
- Separate later experimental settings for routine discovery, semantic enrichment and screen assistance.

Use a dedicated versioned JSON archive and ordered utility-queue atomic writes, following existing stores but adding explicit write errors and durability acknowledgment for execution receipts. Proposed bounds: 128 Brief facts/24 hours; 256 recent feedback receipts/30 days; 64 durable dedup tokens/seven days; 32 run receipts/24 hours; 32 fixed category/timing aggregates with effective observation weight capped at 100. Rescale paired positive/negative weights deterministically when capped. Explicit category disables survive until changed; aggregate weights survive until reset.

Resource payloads stay in memory and are resolved through current owners. Persist no titles, URLs, filenames, paths, bookmark copies, screenshots, clipboard content or transcripts. A 256 KiB total archive cap is a proposed implementation guard. Do not reuse Clipboard's payload key or create a general sensitive context database. Aggregate storage is local metadata; if later persistence needs personal payloads, design a separate encryption/Keychain review before widening it.

Writes occur only for material responses/coverage/results, coalesced where noncritical, never every snapshot/tick. Flush on graceful shutdown. Before external action dispatch, durably record an in-progress run/step so restart cannot replay it. If that write fails, block the bundle rather than claim durable duplicate protection. An interrupted receipt remains uncertain; do not resume it automatically.

Disabling a source invalidates current candidates and source-specific retained facts/tokens immediately. Reset/clear uses serialized ordering so an older queued save cannot repopulate cleared data. Preserve unsupported schemas/corrupt archives rather than overwriting them. Update with a same-bundle-ID app preserves app storage in principle, but ad-hoc updates can affect TCC/Keychain identity; fresh install/update/relaunch tests remain mandatory.

### Concrete STRIDE review

| Threat | Reachable concern | Planned boundary |
|---|---|---|
| Spoofing | Candidate contains a stale meeting or wrong Shortcut identity. | Resolve opaque IDs/current revisions at broker; exact pin/UUID/name and URL allowlist; explain source. |
| Tampering | Local archive or untrusted Calendar/Shortcut input alters a plan. | Typed decoding, schema/bounds checks; broker constructs approval privately; revalidate source/action IDs. Same-user privileged tampering is not prevented by JSON. |
| Repudiation | User cannot tell which steps ran or whether a crash dispatched a Shortcut. | Local bounded outcome/run receipts and honest uncertain state; no claim of exactly-once external execution. |
| Information disclosure | Titles/URLs/screenshots appear in logs/persistence/model input. | Minimum projections, no payload logs, ephemeral resource handles, explicit semantic/screen opt-in, no cloud fallback. |
| Denial of service | Callback storm, slow Shortcut, giant screenshot/archive, pending tasks. | Bounded queues/history/plans, coalescing, single execution, generation checks, cancellation, pixel/output caps. |
| Elevation of privilege | Inference runs arbitrary URL/script or auto-starts hardware. | Closed action vocabulary, no executor in generator, exact explicit preview approval, existing service permissions, no privileged helper/AX. |

No Full Disk Access, new MVP Screen Recording, broad Accessibility, continuous microphone/camera, unrestricted filesystem access, Notification Center scraping, browser tracking, cloud context, background telemetry or private frameworks.

## E. Resource forecast, budgets and measurement

No proactive benchmark exists because the feature is not implemented. Expected cost is event-driven integer/value processing and a small local archive. The numbers below are proposed acceptance budgets, not forecasts measured on hardware or claims about the current app.

| Incremental metric | Proposed MVP budget | How to assess |
|---|---|---|
| Idle CPU with no deadlines/changes | Target indistinguishable from off; investigate sustained delta >0.1 percentage point of one core. | Repeated matched 15-minute Release Time Profiler/resource runs with noise intervals. |
| Idle wakeups | Zero proactive periodic wakeups; no repeating timer. | Timer/task audit plus Instruments/System Trace comparison. Genuine one-shot deadlines counted separately. |
| Resident memory | Target <=5 MiB steady-state incremental; no growing retained slope. | Allocations/VM tracking after warmup, matched before/after and hour-long soak. |
| Candidate evaluation | p95 <10 ms; hard investigate >50 ms per bounded pass. | Redacted signpost around pure generation; fixture sizes and source bursts. |
| Scoring | p95 <1 ms for <=8 candidates. | Deterministic microbenchmark and trace; record hardware/optimization. |
| Eligible input to submitted activity | p95 <50 ms rules-only; source-owned coalescing reported separately. | Signpost meaningful input → policy → coordinator resolution. Do not hide existing 250 ms source coalescing. |
| Activity presentation | No inference wait; no new repeatable main-thread stall over one display frame. | SwiftUI/Animation Hitches; compare actual screen refresh rates. |
| Return Brief reduction | p95 <50 ms for 128 facts; outer rules-only target <250 ms. | Controlled ledger fixture plus real wake reconciliation timing. |
| Persistence | No idle writes; one coalesced save per feedback burst, normally <=1 write/5 s for noncritical history. Explicit consent/reset/run receipt may write immediately. | File Activity, injected store counters, write errors and shutdown flush. |
| Storage | <=256 KiB bounded metadata archive. | Worst-case encoding/retention/migration fixtures. |
| Network | Zero requests from observation/inference/learning/Brief preparation. | Network trace and source inspection. Explicit Join/Shortcut may cause other apps to network; do not claim those actions are offline. |
| Camera/model/capture | Zero proactive idle sessions, buffers or capture. | Permission/session counters and Allocations. Explicit operations measured separately. |

No new continuously running observer-derived inference task, Calendar history scan, directory scan, model prewarm or hidden screenshot. New observation fans out existing owner events, coarsening before SwiftUI. Transfer percentages do not invoke scoring. Pending cooldowns use the next meaningful deadline and stop when no work exists. Prune bounded history on material writes/start, without a maintenance polling loop.

Low Power Mode/thermal serious: keep cheap essential deterministic paths functional; defer discretionary scoring maintenance and all model/capture enhancement; coalesce noncritical writes. Existing ordinary user-requested timer/Caffeine behavior is not silently changed. Record energy state through a narrow public adapter; no second battery stream needed for temperature/Low Power Mode.

### Controlled measurement plan

1. Build the same clean base and proactive revision with the free Release script's compile profile and optimization/coverage settings. For a diagnostic build, keep symbols separately; verify exact executable path/PID. Do not profile an installed different copy.
2. Use representative macOS 26 and current 27 notch MacBooks, including a lower-memory Apple Silicon device. Fix display topology/refresh, brightness, AC/battery condition, thermal state, Clipboard/Spotify/provider state and camera off. Record those conditions.
3. Alternate off/on order over at least three matched runs. Warm up five minutes; idle 15 minutes, then one-hour soak. Include no-enabled-sources, enabled-but-unchanged sources, paused Music, ongoing Pomodoro, coalesced transfer bursts, sleep/wake, expanded card, and repeated open/close/reset.
4. Capture Time Profiler, System Trace/wakeups, Allocations/Leaks, SwiftUI/Hitches, File Activity and available power/energy instrumentation. Use redacted counts/durations, never personal payloads. Inspect xctrace templates/export schema locally rather than assuming a named energy template exists.
5. Measure explicit camera, Shortcut and optional model/capture separately; do not attribute their expected active cost to idle inference. Repeat Low Power Mode and serious thermal simulations/real supported conditions.
6. Compare confidence/noise and report deltas with durations and device/OS/build identity. Stage 22's short Debug fixture results are not interchangeable with this evidence.

Release blockers: recurring idle work; unbounded backlog/log/tombstones newly introduced; persistent allocations after close/stop; capture/model activity while idle; unexplained reproducible CPU/wakeup/memory regression above budget; main-thread I/O/hitch from proactivity; unexpected network; storage write per source tick; broken resource cleanup under 100 lifecycle cycles. A noisy short trace is not proof of either regression or success.

## F. Staged implementation roadmap

Stage names below are proposals, not already-completed repository stages. Estimates are experienced-engineer effort assuming design/QA support, not elapsed schedules or commitments.

| Stage | Scope and prerequisites | Likely files/modules and interfaces | Acceptance/tests | Effort and blockers |
|---|---|---|---|---|
| 25A — Pure policy foundation | Consent/value models, candidate identity/revision/deadline, action vocabulary, deterministic policy and feedback fixtures. No live composition or UI. | Core focused models; new ProactiveFeature target depending initially on Core; tests/Package.swift; narrow documentation. Explicit now/elapsed/revisions inputs. | No providers, timers, I/O, broker side effects or production behavior; consent-off, stale/cancelled, unknown Focus, deadline, category-disable and duplicate-response tests. Existing architecture/build gates. | 3–5 days. No external blocker. Separate prompt provided. |
| 25B — Owned signal and action seams | 25A; minimal callbacks/projections at existing owners, stable Calendar occurrence token, store/migration and single-action broker outcomes. Still unexposed. | CalendarService projection; Calendar/Pomodoro/Caffeine/Files/QuickActions owning-boundary hooks; Persistence/SuggestionStore; Feature/ProactiveComposition and ActionBroker. | No duplicate native watchers; no extra prompts; terminal preservation; exact owner shutdown; awaitable result/duplicate-click/preflight tests; zero automatic dispatch. Fake stores/providers only by default. | 6–9 days. Resolve implicit timer-Focus coupling, transfer epoch/tombstones, Calendar identity and durability before exposure. Separate focused prompts per independent contract appropriate. |
| 25C — Cards and learning together | 25B; one meeting generator first, then battery advice/transfer follow-up; exposed feedback/reset and bounded renderer. | Proactive rules/runtime/views; DynamicIsland renderer/category/token/resolved-event seams; Settings; existing source card renderers. | No duplicate five-minute/battery/transfer banners; essential activities unaffected; all six feedback types; three-negative suppression; no execution on expand; fixed geometry and retained selection; keyboard/VoiceOver/reduced effects. | 15–20 days. Requires real layout/interaction QA; public exposure forbidden until learning/opt-outs work. Separate meeting+learning slice before other generators. |
| 25D — Narrow Return Brief | 25C; accurate terminal ledger/cursor and coverage; public session source and existing wake projection. | Runtime/ledger/store; Services session adapter; composition wake input; temporary Brief renderer. | One Brief per return, 0 items silent, max 5, cold-launch gaps honest, cancelled events absent, stale catch-up handled, duplicate wake/order fixtures, no idle loop. | 6–10 days. Real sleep/fast-user-switch and consent tests; pending reminders excluded. Separate prompt appropriate. |
| 25E — Limited prepared actions | 25B/C; reliable broker outcomes and user-selected plan. Initially Start Work and Meeting Preparation only. | Broker/run models, awaitable owner commands, preview/step status UI, store receipts. | Ask every time; preview order/params exact; no hidden Focus double-run; failed step retry only; duplicate click single reservation; cancellation/crash uncertain; no replay; no provider bypass or saved-default mutation. | 8–12 days. External Shortcut cannot provide rollback/exactly-once/world-state verification. Separate prompt per bundle appropriate. |
| 25F — Release hardening | All MVP slices; incremental resource instrumentation and dogfood. | Focused tests/fixtures, permission/settings docs, diagnostic counts, existing release verifier; no broad UI refactor. | Full suites/profile compilation, permission revoke/update/relaunch, accessibility/layout, hardware minimum OS, repeated lifecycle cleanup, budget gates and useful-surface evaluation. | 10–15 days plus observation time. macOS 26/fresh ad-hoc TCC/hardware evidence required. Separate validation prompt appropriate. |
| 26 — Routine Discovery | Stable MVP receipts and explicit opt-in; distinct-day patterns. | Owned manual action hooks, pure matcher, routine schema/Home editor. | Successful Notchium-only sequences; no self-reinforcement; exact edit/save; deletion/reset; manual-only default. | 10–20 days; data usefulness/false-positive evidence is prerequisite. Separate prompt after MVP. |
| Optional text enrichment | Stable deterministic precision and independent consent. | Services optional model adapter; bounded enrichment contract; tests/evaluation fixtures. | Works with every unavailable model state; no action tools/cloud; cancel/low-power fallback; OS/model regression corpus. | 10–20 days plus hardware/model QA. Separate spike, then scoped implementation if justified. |
| Experimental screen assistance | Explicit standalone approval, separate feature. | Optional Services capture/OCR/model adapter and independent feature UI. | Native selected-source consent; single still; cancellation/cleanup; 26 OCR fallback/27 image gate; no AX/background capture. | 5–10 day spike; later product work separately estimated. Not MVP prerequisite. |

Total engineering envelope for 25A–F: roughly 48–71 working days, approximately 10–15 engineer-weeks before contingency. Budget 12–18 engineer-weeks with integration/design/hardware contingency, and allow 2–4 weeks of real-use observation that may overlap implementation. The research's 14–18-week estimate is consistent with that broad envelope, but is not an empirical measurement. Do not compress trust/false-positive observation simply by adding engineers.

Every stage retains Stage 21 authority, Stage 22 generations/caches/task ownership, Stage 23 tokens/geometry/accessibility, Stage 24 free distribution and existing utility behavior. No stage is permission to implement the next one.

## G. Risks, blockers and fallback decisions

| Risk/status | Grounded mitigation/fallback | Release or stage gate |
|---|---|---|
| Focus entitlement: confirmed free-build blocker | Keep RealFocusService unavailable; manual Pause, owned focus-session policy, explicit selected Shortcut. | Never require generic Focus to enable the MVP. |
| Calendar authorization/full access | Reuse existing source/selection; no read-only claim or second prompt; fail closed and purge copied state. | Denial/revocation fixture and actual fresh-user test. |
| Calendar occurrence UUIDs: confirmed process-local | Opaque durable occurrence token at existing projection; bounded suppression and recurring/edit fixtures. | Before cards are exposed across relaunch. |
| macOS 26/27 APIs: confirmed version boundary | Compile for minimum target; separate image #available gate; original text session fallback. | Minimum-OS hardware inference/capture still unverified. |
| Shortcut rename/deletion | Exact UUID/name preflight; relink, never fuzzy substitute. | Mock tests; disposable user-owned Shortcut validation later. |
| Shortcut arbitrary effects / edited contents | Exact explicit step disclosure; no personal input by default; no automatically retried opaque step. | User understands external effects; no “safe/reversible” blanket promise. |
| Ad-hoc identity/TCC/update | Preserve distribution architecture/bundle ID; no helper/provisioned entitlements; real fresh/install/update tests. | Source build success does not certify Gatekeeper/TCC. |
| Persistence across updates/crashes | Versioned archive, bounded schema, ordered atomic writes, durability receipt, preserve unknown data, no auto-resume. | Migration/corrupt/future-schema/reset-race tests. |
| False positives/annoyance | Strong structured rules, opt-in, max exposures/cooldowns, initial learning, no no-URL meeting card. | Category precision/negative feedback reviewed before broader rollout. |
| Interruption conflicts: confirmed transient-vs-baseline semantics | Eligibility before submission; source-aligned enrichment; existing ranks untouched. | Music/transfer/timer/Calendar/HUD coexistence tests. |
| Stale callbacks/source changes | Generation/revision and cancellation checks before and after awaits; terminal facts from owning reducer. | Cancel/edit/disable/stop-restart race fixtures. |
| Duplicate bundle actions | Reservation before awaits, exact consent, awaitable owner results; handle timer Focus coupling. | Double-click and duplicate Shortcut-coupling regressions. |
| Partial failures | Stop dependent steps, successes retained, explicit safe per-step retry, uncertain external status. | Broker state machine/crash tests. |
| Sleep/wake/lock uncertainty | Coalesced lifecycle; wait for explicit interaction; bounded coverage and generic hints. | Native sleep/fast-user-switch, no assumption that wake means unlocked. |
| Prolonged idle/backlog | No loop; bounded runtime/storage; preserve service terminal semantics; do not add slow unbounded stream subscriber. | One-hour soak and callback-storm traces. |
| Existing TransferActivityModel.finishedIDs growth | Do not duplicate it in proactive state or “fix” it by unsafe eviction; an owner epoch/ack contract is needed for bounded terminal dedup. | Document baseline, exercise long sessions before transfer proactivity release. |
| Unsupported Apple Intelligence | Runtime availability/locale check; deterministic path always sufficient. | No model gate on essential action/presentation. |
| Privacy-sensitive collection | Source-specific OFF, narrow projection, no payload retention/logging; independent semantic/screen consent. | Disable/revoke/delete verified locally. |
| Discoverability/trust | Specific explanation and exact preview; user can explain what caused a card and what Start executes. | Formative sessions before beta; no AI branding for deterministic rules. |
| Notchless fallback | Silent unsupported presentation, manual existing utility access. | No new external overlay as workaround. |

## Deterministic testing strategy

Use TestAppClock with automaticallyAdvances=false, injected wall/elapsed time and UUIDs, fake providers/action adapters, explicit stream/task registration barriers, and temporary stores. No real Calendar, camera, Shortcut run, Keychain or personal file content in fixtures. Do not synchronize by arbitrary Task.yield counts or sleeps. UI/hardware checks are a separate controlled layer.

| Scenario | Required outcome |
|---|---|
| Meeting in five minutes with supported URL | One candidate/source enrichment, valid direct Join; stable occurrence token; no auto action or duplicate Calendar notification. |
| Meeting without URL/all-day/unsupported host | No meeting-setup candidate; current Calendar utility remains usable. |
| Calendar denied/write-only/revoked | No protected proactive reads/use; no repeated request; purge candidate, action revalidation fails. |
| Focus unavailable | Source reports unknown/unavailable, rules still work; manual/owned-session gate available. |
| Known Focus on in a fixture | Optional generic suggestion withheld; existing essential activity behavior unchanged. |
| Competing transfer/running timer/Calendar/volume | Low suggestion cannot replace protected activity; original identity, priority, expiry and baseline restore. |
| Three distinct dismissals | Category quiet period and lower affinity; no fourth unsolicited occurrence during suspension. |
| Three exposed ignores vs three hidden expiries | Exposed ignores quiet category; hidden/invalidated expiries do not alter affinity. |
| Repeated snoozes | One reschedule only, no rejection update; deadline clamp; no expiry-after-start replay. |
| Low battery during Pomodoro/Caffeine | Existing critical warning once, optional work advice only for crossing/valid work state; charge recovery clears it. |
| Return after sleep and duplicated wake events | One return identity/Brief after explicit input; dedup/rank known facts; no stale pre-sleep card. |
| Notchium previously stopped | No invented completion history or cold-start unsolicited Brief; reconstructible timer/current state honestly labeled. |
| Awake Mac with long interval between notch opens | No claim of workstation absence; optional manual “since last opened” wording only. |
| Shortcut deleted/renamed/disabled/ambiguous | Preflight fails, relink path, no replacement guessed/run. |
| Prepared plan partially fails | Successes retained; dependent steps not dispatched; retry only selected failed step after new validation. |
| Duplicate user click/late completion/cancellation-before-launch | One reserved run; stale completion cannot overwrite replacement; no orphan task/process. |
| Timer already coupled to Focus Shortcut | Exact one intended Shortcut dispatch; manual timer coupling remains unchanged. |
| Stale suggestion after cancellation/time change | Removed immediately; approval invalid, no old URL opening; revised time does not renew beyond absolute relevance. |
| Low Power Mode/serious thermal | Cheap rules remain usable; optional inference/capture deferred and resources released. |
| App termination/crash during execution | No pending-step replay; uncertain run surfaced only on deliberate review; local assertion naturally releases. |
| Upgrade/future schema/corrupt archive | Explicit opt-outs preserved; migrations bounded; unknown/corrupt file not silently overwritten. |
| Reset while save in flight | Older save cannot restore cleared history or lift Never suggest. |
| Transfer callback storm/5,040 permutations | Terminal exactly once per epoch; no late-active resurrection; bounded proactive consumer state. |
| 100 enable/disable/open/close/sleep cycles | Observers/tasks/resource handles gone after stop; no retained runtime, camera or model session. |
| Keyboard/VoiceOver/long copy/reduced effects | No focus theft, no hidden hit targets, exact button intent, footer reachable, fixed shell geometry. |

Existing suites to retain: ActivityCoordinatorTests, NotificationLifetimeTests, CalendarReminderTests, Stage21 activity/display/environment/presentation tests, Stage22 transfer/lifecycle stress, Stage19/23 Pomodoro, Stage11 QuickActions, camera/Clipboard lifecycle and ArchitectureTests. Expand only the suites/contracts actually changed in each stage; full package/Release/profile checks at exposure/release gates.

## Product evaluation

Local-only category counters initially. No background telemetry or raw-context export. Optional beta sharing requires explicit user consent and an inspected redacted export.

Useful surface rate = unique exposed suggestions accepted or explicitly marked useful / unique exposed suggestions. Acceptance alone is an operational proxy, not proof of usefulness. Accepted-to-completed rate = verified declared step completions / accepted plans, with URL handoff and external Shortcut completion separately labeled. A “joined meeting” result is not measurable through NSWorkspace alone.

Track dismiss, snooze, exposed expiry, Less/Never, category/source opt-out, repeated-unwanted recurrence within the suppression window, execution partial/error/uncertain rates, rule/presentation latency and incremental resources. Segment by category/timing, source availability and policy version. Counts for one occurrence do not increase merely because its hint refreshed or was snoozed.

Compare conservative enabled categories with their local disabled baseline during consenting dogfood. Review whether users understand why a card appeared and which exact steps would execute. Tune timing/density/threshold one variable at a time; never explore more interruptions merely to improve metrics. Increased Never suggest/opt-out or repeated unwanted surfaces is a loss even if acceptance rises.

Do not set statistical sample sizes or precision claims without actual rates. Require zero unauthorized actions and zero recurrence while explicit category disable is set. Require the deterministic three-negative quieting contract, no critical-source regression, and passed resource/permission gates. Broader rollout needs evidence of useful category behavior plus qualitative trust; suggestion volume, expansions and engagement time are not success metrics.

## Validation actually performed

| Check | Observed result and limit |
|---|---|
| Repository/settings audit | Clean main baseline; Swift package tools version 6.2, macOS 26; Xcode Swift language mode 6 and complete strict concurrency; Release flag NOTCH_FREE_DISTRIBUTION, no injected entitlements, no sandbox/hardened runtime. Release script explicitly propagates the free flag into package targets through OTHER_SWIFT_FLAGS. |
| Host/toolchain | macOS 27.0.1, build 26A434; Xcode 27.0, build 27A266a; Swift compiler 6.4; macOS 27 SDK; arm64. This is not minimum-OS runtime evidence. |
| Existing Release app compilation | Passed in isolated temporary derived data with signing disabled. Then passed again with release-script free-profile propagation (-D NOTCH_FREE_DISTRIBUTION), including NotchiumCore. No packaging/signing/notarization/launch. |
| Existing focused tests | 36 XCTest cases passed: ActivityCoordinator 11, CalendarReminder 10, NotificationLifetime 5, Stage21ActivityPolicy 3, Stage21DisplayState 4, Stage21EnvironmentProjection 3. |
| Free-profile tests | Two Swift Testing cases passed with NOTCH_FREE_DISTRIBUTION: compiled profile and unavailable helper controls. |
| macOS 26 API compile probe | Passed Swift 6 complete-concurrency typecheck at arm64-apple-macosx26.0: EventKit full-access API, original Foundation Models text/session/locale, Focus API symbol, SCK picker/still capture, Workspace session events, idle-time query, ProcessInfo power/thermal and Vision OCR. Probe functions were not called. |
| Image availability negative/positive probes | Ungated Attachment<ImageAttachmentContent> failed at minimum target with macOS 27 availability errors, as expected. The @available(macOS 27.0, *) version passed. |
| Ad-hoc model availability probe | Separate temporary executable, ad-hoc signed without entitlements: availability=available; en_CA locale supported on host. No prompt, private user context, text generation or image inference executed. |
| Shortcuts CLI inspection | list --help confirms --show-identifiers; run --help confirms name-or-identifier. No personal Shortcut inventory was listed and no Shortcut was run. |
| Research inspection | Text extracted from 44 pages; key flow/metrics rendered and inspected. |

Initial sandboxed Xcode attempt failed before building with Workspace/service-access errors; the same workspace passed outside that restricted sandbox through approved escalation. Existing warnings remain: Focus async-alternative suggestion and skipped App Intents metadata extraction. No production compile failure was hidden.

Tests and probes used isolated temporary outputs at /var/folders/0x/8tbmr8qs78z651gjnn7wyr680000gn/T/notchium-proactive-feasibility-gahjvaxl. Logs include focused-tests.log, free-profile-tests.log, free-release-build.log, api26-typecheck.log, image27-expected-failure.txt and the disposable Swift probe sources. These are temporary evidence, not shipped artifacts or performance traces.

No full suite, real Calendar data, permission dialog, camera, real Shortcut, model response, screen capture, new UI test, Instruments trace, fresh Gatekeeper/TCC/update path, or macOS 26 runtime was exercised in this study. No claim of measured proactive CPU/memory/battery cost or complete future-feature behavior is made.

## H. First implementation prompt

The separate [Stage 25A implementation prompt](/Users/marcusyu/Projects/notch/docs/PROACTIVE_INTELLIGENCE_STAGE25A_PROMPT.md) is copy-ready. It implements only pure consent/candidate/action value contracts and deterministic policy/feedback tests. It explicitly excludes live composition, production persistence, observers, action execution, UI and changes to existing behavior.

The plan is ready for review. Production implementation remains awaiting explicit approval.
