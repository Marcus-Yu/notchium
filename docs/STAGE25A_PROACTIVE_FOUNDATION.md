# 25A — Pure Proactive Intelligence Foundation

Implemented October 12, 2026 (America/Toronto). Stage 25A only; production remains unconnected.

## Implementation and exact file inventory

Modified:

- `NotchiumPackage/Package.swift`: adds the Core-only feature target and its separate test target; no production dependency or library product was added.
- `docs/ARCHITECTURE.md`: records the pure boundary and links this implementation note.

Added in `NotchiumPackage/Sources/NotchiumCore/`:

- `SuggestionIdentity.swift`: four categories, seven evidence sources, disabled-by-default independent `SourceConsent`, opaque source epoch/occurrence/revision and revision-independent `SuggestionKey`.
- `SuggestionCandidate.swift`: structured evidence, supporting owner revisions, candidate deadlines, optional interruption importance, source freshness/availability projection, meeting input and the seven-case `ProactiveAction` vocabulary.
- `ProactiveTime.swift`: supplied wall date, process-run ID and monotonic elapsed duration; dual-bound cooldown values.
- `SuggestionFeedback.swift`: centralized provisional constants, configurable policy parameters, typed responses, neutral withdrawal reasons and actual visible-exposure receipts.
- `SuggestionEligibility.swift`: minimal immutable-by-copy owner context, Focus unknown/on/off, explicit protection flags and typed eligible/deferred/discard decisions.

Added in `NotchiumPackage/Sources/NotchiumProactiveFeature/`:

- `MeetingSuggestionRule.swift`: a pure meeting rule taking dates and a supported-link Boolean. Authorized, fresh, non-all-day, uncancelled meetings inside the five-minute lead window produce one value; relevance ends at the earlier of event end or start plus two minutes.
- `SuggestionCandidateValidity.swift`: shape, consent, primary and secondary owner epoch/revision, availability, freshness, cancellation and expiry gates. No score bypasses them.
- `SuggestionCandidateSet.swift`: bounded coalescing by logical occurrence/category. Revisions cannot extend the stored absolute deadline; repeated generation does not renew creation time. Full collections reject new occurrences without evicting existing entries.
- `SuggestionScoring.swift`: clamp(0.55 × evidence + 0.20 × urgency + 0.25 × affinity − nonnegative timing penalty, 0…1), with threshold 0.75. Nonfinite inputs fail closed.
- `SuggestionInterruptionPolicy.swift`: pure submission eligibility, including consent/disable, validity, protection, Focus, daily cap, capacity, learning suppression, cooldown and snooze. No activity ranking or presentation ownership.
- `SuggestionFeedbackState.swift`: protected value-state mutation, per-category smoothed aggregates and bounded exposure/suppression receipts.
- `SuggestionFeedbackReducer.swift`: explicit exposure registration, idempotent feedback, category settings intent and learning reset; no storage or execution.

Added in `NotchiumPackage/Tests/NotchiumProactiveFeatureTests/`:

- `Stage25Fixture.swift`
- `Stage25CandidateTests.swift`
- `Stage25EligibilityTests.swift`
- `Stage25LearningTests.swift`
- `Stage25ArchitectureTests.swift`

Added this document: `docs/STAGE25A_PROACTIVE_FOUNDATION.md`.

The two supplied proactive planning documents were already untracked before this implementation and were preserved unchanged. No other existing source, configuration, entitlement, permission, setting or distribution script was modified.

## Ownership, identity and privacy

Dependencies are `NotchiumProactiveFeature → NotchiumCore → Foundation`. Its tests depend only on those two targets. The production `NotchiumFeature` dependency list remains unchanged. Feedback state stays with its reducer in the pure feature target so mutation can be module-internal; transport contracts stay in Core. No extra protocol, actor, context/event bus, model framework, database, service, action broker or coordinator was introduced. No third-party dependency was added.

Existing Calendar, battery, transfer, timer, Caffeine and Shortcut owners retain provider truth. `ActivityCoordinator` retains ranking, coalescing and visible lifetime. Stage 21 retains display/fullscreen/sleep/panel ownership. The new policy answers only whether submission would be eligible from an explicitly supplied snapshot. Any protection flag blocks optional proactive submission regardless of score or importance; essential critical battery warnings remain entirely in the existing path.

`SuggestionSourceIdentity` combines source and opaque owner epoch. `SuggestionOccurrence` adds an opaque token. `SuggestionIdentity` adds category and content revision; `SuggestionKey` excludes that revision. Exposure UUIDs are independent supplied presentation receipts. A title/content edit updates revision, not occurrence. Supporting evidence binds to the exact secondary owner epoch and revision, with independent consent, availability and freshness checks.

There are no title, name, URL, path, clipboard, screenshot, media or raw Shortcut fields. IDs are local pseudonymous metadata, not anonymity or authorization. Actions are descriptions only: Join identified meeting, Mirror, finite Caffeine, positive-duration Pomodoro, explicitly pinned Shortcut, Reveal observed transfer, Add observed transfer to Shelf. The existing `CaffeineDuration` is reused; no arbitrary shell/script/URL/path action exists. There is no executable closure or approval token. No Codable archive was introduced before a serialization contract exists.

## Feedback, timing and hard bounds

Positive/negative weights start at 2/2. Accept adds 1 positive; Dismiss adds 1 negative; sufficiently exposed Ignore adds 0.25 negative; Less like this adds 3 negative and quiets immediately. Three distinct dismissals or three distinct adequately exposed ignores quiet the category for seven days by default. Accept or neutral withdrawal cannot renew that quiet period. Never suggest explicitly disables a category until `setCategory(_:enabled:in:)` represents a user setting change. Learning reset preserves disables, source consent, global timing, high-water date and safety receipts.

`recordExposure` must be called only after the optional proactive experience actually renders. Submission, queuing, hidden expiry and the unchanged essential source alert are not exposures. Ignore requires the registered receipt and supplied cumulative visible duration of at least five seconds, no greater than elapsed time in that same run. Opening and hidden expiry/source invalidation/stop/policy withdrawal are neutral. Opening can precede acceptance but never becomes inferred dislike. Feedback consumption is once per exposure; terminal preference responses suppress the occurrence across revisions. Action completion/failure is outside the reducer and cannot automatically change affinity.

Snooze creates at most one deadline for a receipt, only strictly before absolute relevance expiry. It does not change affinity. A valid explicit snooze requests that occurrence's return, so its return is not another unsolicited exposure and does not wait for the cooldown created by its own exposure. A later unrelated exposure, manual/category quieting, consent revocation, expiry or protected activity still blocks it. A new actual return needs a new receipt; the original receipt cannot train twice.

Absolute source/calendar deadlines use supplied wall time. Cooldowns and exposure duration use supplied elapsed duration within one `runID`; cooldowns fall back to their wall bound across runs. Owners must pass their high-water wall date through `wallTimeFloor`, including evaluations that expire a hidden candidate. The reducer also preserves a high-water date for its observed transitions. A forward wall jump can expire a candidate without clearing an elapsed cooldown; a backward wall jump cannot undo a preserved expiry. Returned deferred boundaries include both wall and run-scoped elapsed values. No clock is read, and no sleep is scheduled. `AppClock.now()` remains an existing wall-date API and was not refactored.

Hard bounds are eight pending candidates, seven action descriptions per valid candidate, four category aggregates, 128 exposure receipts and total learning weight 32 per category. Weight rescaling preserves the current affinity. Negative streak counters saturate. Source-keyed projections are bounded by the seven-case source enum. Default unsolicited budget is three per day and global silence is thirty minutes; quiet duration, negative threshold, minimum visibility and daily budget are configurable supplied values.

Receipts are never automatically pruned or evicted. At saturation, recording and submission fail closed. Resetting learned preferences is not permission to replay old identities. Safe durable epoch retirement/receipt compaction is deliberately not implemented; Stage 25B must establish its proof before replacing the conservative saturation behavior. The composition owner also supplies the actual unsolicited daily count and must keep day/timezone/clock adjustment accounting from resetting it prematurely. No daily rollover scheduler exists here.

Only the meeting rule is implemented. Battery, transfer and future return-brief evidence are data contracts, not live generators or histories.

## Skills and verification method

Applied installed `swift-concurrency`, `swift-code-review` (including value/API and concurrency/lifetime references), `macos-patterns`, `security-review` and `verification-loop`. The named `write-swift`, `test-driven-development` and `verification-before-completion` skills were absent from the installed locations. Swift concurrency/review and verification-loop supplied the available mature substitutes. Tests were written first and observed failing for missing contracts; a secondary-source revision fixture was also observed failing before its correction. No skill or dependency was installed. No visual/SwiftUI design skill was needed.

XcodeBuildMCP tools were not exposed, so repository-documented local commands were used. The initial sandbox blocked Swift module-cache access before compilation; approved local Xcode access used isolated temporary scratch/DerivedData outputs. Xcode 27.0 (27A266a), Swift compiler 6.4, arm64, macOS 27 SDK; package deployment remains macOS 26. Package compiler invocations use Swift 6 language mode, and explicit complete-concurrency compilation checks the disconnected target independently.

## Verification results

| Check actually run | Result |
|---|---|
| `swift test --package-path NotchiumPackage --disable-sandbox --scratch-path /private/tmp/notchium-stage25a-spm --filter Stage25` | 38 Stage 25A XCTest cases passed, zero failures. |
| Focused existing Architecture/ActivityCoordinator/NotificationLifetime/Calendar/Stage21/lifecycle/transfer/Pomodoro/QuickActions selection | 108 existing XCTest cases plus four existing Swift Testing tests passed; the selection also ran the new Stage 25A cases. |
| Full `swift test --package-path NotchiumPackage --disable-sandbox --scratch-path /private/tmp/notchium-stage25a-spm` after the final behavioral correction | 38 new and 724 existing XCTest cases; four existing hardware cases explicitly skipped, zero failures. Five existing Swift Testing tests passed. The full run includes all selected regression suites. |
| `swift test` in isolated `/private/tmp/notchium-stage25a-free-tests`, `-Xswiftc -D -Xswiftc NOTCH_FREE_DISTRIBUTION --filter 'FreeDistributionTests\|Stage25'` | 38 Stage 25A XCTest cases and two free-profile Swift Testing tests passed, zero failures. |
| Debug workspace build | Passed, arm64, signing disabled, isolated `/private/tmp/notchium-stage25a-debug`. |
| Zero-cost Release workspace build | Passed, arm64, signing disabled, isolated `/private/tmp/notchium-stage25a-release`; `OTHER_SWIFT_FLAGS=$(inherited) -D NOTCH_FREE_DISTRIBUTION` propagated to package targets, coverage disabled as in the release script. |
| Disconnected pure target Release build | Passed using `swift build -c release --target NotchiumProactiveFeature -Xswiftc -strict-concurrency=complete -Xswiftc -D -Xswiftc NOTCH_FREE_DISTRIBUTION`, isolated `/private/tmp/notchium-stage25a-pure-release`. Effective compiler commands confirm `-swift-version 6` and complete strict concurrency for Core and the feature. No unsafe Sendable/isolation escape was added. |
| `git diff --check` and no-index whitespace checks for all 18 new implementation/test/doc files | Passed. No staging performed. No linter is configured. |
| Final source/dependency/privacy review | Complete for the two modified files and 18 added files. Architecture tests verify Foundation/Core imports, value-only code, no I/O/task/executor/observer path and no production attachment. No material unresolved finding remains within Stage 25A. |

Workspace commands used `-workspace Notchium.xcworkspace -scheme Notchium -destination 'generic/platform=macOS'`, `ARCHS=arm64`, `ONLY_ACTIVE_ARCH=NO`, `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, empty signing identity/team/entitlements and no injected base entitlements. These were builds only, not archive/sign/package/launch operations. The script itself was never run.

Temporary receipts: `/private/tmp/notchium-stage25a-focused.log`, `notchium-stage25a-regression.log`, `notchium-stage25a-full.log`, `notchium-stage25a-free-tests.log`, `notchium-stage25a-debug.log`, `notchium-stage25a-release.log`, `notchium-stage25a-pure-release.log`. The two expected failing test receipts are `notchium-stage25a-red.log` and `notchium-stage25a-supporting-red.log` in that same temporary directory. No generated output was added to the repository.

The four skipped `VolumeReplacementHardwareTests` require the existing `NOTCHIUM_VERIFY_SYSTEM_FEEDBACK=1` hardware qualification gate. Existing unchanged-source warnings remain, including Focus's async-alternative suggestion and skipped App Intents metadata extraction; the new pure code has no concurrency diagnostic. XCUITests, app launch, physical hardware, macOS 26 runtime and resource profiling were not exercised because no live/UI/platform integration was introduced.

## Stage 25B handoff — interfaces needed, not implemented

| Existing owner | Minimal projection or action seam needed |
|---|---|
| `CalendarService` / `CalendarActivityModel.snapshot` | Stable opaque occurrence token at the existing projection boundary; source epoch/content revision, permission/availability/freshness/cancellation, start/end/all-day and existing supported-link flag → `MeetingSuggestionInput` and `SuggestionSourceSnapshot`. Resolve `joinCurrentMeeting` through the current selected occurrence, never a retained URL. Current Calendar UUIDs are only stable within a process. |
| Existing `startBatteryActivities` / `BatteryActivityPolicy` | Existing authoritative crossing plus coarse battery percentage; independent Caffeine/Pomodoro evidence epochs/revisions and freshness. Optional work advice must enrich the existing warning, never create or suppress an essential critical warning. No second battery stream or crossing policy. |
| `TransferActivityModel.receive`, `active`, `recent`, `finishedFiles` | Terminal result after the owning reducer, opaque run/transfer token, reported byte count and resolvable final-file Boolean. Preserve observed-active coverage and terminal dedup; project active transfer protection. Reveal/Add to Shelf resolves through the existing owner. No filenames/paths or new scanning enter proactive values. |
| `PomodoroModel.state`, `records`, `startTimer()` | Opaque session identity, current revision, running/remaining coarse state and owner terminal outcomes. A future positive-duration action needs owner eligibility and an awaitable result, without mutating saved configuration or double-running coupled Focus Shortcuts. No second timer. |
| `CaffeineControlModel.mode`, `expiresAt`, `keepAwake(for:)` | Current owner epoch/revision and active finite-state projection; future awaitable finite-duration result preserving the model's expiry ownership. Reuse `CaffeineDuration`; no Lid Awake. |
| `QuickActionStore.pinned` / `QuickActionRunner.validate`, `run` | Explicit enabled pin UUID and current owner revision/availability. Resolve only that exact pin; future broker preflight/awaitable results distinguish acceptance from completion/failure and handle cancellation. No name guessing, raw definitions, automatic run or approval inferred from an ID. |
| Stage 21 / existing activity and shell owners | Immutable protection flags, Focus unknown/on/off, consent/global state, explicit wall/run/elapsed time, high-water date, daily count and other-pending count → `SuggestionEligibilityContext`. Continue to let `ActivityCoordinator` arbitrate after eligible submission. |
| Actual resolved/rendered suggestion and deliberate user response | Supplied independent exposure UUID and exact identity/deadline → `recordExposure`; cumulative actual visible duration and typed response → `respond`. Hidden/invalidated/withdrawn reasons stay neutral; user-requested snooze returns are excluded from unsolicited day counts. |

Before any exposure, Stage 25B must validate durable Calendar identity, owner revisions, source revocation, safe bounded receipt retention/migration, daily accounting across wall/day/timezone changes, monotonic run origins, actual exposure provenance and exact action preflight/approval/outcomes. Parameters remain provisional. No UI, runtime, observer, persistence or executor interface from this table was attached or implemented in Stage 25A.

## Resource impact and limitations

No new observers, timers, polling, background tasks, singleton, network, filesystem scan, inference, permission request or application startup work exists. The pure target is disconnected from the app product. No CPU improvement, resource trace, compile-time delta or binary-size delta was measured. Builds do not establish native minimum-OS/hardware behavior; Stage 25A introduces no native runtime path requiring such a claim. No commit, tag, packaging, distribution artifact or publication was performed.
