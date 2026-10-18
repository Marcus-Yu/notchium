# Stage 27A — engineering audit and regression evidence

Date: October 16, 2026 (America/Toronto). Repository baseline: `7ef5522d287fe5c6d498dd5251958d49cbf566db`, branch `main`, initially clean. A source snapshot of that commit was preserved under `/tmp/notchium-stage27a-baseline-src`. Changes are uncommitted. No version, release configuration, distribution policy, tag, publication, or DMG packaging was changed or executed. Onboarding validation was not started.

## A. Executive assessment

**NO-GO — engineering qualification remains incomplete.** Four source defects were reproduced and corrected, one intermittent test was made event-driven, and eight regression/stress test cases were added. The final package suite, Xcode unit/integration target, targeted Thread Sanitizer run, optimized fixture-enabled tests, Debug/Release builds and static analysis pass. Four hardware tests remain skipped. Xcode's native UI runner could not bootstrap; direct Computer Use supplied a narrower set of native acceptance checks.

No unresolved P0/P1 defect was established in the reviewed paths. This is not an assertion that the entire app is bug-free, free of exploitable issues, or fully qualified. Repository/module/control inventories and the high-risk ownership paths below were examined; every production line and every declared control was **not** independently exercised. Live integrations, sustained production performance, complete accessibility testing, and source provenance remain gaps.

Receipts:

- [Automated suite ledger](STAGE27A_AUTOMATED_RESULTS.tsv): per-suite counts, skips, failures and durations for the final runs.
- [Current control declaration inventory](STAGE27A_CONTROL_INVENTORY.tsv): 209 declarations across 53 files, including conditional/debug declarations, gestures and native factories. This is a source inventory, not 209 manual passes or a runtime control count.
- [Sanitized performance data](STAGE27A_PERFORMANCE_RESULTS.json): measurement configuration, counters and limitations. Raw traces, exports and logs remain temporary/private under `/tmp/notchium-stage27a-*`; they are not repository artifacts. Instruments exports can contain the target environment and host identifiers and must not be uploaded indiscriminately.

## B. Confirmed findings and corrections

### S27-01 — P2: a shorter output channel can overrun its buffer

- Component/files: `NotchiumRealtimeAudio/NotchiumRealtimeAudio.c`; `Stage27AudioBufferTests.swift`.
- Reproduction: supply four stereo input frames, a four-frame left output and a two-frame right output to `NTAudioMixFloat32`, with noninterleaved output. A standalone Clang Address Sanitizer reproducer reported `heap-buffer-overflow` in `NTAudioMixFloat32`. The retained regression also detected writes into sentinel storage beyond the advertised right-channel byte count.
- Root cause: the callback used the first destination buffer's frame count to authorize writes into both channels.
- Correction: bound each noninterleaved destination write by that buffer's own `mDataByteSize`. Allocation-free and lock-free callback behavior is retained.
- Verification: the sentinel regression failed before the fix in eight combinations and passes afterward across 18 length/layout combinations. The standalone reproducer passes with Address and Undefined Behavior Sanitizers after the correction. Existing audio mixer tests pass.
- Limit: a real HAL/hardware instance supplying this unequal layout was not observed. The bounds failure is confirmed; production exploitability is not established. This is not a claim of a remotely exploitable vulnerability.

### S27-02 — P2: late Caffeine creation can undo shutdown

- Component/files: `NotchiumServices/CaffeineService.swift`; `Stage27CaffeineLifetimeTests.swift`.
- Reproduction: suspend native assertion creation, invoke shutdown/cancellation, then let creation return. Before the fix, the service became `systemAndDisplay` again and retained the late assertion; the regression failed three assertions.
- Root cause: a mutex protected assignments but did not invalidate an in-flight native creation.
- Correction: reserve an operation revision, invalidate it on shutdown/replacement, check task cancellation at entry and commit, and release an obsolete newly created assertion exactly once. The native create/release boundary is injectable internally so tests do not alter host power settings.
- Verification: shutdown during creation passes both with and without task cancellation; existing timed/press/utility Caffeine tests pass; targeted Thread Sanitizer passes.
- Limit: physical idle-sleep/display/lid behavior was not retested. The privileged helper was not installed or invoked.

### S27-03 — P2: Focus shortcut side effects can complete in reverse order

- Component/files: `NotchiumFocusFeature/FocusModeModel.swift`; `Stage27FocusOrderingTests.swift`.
- Reproduction: suspend the user's On shortcut, end the Focus session, and allow Off to finish first. Before the fix the explicit completion sequence was `[Off, On]`, leaving On as the final side effect.
- Root cause: independent unowned tasks provided neither ordering nor lifecycle cancellation.
- Correction: serialize shortcut operations in submission order and retain all queued/running tasks for cancellation at stop/deinitialization. Canceled queued work cannot start after stop; cancellation does not become a user-facing shortcut failure.
- Verification: the ordering regression fails before the ordering repair and passes afterward. A second regression verifies cancellation of an in-flight shortcut and suppression of queued work at stop. Existing Focus tests, optimized checks and Thread Sanitizer pass.
- Tradeoff/limit: while the feature remains active, a following Off waits for its preceding On to finish. An arbitrary user shortcut can be slow; the audit did not execute personal shortcuts or change real system Focus. Teardown cancels owned work through the existing service cancellation path.

### S27-04 — P2: restored scoped Shelf references are checked before access

- Component/files: `NotchiumShelfFeature/ShelfModel.swift`, `NotchiumServices/ShelfService.swift`; `Stage27ShelfScopeTests.swift`.
- Reproduction: restore a valid bookmark whose file is visible only while its security scope is open. The original implementation treated it as missing and saved an empty reference list. The two initial scope tests failed eight assertions before repair.
- Root cause: existence validation preceded scope acquisition; a moved resolution also used its new URL without acquiring/replacing the scope.
- Correction: acquire before validation/bookmark refresh, release rejected duplicate/missing candidates, retain accepted scopes, and acquire the moved URL before releasing the previous URL. Store-profile bookmarks request read-only scope, matching its existing entitlement and the Quick Actions implementation.
- Verification: restore/preservation, duplicate/missing rejection and moved-reference replacement tests pass; existing Shelf/lifecycle tests pass. Native final-build picker cancellation retains the disposable reference.
- Limit: the reduced App Store profile was not runtime-qualified. Direct unsandboxed bookmarks still work without requiring a successful scope acquisition. Apple documents the required acquire/use/release sequence in [security-scoped URL access](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource()).

### S27-05 — P3: mixer regression relies on a scheduler-yield budget

- Component/file: `AudioMixerTests.testProcessExitAndOutputChangeReconcileTheTapGraph`.
- Evidence: the untouched baseline package run failed its first-route assertion (`nil` versus `20`); the baseline Xcode run passed it. The test assumed four yields completed a chain of canceled/replacement actor tasks.
- Correction: a test-local actor signals actual application of the speaker route, headphone route and process removal. All original state assertions remain. No production mixer behavior was changed for this failure.
- Verification: final complete package/Xcode runs pass; focused and optimized runs pass.

### S27-06 — P3: current entry documentation describes superseded behavior

`CLAUDE.md` still described four pages, a single panel and signed/notarized primary distribution. The handoff described removed Spotify OAuth/Connect and seek-then-play behavior. Current-source corrections now identify six pages, shared providers with per-display shells, local Spotify control, preserved paused seeking and the existing free distribution policy. Historical stage evidence remains explicitly historical. The permission ledger now flags its old planning claims instead of presenting them as tested current behavior.

## Architecture and ownership reviewed

| Boundary | Current flow / ownership |
|---|---|
| Startup/shutdown | `NotchiumAppDelegate` owns one controller; `AppEnvironment`/`ServiceRegistry` compose adapters; controller starts feature models once and stops them at termination. Media/calendar teardown tasks order rapid restart against earlier shutdown. |
| Provider truth | Platform services emit typed snapshots/streams. Feature models project state; the source activity coordinator arbitrates activities. Display projections do not instantiate duplicate providers. |
| Panels and geometry | `NotchiumDisplayCoordinator` owns selected display sessions. Each session owns its presentation model and panel. `NotchGeometryResolver` supplies layout; the panel controller applies it. Current outer shell is 524 × 266 pt, host 740 × 322 pt. |
| Local Spotify | `LocalSpotifyController` → serial utility-queue script executor → provider revision/reconciliation checks → `MediaSessionController`. Workspace/playback hints refresh provider truth. One 15 s playing / 30 s paused fallback stops for unavailable/closed/denied Spotify. Queue remains unsupported. |
| Media resources | Artwork requests share a cache bounded to eight thumbnails/~1 MB decoded and 2 MB input per request, with Spotify CDN checks. Spotify tap mutation is actor-owned; FFT publication and inactive presentation are gated. Real tap energy was not measured. |
| Calendar | EventKit stays in its adapter. Store/day/activation/clock/time-zone/wake events and one next boundary trigger refresh; the feature owns selected event and reminder policy. Real revocation was not induced. |
| Audio | HAL listeners and the existing event/worker route gate own output truth. App mixer actor owns tap/aggregate lifetime. C callback uses preallocated atomic gains. Process/output removal regressions and the new per-buffer bounds test pass. |
| Shelf/native UI | Shelf holds references, not managed copies. Model scopes pair with exact acquired URLs. Native picker/sharing objects and the existing shell lease own native presentation until terminal cleanup; source-related windows only can end sharing. |
| Clipboard | Pasteboard service captures supported non-sensitive types; model controls opt-in, deduplication, pins and retention. Ordered utility-queue store owns Keychain/disk state and blocks mutations while unavailable/unhydrated. |
| Timer/Focus/Caffeine | Pure Pomodoro transitions take explicit time; the model schedules a deadline, catches up on wake/clock changes and persists on transitions. Focus shortcut ordering and Caffeine assertion invalidation were corrected above. |
| Background resources | Screenshot directory/candidate sources, Spotlight, Progress subscriptions, battery run-loop source and audio listeners have explicit teardown paths. Progress terminal-event delivery remains unbounded intentionally so independent terminal events are not dropped; this is not a blanket claim that every stream is bounded. |

Deep source inspection covered the composition/lifecycle, local Spotify/script/provider pipeline, Clipboard encryption/disk/model/service, Pomodoro engine/model/store, Focus/Caffeine, Calendar adapter/model, Shelf/model/native presentation, C mixer and app mixer, panel/session/page ownership, screenshot/transfer/battery observers, Quick Actions/Reminder flow, and artwork/meter/tap ownership. Other production declarations and future/scaffolding targets received inventory/build/test coverage rather than a complete line-by-line proof. Physical behavior and framework implementation internals remain outside source-only conclusions.

## C. Executed automated verification

| Run | Actual result |
|---|---|
| Untouched baseline complete package | Main XCTest: 720 cases, four hardware skips, one failure (mixer scheduler-dependent assertion). Proactive XCTest: 38/38 passed. Swift Testing: five passed. |
| Untouched baseline Xcode plan attempt | Main XCTest: 720 cases, four skips, zero failures. Overall plan failed because UI runner exited before bootstrap. |
| Final complete package | Main XCTest: **728 cases, four skips, zero failures**; proactive XCTest: **38/38 passed**; Swift Testing: **five passed**. Main XCTest duration 57.517 s. |
| Final Xcode unit/integration target | **728 cases, four skips, zero failures**, plus five Swift Testing tests. XCTest duration 58.987 s. `TEST SUCCEEDED`. Proactive target is covered by the package run; it is not in the current Xcode test plan. |
| Final targeted Thread Sanitizer | **20 cases, zero failures**, no Thread Sanitizer report in that run. Includes new regressions, Clipboard retry concurrency and Stage 22 lifecycles. This does not cover all real hardware callbacks. |
| Optimized fixture-enabled tests | **29 cases, zero failures**. `-c release`, `NOTCH_FREE_DISTRIBUTION` and `DEBUG` explicitly enabled for existing test fixtures. This is distinct from a production Release test target. |
| Plain optimized tests without DEBUG | Compilation failed before test execution because existing `MockNotchActivity`, `FixtureFactory`, etc. are DEBUG-only. Reproduced on the preserved untouched baseline. No test was disabled to hide the failure. |
| Native UI plan / isolated retry | Both attempts failed before runner connection: `Notchium-Runner` killed before bootstrap. A temporary ad-hoc signing retry did not resolve it. **Zero UI-test passes are claimed.** |
| Debug app | Built through the final Xcode unit run. |
| Ordinary local Release | Built successfully; package coverage instrumentation was detected in this local invocation. It is not a clean distribution build receipt. |
| Existing release-policy build only | `BUILD SUCCEEDED`; no fixture/debug/coverage markers or LLVM coverage/profile sections in the resulting binary. No packaging/signing/publication stage was invoked. |
| Xcode static analysis | `ANALYZE SUCCEEDED`. No new analyzer defect was reported. |
| C bounds reproducer | Before: Address Sanitizer heap-buffer-overflow. After: Address + Undefined Behavior Sanitizers exit successfully. |
| Release safety tooling | Five Python unittest tests passed. |
| Lid helper harness | Standalone injected-command harness passed acquire, renewal, release, foreign ownership, safety cutoff, crash recovery and restoration retry. No root/helper/system-power mutation. |
| Source secret scan | Existing verifier passed 261 production files. Separate scan covered 1,755 reachable historical blobs across 1,169 reachable commits for eight credential/private-key formats. One match was the deliberate private-key header fixture in `scripts/tests/test_release_safety.py`; no actual key was found by those patterns. |
| Whitespace/final diff | `git diff --check` passes. No original assertion was removed, weakened, or skipped. Final source/configuration inventory is described below. |

Reproduction commands (output paths in the executed commands were isolated under `/tmp/notchium-stage27a-*`):

```sh
swift test --package-path NotchiumPackage --scratch-path /tmp/notchium-stage27a-spm --cache-path /tmp/notchium-stage27a-cache --disable-sandbox
swift test --package-path NotchiumPackage --scratch-path /tmp/notchium-stage27a-tsan --cache-path /tmp/notchium-stage27a-cache --disable-sandbox --sanitize thread --filter 'Stage27|ClipboardRetryConcurrency|Stage22Lifecycle'
swift test --package-path NotchiumPackage -c release --scratch-path /tmp/notchium-stage27a-release-spm --cache-path /tmp/notchium-stage27a-cache --disable-sandbox -Xswiftc -DNOTCH_FREE_DISTRIBUTION -Xswiftc -DDEBUG --filter 'Stage27|ClipboardKeychain|Stage26ClipboardCompatibility|ClipboardStorageRecovery|LocalSpotify'
xcodebuild -workspace Notchium.xcworkspace -scheme Notchium -destination 'platform=macOS' -configuration Debug -derivedDataPath /tmp/notchium-stage27a-dd -only-testing:NotchiumFeatureTests CODE_SIGNING_ALLOWED=NO test
xcodebuild -workspace Notchium.xcworkspace -scheme Notchium -destination 'platform=macOS' -configuration Release -derivedDataPath /tmp/notchium-stage27a-release-dd CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace Notchium.xcworkspace -scheme Notchium -destination 'platform=macOS' -configuration Debug -derivedDataPath /tmp/notchium-stage27a-analyze-dd CODE_SIGNING_ALLOWED=NO analyze
python3 -m unittest discover -s scripts/tests
python3 scripts/verify-release.py --source .
git diff --check
```

Warnings were reviewed, not described as a warning-free build: existing `FocusService` callback-vs-async suggestion intentionally avoids awaiting an unanswered authorization request; AppIntents metadata extraction is skipped because there is no AppIntents dependency. Offscreen rendering tests report FocusState constant-binding warnings; one Xcode rendering run also reported a QoS inversion diagnostic. These do not prove production focus/QoS correctness and remain native qualification items.

## Manual/native matrix for this session

| Area | Executed result | Still unverified |
|---|---|---|
| Home/Music | Native dark quality fixture: long multilingual metadata, Home/Music navigation, retained paused presentation inspected. Paused seek 92 → 120 s updated feedback and remained Play/paused. | Real Spotify launch/quit, consent, revocation, rapid skips/track races and sustained real waveform. |
| Calendar | Native long-title and empty upcoming fixture inspected; source/unit ordering, status and reminder cases executed. | Real EventKit account changes, overlapping real events, join targets, fresh/revoked permissions. |
| Audio | Native long output name, battery labels, empty local-app list and control layout inspected; deterministic volume/mixer/route tests executed. | Physical 0/100%, disconnect/reconnect, AirPods/Bluetooth, real per-app gain/tap cleanup, four opt-in hardware cases. |
| Pomodoro | Native in-memory Start → Pause → Resume → Pause → End showed correct controls/ready feedback. Deterministic phase/history/configuration/sleep catch-up cases ran in suite. | Physical sleep/wake, real long session across midnight/DST and sound/hardware feel. |
| Shelf picker | Three native first-click open/cancel cycles on the baseline fixture; **three further cycles on final optimized fixture**, retaining its one disposable reference and Shelf page. | Finder drag in/out, actual user-file import/export/Quick Look, multiple/folder selection, fullscreen and physical alternate display. |
| AirDrop | **Three final-build native open/cancel/immediate-reopen cycles** returned to expanded Shelf with AirDrop available. Only a generated `/tmp` file was offered; no recipient selected. | Recipient completion/transmission, fullscreen Spaces, physical multi-display and OS-version matrix. |
| Clipboard | Empty native in-memory history/search layout inspected. Encryption/key lookup/migration/failure/preservation/retry tests used fake keys and temporary stores. | Personal-history quit/relaunch/recovery, actual Keychain ACL/lock changes, real capture/source attribution and retention under live data. |
| Mirror | Native quality fixture displayed permission explanation and device list; close returned to page. Mock camera lifecycle/recovery tests passed. | Actual camera consent, preview/mirroring/selection/disconnect and device release indicator. |
| Quick Reminder | Native mock: empty Add disabled; typing enabled Add; save closed composer and displayed Reminder Added. | Actual EventKit save and denial/revocation, fullscreen context and personal lists. |
| Quick Actions | Configured fixture strip and accessibility labels inspected; discovery/validation/resource/runner tests passed. | Personal workflows and targets, security-scoped Store runtime. |
| Settings | Final light native General page inspected; native close and Command-comma reopening succeeded. | Every setting toggle/persistence combination and full light/dark category matrix. No personal preference toggle was intentionally exercised. |
| Shell/accessibility | Six page layouts and meaningful labels inspected with fixtures; direct expand/close observed; 1,000 deterministic model cycles passed. | 1,000 rendered native cycles, VoiceOver speech/order, complete keyboard traversal, physical scaling/hot-plug/Spaces and reduced-effects settings matrix. |
| Activities/battery/transfers | Automated arbitration, expiry, transfer terminal ordering and 2,000-session sharing ownership stress ran as part of the complete suite. | Real simultaneous providers, battery critical transition, real downloads/screenshots/transfer failures and long energy traces. |

Native observations are fixture observations on macOS 27, not hardware/integration passes or macOS 26 acceptance. They do not replace the failed XCUITest runner. The dark long-content quality fixture and light empty/native-file/Settings fixture are different scenarios; a complete two-appearance matrix was not executed.

Isolation incidents: Computer Use interactions resulted in unexpected temporary Debug app processes without fixture arguments, including a relaunch after native Quit. Two such extra processes were stopped when identified; the second was discovered during final cleanup. No success or performance result is attributed to them. No direct personal Clipboard/Keychain deletion, reset, key replacement, or manual fault injection was performed. Automatic production-service work during those launches was not independently audited, so this report cannot certify those intervals as fully isolated or prove personal-store integrity from a before/after snapshot. The original installed process was left running. Final coverage-free samples used direct launches with verified mock arguments and no further Computer Use calls. The generated sharing test file was removed only after verifying its exact disposable content.

## D. Performance and resource evidence

Host: MacBook Air `Mac16,12`, Apple M4 (10 CPU cores), 16 GiB; macOS 27.0.1 (`26A434`), Xcode 27.0 (`27A266a`), Swift 6.4 compiler with Swift 6 language mode and complete concurrency checking. Minimum deployment remains macOS 26. Tooling: app-scoped Instruments Time Profiler, public `proc_pid_rusage` counters sampled at 100 ms, Apple `leaks`, and deterministic model stress memory checkpoints.

The initial paired runs were optimized Release builds with existing DEBUG mock fixtures enabled. Local Xcode package coverage instrumentation was subsequently discovered. Their raw counters are retained in the JSON as **exploratory instrumented samples**. They exclude real Spotify, EventKit, pasteboard polling, camera and Core Audio taps. Development builds/tests were also active on the host. The final shell was observed collapsed later, so continuous expanded state is not established. No optimization or production performance improvement is claimed from those numbers.

| Exploratory metric | Before | After | Difference |
|---|---:|---:|---:|
| Mock collapsed idle CPU, one-core percent | 0.0000% | 0.0001% | +0.0001 percentage points |
| Mock playback rendering CPU | 0.4648% | 0.4457% | −0.0191 percentage points; not a steady-state production comparison |
| Idle physical footprint at sample end | 44.08 MiB | 43.77 MiB | −0.31 MiB |
| Playback physical footprint at sample end | 53.66 MiB | 52.31 MiB | −1.35 MiB |
| Peak sampled playback RSS | 61.30 MiB | 114.38 MiB | +53.08 MiB; residency/pressure and workload-state differences not controlled |
| Idle interrupt wakeups/s | 0.000 | 0.050 | +0.050/s |
| Playback interrupt wakeups/s | 60.344 | 60.321 | −0.023/s |
| Production idle/media/peak memory and retention | N/A | N/A | No matched real-service workload |
| Model retention, cycles 250 → 1,000 | N/A | See below | No baseline model run; no numeric improvement claim |

Each counter window lasted approximately 20 seconds; exact durations/counters are in JSON. RSS and physical footprint are different measurements. A change in resident pages while the host is compiling/compressing memory does not establish a leak or an allocation regression.

A supplementary **coverage-free** mock idle comparison rebuilt both baseline and final binaries with the existing release script’s global coverage-disable flags. The two verified mock processes warmed up for five seconds and were measured simultaneously for 20.024 seconds, with no Computer Use calls. This isolates neither the real adapters nor the full production workload; it is a narrow idle regression diagnostic.

| Coverage-free mock idle metric | Before | After | Difference |
|---|---:|---:|---:|
| CPU, percent of one core | 0.0000% | 0.0001% | +0.0001 percentage points |
| Physical footprint at end | 40.6573 MiB | 40.6417 MiB | −0.0156 MiB |
| Peak sampled RSS | 84.00 MiB | 105.61 MiB | +21.61 MiB |
| Interrupt wakeups/s | 0.000 | 0.000 | 0.000/s |
| Real media/camera/Clipboard/Calendar cost | N/A | N/A | Mock providers do not exercise those adapters |

The nearly equal physical footprints and differing RSS are reported together; no speedup, memory improvement, production energy threshold, or absence-of-leaks claim is derived from them. Clean production benchmarks still require the live matrix.

The targeted model-only stress run recorded **82,018,304 resident bytes at all four checkpoints** (250/500/750/1,000 cycles) and verified model release afterward. Full-suite and sanitizer/optimized runs have their own higher process baselines; these must not be compared to the isolated run as app memory. This was 1,000 immediate presentation/page/lease cycles, not 1,000 rendered NSPanel animations.

Time Profiler collected 3,938 baseline active-fixture sample rows and 4,221 final sample rows, including Notchium frames. The idle Debug trace had no CPU sample rows; it supplies no hotspot evidence. Apple Leaks on the optimized baseline reported **416 allocations / 19,936 bytes**, while also saying the process was not debuggable and inspection was restricted to read-only memory. That aggregate is **unattributed and unresolved**; it is not accepted as proof of an application retain cycle, nor as a clean leak result. Full Allocations/Leaks/Memory Graph attribution remains required.

| Required production scenario | Current evidence / limit |
|---|---|
| Collapsed idle / inactive | Optimized mock counters only; production adapters N/A. |
| Media playing / paused | Local-provider regressions and mock rendering samples; real Apple Events/tap cost N/A. |
| Clipboard monitoring | Change-count and privacy/concurrency tests; real continuous polling/capture CPU N/A. |
| Timer running | Native start/pause/resume/end and deterministic deadline tests; sustained production energy N/A. |
| Calendar active | Event-driven source path and regressions; populated real-calendar CPU N/A. |
| Mirror active | Mock resource-release tests; camera processing CPU/memory N/A. |
| Expanded notch | Native layouts and rendering tests; continuous state/refresh-rate benchmark N/A. |
| Multiple active activities | Deterministic arbitration/terminal/session stress; real combined workload N/A. |

No speculative micro-optimization, background timer, reduced update fidelity or animation redesign was introduced. The changes correct demonstrated bounds, ordering and resource-lifetime failures.

## E. Security, privacy and dependencies

**Clipboard:** AES-256-GCM uses authenticated identities for index/image payloads, fresh seal nonces and a Keychain-held random key. Create-only `SecItemAdd`, readback verification and exact error handling distinguish missing items from access/unavailable errors. Existing ciphertext prohibits replacement-key creation. Legacy backend promotion requires authentication of the encrypted index and referenced images; wrong keys/corruption block writes and cleanup. Tests use injected clients, never personal Keychain entries. Apple's [Keychain lookup guidance](https://developer.apple.com/documentation/security/searching-for-keychain-items) supports distinguishing not-found from other failures.

Disk operations are ordered; descriptor-relative opens reject symlinks/nonregular/hard-linked payloads and enforce limits. Atomic rename/fsync and restricted directory/file modes protect committed data. Capture defaults off in production. Concealed/transient types and named password managers are excluded; public pasteboard attribution remains best effort and cannot guarantee detection of all secrets. Pins/retention/history and image bounds were reviewed and tested; live personal history was not migrated or intentionally reset.

**AppleScript/Spotify:** commands interpolate bounded finite numeric values and fixed Boolean/action tokens, never track titles, artist strings, URLs or arbitrary executable text. Metadata returns a typed list. Execution and permission preflight stay on a serial utility queue with five-second Apple Event timeouts. Launch/quit checks, generation/revision barriers and no polling for absent/denied Spotify are present. No production OAuth, Web API player endpoint, client-ID/token transport or loopback listener was found in current source. Legacy Keychain credentials remain unused; they were not deleted. Queue compatibility types/mock tests are not a live remote queue.

**Permissions:** existing usage strings cover local Spotify Automation, Calendar, Camera, Reminders, system-audio capture and protected folders. No microphone usage string is present. Current free Release deliberately has no entitlements and omits the privileged helper; Store/Debug declarations are separate profiles. The optional helper's signing/XPC requirements were not weakened and it was not installed. No Full Disk Access, administrator grant, TCC reset, hidden consent or Accessibility grant was performed by this audit. Existing permission-planning documents conflict with startup Calendar/screenshot behavior; the new current-source notes flag that conflict. This audit did not begin first-run onboarding qualification.

**Other inputs/processes:** meeting-link detection restricts HTTPS vendor hosts and rejects URL credentials; Quick Actions validate destinations/bookmarks; Shortcuts uses a fixed executable and argument arrays with cancellation ownership. Source-file deletion is not a Shelf operation. The corrected C buffer boundary is a memory-safety finding with unproven real-device reachability, not a demonstrated external exploit.

**Logging/secrets:** the production logger accepts a closed event enum. No clipboard payload/event title/credential was added to logs. Both current-source and history scans were heuristic, with their exact coverage above; they cannot prove that every possible secret format is absent. Existing private Stage 26 backups were not scanned, deleted or published. Trace exports and unrelated process environments are not shareable evidence; only sanitized counters and summaries are retained here.

**Supply chain/licenses:** the package has no external SwiftPM dependency, binary target, package plugin or downloaded runtime dependency. Existing build scripts and in-repository C/helper boundaries were inspected. The bundled Spotify logo is separately attributed in `THIRD_PARTY_NOTICES.md`; its provenance/branding permission is not established by the MIT license. No dependency was removed or added.

The upstream [Boring Notch repository](https://github.com/TheBoredTeam/boring.notch) declares GPL-3.0. Current source/history searches found no explicit Boring Notch attribution or GPL marker. This is **not proof of independent authorship**. Notchium's MIT-only distribution compatibility cannot be certified without source/asset provenance. If GPL source was incorporated, the combined-work obligations described by the [GNU license FAQ](https://www.gnu.org/licenses/gpl-faq.html#WhatDoesCompatMean) cannot be satisfied merely by omitting its notice. This remains an unverified provenance/compliance question, not a confirmed copying accusation or permission to relicense. Obtain origin records/author confirmation before distribution.

Strix and XcodeBuildMCP tools were unavailable in this session. Available security skills primarily target web/API deployments; no cloud source upload, unrequested scanner installation or live web exploit run was substituted. The security result is source review, deterministic adverse-input tests, sanitizer evidence and heuristic scans, not a completed managed pentest.

## F. Code quality and final change review

- Production changes are limited to the four confirmed mechanisms: five existing source files. Tests add eight cases in five files and repair one existing mixer test.
- No dependency, feature, service manager, panel, page, animation or distribution mechanism was added. No source was deleted solely from a text-search inference.
- Up Next/queue compatibility models and mocks remain because protocols/tests still reference them; the current Media page does not mount queue navigation. Future/scaffolding adapters remain unavailable rather than fabricating support. The old Spotify remote transport files were already absent at baseline.
- Resource corrections cover a stale IOKit assertion, ordered/cancelable Focus operations and balanced scoped bookmarks. The C correction bounds existing writes. There is no claim that all possible leaks/races are eliminated.
- `@unchecked Sendable` and unsafe isolation annotations were not added. Existing queue/actor/mutex/foreign-callback invariants were inspected in the reviewed paths and compile in Swift 6 mode.
- Caffeine's internal injected create/release functions are a platform testing boundary with normal IOKit defaults; no runtime audit switch or instrumentation was added to production paths. The 1,000-cycle counter lives only in tests.
- Config, Info.plist, Xcode project, release script and GitHub release configuration remain unchanged. Version remains 1.0.0/build 2. Canonical release instrumentation validation is a build-only check of existing flags, not a release-policy change.

Skills applied: Apple design, Swift code review/concurrency, macOS patterns, Instruments, Xcode workflow and security review; Apple API details were checked through Context7. The installed Apple design reference is WWDC-derived/web-oriented, so its platform-independent feedback/accessibility principles were applied without importing web layout or redesigning the native shell. Missing dedicated macOS energy/mutation/provenance tooling was not represented as an executed specialist audit.

## G. Remaining checks and precise acceptance matrix

Every item below is **UNVERIFIED** unless an executed narrower result is explicitly identified above:

1. Restore Xcode UI runner bootstrap on this host and run the complete native suite without early runner death. Current direct UI checks are narrower evidence.
2. With the intended direct app identity, qualify real Spotify absent/launch/quit, first consent/denial/revocation, repeated command/seek races and local waveform teardown; do not restore OAuth/Connect/queue behavior. Fresh onboarding belongs to Stage 27B and was not begun here.
3. Qualify actual Calendar account/selection/overlap/time-zone/DST/revocation, configured reminder intervals and safe Join behavior; test real Reminder denial/recovery/save in intended contexts.
4. Run the four audio opt-in hardware tests and real output disconnect/reconnect, Bluetooth/AirPods, per-app mixing, writable/unsupported controls and tap teardown. Do not report mock routing as device acceptance.
5. Exercise actual camera permission/revocation/device removal, mirroring/selection, close/sleep release and capture indicator.
6. Complete Finder drag in/out, folders/multiple files, duplicate references, copy/move semantics, original-file safety, Quick Look, AirDrop recipient completion, fullscreen Spaces and physical multi-display/native-dialog placement.
7. Validate personal encrypted history through ordinary authorized application access and a normal quit/relaunch with an approved non-destructive evidence plan. Do not reset history or manipulate personal Keychain to simulate faults. This also closes the unintended-launch isolation gap noted above.
8. Capture sustained **coverage-free production** CPU/wakeups/footprint/Allocations/Leaks for idle, media playing/paused, capture, timer, populated Calendar, Mirror, expanded and combined/inactive workloads. Attribute the restricted Leaks aggregate before deciding whether any app-owned leak exists.
9. Finish native keyboard/VoiceOver order, reduced motion/transparency/contrast, scaling, display hot-plug and sleep/wake matrix on macOS 26 as well as current macOS. The 1,000 immediate model cycles are not a rendered animation endurance test.
10. Establish copied-source and asset provenance, including the requested Boring Notch/GPL question, before claiming MIT-only distribution compliance.

## H. Final engineering gate

**NO-GO — engineering blockers remain.** No unresolved confirmed P0/P1 source defect was established in the reviewed paths, but required native UI automation is blocked, source/control coverage is not exhaustive, production performance/leak attribution and hardware/permission acceptance are incomplete, and licensing provenance is unverified. Those evidence gaps prevent a truthful Stage 27A completion/GO verdict. No new onboarding or distribution validation stage was started.

The next bounded engineering task is to restore native UI-runner execution and complete the listed live regression/performance matrix on the exact intended build, while preserving personal history and credentials. A later GO would authorize proceeding to Stage 27B only; it would not authorize publication.

### Final verification note

The build-only Release invocation copied the existing `scripts/release.sh` global coverage-disable, signing-disable and source-prefix-map flags. It completed successfully in `/tmp/notchium-stage27a-release-policy-dd`. Its binary contains no `--ui-testing`, Stage 11 fixture, startup-debug, LLVM profile or coverage markers, and `otool` found no LLVM profile/coverage sections. Both disposable optimized fixture binaries were also rebuilt without coverage; their existing DEBUG mock entry points intentionally remain available only for the diagnostic configuration. No package, DMG, production signature or release was created. The earlier plain Xcode Release result must not be substituted for this clean build receipt.
