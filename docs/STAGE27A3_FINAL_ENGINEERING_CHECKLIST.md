# Stage 27A.3 — Final Engineering Checklist

Verification date: 18–19 October 2026. Repository: Marcus-Yu/notchium. Version 1.0.0, build 2.

## A. Executive Summary

**CONDITIONAL GO — engineering candidate ready for Stage 27B in parallel; final release freeze awaits limited native visual sign-off.** No reproducible P0/P1 production defect remains established after the corrections. UI-03 and UI-04 have automated/source support but did not obtain a valid final native visual reproduction in this session. This is a condition, not a visual pass.

This was a focused verification of sustained production services, Spotify duration handling, the two outstanding native transitions, regression coverage and release hygiene. Owner acceptance of licensing/provenance, Spotify logo rights, accessibility, actual AirDrop and additional hardware remains accepted. Stage 27B onboarding and persistence validation has not been performed.

One production defect was reproduced deterministically: a wall-clock rollback could timestamp an authoritative file-transfer terminal event before previously delivered progress, causing the presentation reducer to reject it and retain an active transfer. The service now clamps that final event to the last delivered timestamp. Its public API, completion classification, throttling, actor ownership and reducer stale-event contract remain intact. An internal Sendable clock seam makes the regression deterministic. A full GUI run exposed one transfer stress failure, but its actual clock history was not captured; the deterministic reproduction establishes the defect without asserting the cause of that earlier failure.

An initially attempted reducer-level correction violated an existing stale-terminal test and was withdrawn. The final reducer is byte-identical to the starting source. Audio tests now await observable service completion with a bounded timeout instead of assuming four task yields are sufficient. A stale Stage15 expectation was aligned with the owner's existing local-playing-Music expansion policy. Four media test methods and one transfer regression method were added. Two existing hover/Spotify lifecycle tests now synchronize on the actual scheduled sleep or published state; they no longer assume that an earlier asynchronous step means the final outcome has completed. No UI or animation production code was changed.

An ignored zero-byte `Notchium/default.profraw` was copied by the filesystem-synchronized Xcode target into an early Release artifact. Its original bytes, hash and metadata were preserved outside source inputs, and a fresh build passes the artifact verifier. Logs retain all excluded attempts. There was no speculative Spotify parser change, dependency, permission/signing-policy change, commit, push, tag, DMG, publication or Stage 27B work.

## B. Sustained Performance

Hardware: MacBook Air Mac16,12, Apple M4 (4 performance + 6 efficiency cores), 16 GiB; macOS 27.0.1 (26A434), Xcode 27.0 (27A266a). Optimized arm64 Release, `-O`/whole-module optimization, explicit `NOTCH_FREE_DISTRIBUTION` across Swift package modules, coverage disabled. No fixtures, mocks, sanitizers, profiling callbacks or Instruments in these long windows.

Measured executable: `/private/tmp/notchium-stage27a3/Notchium Sustained QA.app/Contents/MacOS/Notchium`, PID 46198, SHA-256 `12e51cb6ec5624ac5c5f12083fa25d3746eb8a6e680bafdfe941d068ccc64304`. It uses real production services with disposable identity `com.marcusyu.notchium.qa27a2`, isolated Clipboard disk/Keychain namespace, Pomodoro storage and test preference suite. The `.qa27a2` suffix retains existing QA permissions; it does not designate the source version. Calendar access was read-only. No personal Clipboard content operation or Keychain-value read occurred. The original app was stopped with approval. Temporary awake assertions changed no saved power settings.

These sustained windows precede the final transfer timestamp fix. No transfer publication was active in them; the correction does not change service polling or resource lifetimes. They qualify the stated pre-fix executable and relevant service workloads, not literal sustained execution of the final binary. Final-source builds, regressions and post-fix diagnostics are recorded separately below.

One-second `proc_pid_rusage` v4 deltas use monotonic elapsed time. CPU 100% = one core. Footprint/RSS are sampled MiB (1,048,576 bytes); wakeups are interrupt/package-idle events per second. Peak CPU is a one-second sampled peak, not an instantaneous maximum. All qualifying windows used one long-lived process, so caches carry between scenarios. Native accessibility checkpoints and lightweight hardware queries add disclosed observer overhead. No test/compiler/profiler jobs ran in qualifying windows.

| Real-service workload | Duration | CPU mean | Peak 1 s CPU | Footprint start → end MiB | Peak MiB | Wakeups/s interrupt / package | Verdict |
|---|---:|---:|---:|---:|---:|---:|---|
| Collapsed idle | 600.15 s | 0.01564% | 0.798% | 45.47 → 50.45 | 95.78 | 4.546 / 0.033 | Qualified stated workload |
| Spotify playing, expanded | 600.15 s | 0.55005% | 2.209% | 68.66 → 71.45 | 122.03 | 58.710 / 4.909 | Qualified stated workload |
| Spotify paused, expanded | 300.09 s | 0.00897% | 0.099% | 73.34 → 72.89 | 73.34 | 0.443 / 0.083 | Qualified stated workload |
| Mirror camera | 600.21 s | 0.13148% | 0.219% | 167.50 → 160.53 | 167.50 | 218.027 / 36.794 | Qualified stated workload |
| Clipboard monitoring | 300.17 s | 0.00914% | 0.105% | 110.14 → 110.09 | 110.16 | 2.069 / 0.033 | Qualified stated workload |
| Populated Calendar | 300.14 s | 0.01537% | 0.149% | 110.14 → 110.44 | 110.55 | 1.419 / 0.123 | Qualified stated workload |
| Pomodoro timer | 600.36 s | 0.02275% | 0.191% | 115.38 → 115.61 | 115.72 | 3.829 / 0.346 | Qualified stated workload |
| Local per-app audio gain | 300.12 s | 0.01927% | 0.661% | 117.14 → 117.19 | 117.88 | 0.696 / 0.030 | Qualified stated workload |
| Camera + Clipboard + Calendar + timer | 1200.59 s | 0.08464% | 0.194% | 226.83 → 222.77 | 226.83 | 224.403 / 56.558 | Qualified stated workload |

| Workload | RSS start → end / peak MiB |
|---|---:|
| Collapsed idle | 83.56 → 50.12 / 83.56 |
| Spotify playing, expanded | 78.92 → 75.09 / 79.23 |
| Spotify paused, expanded | 71.09 → 44.17 / 71.09 |
| Mirror camera | 158.42 → 62.80 / 158.42 |
| Clipboard monitoring | 108.77 → 84.78 / 108.77 |
| Populated Calendar | 98.31 → 73.95 / 98.59 |
| Pomodoro timer | 97.23 → 78.56 / 97.23 |
| Local per-app audio gain | 87.98 → 77.47 / 88.33 |
| Camera + Clipboard + Calendar + timer | 116.94 → 59.59 / 116.94 |

Idle had local Spotify control off, Clipboard off, camera closed, timer inactive and real populated Calendar. Playing Music had artwork/waveform and natural track changes. Paused Music remained expanded, with a real seek to 120 seconds read back as paused. Mirror hardware running-device count was 0 before, 1 at start/middle/end and 0 after closing; activation before the sample window was not measured. Clipboard used an existing synthetic QA item and real encrypted storage without copy/paste/clear. Calendar remained populated with normal refresh. Pomodoro used a real QA 60-minute session; system Focus is unavailable in the free profile. Audio used local Spotify, app gain 50%, built-in output, unchanged pre-existing system volume 6.25% and Spotify master 100%.

The final combined workload was explicitly declared before measurement: camera + Clipboard monitoring + populated Calendar + active 60-minute timer; Spotify QA control disabled and app gains unity. Mirror remained expanded at all checks, including near and after completion; hardware was 1 at both ends and 0 after close. Timer still had 39m34s remaining. Clipboard preference was 1 and Spotify local-control preference 0 at the end. The timer was then ended and capture turned off through native controls.

Excluded windows: initial paused 300.15 s ended collapsed; first combined 1200.93 s lacked an end checkpoint; second combined 1200.38 s ended with changed output route and paused Spotify. Timing/cause of those changes is unknown. Raw counters are retained but these runs do not qualify their intended states. The first camera-cycle attempt did not execute because the Mac was locked; the owner subsequently unlocked it.

Historical Stage 27A.2 means (idle 0.0207%, playing 0.6170%, Mirror 0.1566%) are context only. Durations, cache state, opt-ins, playback/output and background load differ; subtracting the means would not establish a regression or improvement. Process counters exclude WindowServer/GPU, camera/audio daemons and Spotify CPU. Wakeups are not watts and establish no battery-life claim. Native checks showed responsive endpoints; continuous frame pacing and significant-stall coverage over every long window were not recorded.

## C. Memory and Resource Stability

Fifty real camera open/close cycles completed: hardware running 1 after every open and 0 after every close, with zero hardware-query errors. The separate 180.73 s cycle/navigation/cooldown diagnostic measured mean CPU 0.520698%, peak 2.037740%, footprint 135.95 → 147.41 MiB, sampled peak 311.69 MiB; RSS 31.27 → 145.98 MiB, peak 182.19 MiB; wakeups 63.636/4.183 per second. Closed batch footprints after cycles 10/20/30/40 were 171.69/165.25/167.02/166.95 MiB, then 147.41 MiB after cooldown. These observations show no progressive growth across those checkpoints; they do not prove zero leaks or attribute transient camera allocations. Sustained Mirror minute means settled near 160.4 MiB. A short post-close sample includes navigation and is not a second idle benchmark.

Source review confirms serialized camera start/stop off MainActor, removal of capture inputs/observers, cancellation of permission/start work and rejection of stale generations. Audio observation uses HAL events and removes listeners on stream termination; mixer ownership serializes configuration and stops IOProc/taps/aggregate devices for empty targets, stop and errors. Realtime buffer work stays in bounded C storage. Intentionally persisted app gain can continue while Audio is hidden.

Separate-process public Core Audio enumeration reported no private tap/aggregate even during audible adjusted playback. It cannot prove private engine presence, teardown or acoustic attenuation. Those limits remain explicit; lifecycle tests and source review provide separate evidence. Existing regressions exercise camera cancellation/release/recovery, observer/task lifetime, thumbnail LRU, balanced file scopes, late IOKit acquisition cleanup, Focus cancellation/order and C audio bounds. No new growing allocation root was attributed. A higher peak alone is not a leak, and earlier stable AppIntents/LinkServices findings are not reopened.

## D. Spotify Edge Case

The original Stage 27A.2 raw nonpositive-duration item is unknown and was not reproduced. The installed Spotify scripting dictionary describes integer duration in seconds, but observed ordinary values are milliseconds (213562, 241675, 280926); player position is seconds. The existing parser matches those actual values.

A focused native search tested [Sound Tiles — Light Switch](https://open.spotify.com/track/0I9LITvqYIfn3R7tSPfVlk), catalog-labelled 0:00. After selecting This computer in Spotify Connect and playing that exact search result once, bounded read-only sampling returned 46 records, 22 matching the candidate. Every matching raw duration was positive integer 398 milliseconds, in both playing and paused states. This is subsecond rounding, not a raw zero. The diagnostic checks descriptor type and records unavailable data as null, avoiding a diagnostic missing-value-to-zero conversion. Notchium's real-service Music UI showed title/artwork, safe position 0, 0:00/0:00, enabled Play and no refresh error. The candidate was left paused; no prior unknown item was guessed or restored.

Local Spotify decoding intentionally rejects zero/negative/nonfinite/missing duration, retains the last good provider snapshot with a refresh issue, and recovers on valid metadata. The generic media model independently handles unavailable duration with preserved metadata/transport, zero safe progress and disabled seek; this does not mean the local parser accepts durationless Spotify snapshots. No OAuth/Web API/queue or speculative fallback was added.

Added coverage exercises positive raw durations 1/398/240000/43200000/Int32.max milliseconds, progress clamping and long-form metadata; invalid raw values 0/-1/Int32.min/nan/inf/-inf/empty/missing; valid paused recovery; Spotify quitting during a held metadata read and relaunch; generic nil/zero/negative/nonfinite duration and return to valid duration. Existing coverage retains paused seeking, stale/old-track reads, finite command bounds and launch/quit. UI time formatting intentionally caps at 24 hours, so parser acceptance of larger values does not promise exact larger duration text.


## E. UI and Motion

The complete functional native suite passed 24/24 on the corrected production source (22 repository cases plus the two established actual-pointer hover cases, normal/reduced motion, retained in the external QA copy). Supplementary diagnostic capture is counted separately. It is not a 25th functional acceptance case.

**UI-03: native visual sign-off incomplete. UI-04: native visual sign-off incomplete.** The first capture helper was denied write access to the shared temporary folder; it was changed to its own sandbox temporary directory. The existing Developer Panel was opened through native XCTest status-menu interaction. A 40-frame batch preceded the intended action timestamps, so it did not capture that interaction and is excluded. Subsequent computer-control button attempts did not demonstrate a state change, and the diagnostic test later reported a crash. No product-crash cause was established. No global security setting, timeout in production, or animation parameter was changed to force a pass. The native setup attempts and crash result are not counted as successful visual verification. A redundant full-plan restart was interrupted and excluded; its partial Caffeine failure is retained, not counted as another complete functional run.

Source and passing regressions retain bounded introduced-entry identity tracking: an AirPods notification restored after preemption is marked settled. Outgoing compact rows have explicit removal rather than two right-aligned values crossfading in one slot; Reduce Motion removes outgoing content immediately. These checks support the implementation but do not replace the missing native normal/reduced visual reproduction.

A standalone final-production-source optimized QA app completed a matched native sequence without and with Instruments: expand, Music → Calendar → Audio → Shelf → Music, Mirror open/close, collapse. The initial unprofiled run also included one priming collapse. Command completion timestamps include accessibility-observer work and are not input-latency measurements. A follow-up real hardware query returned camera running 1 while Mirror was open, then 0 after closing. The action logger initially looked for `Value: On`; the actual accessibility label is `Preview open`, so its false `camera_on` field is an excluded diagnostic interpretation, not hardware evidence.

The bounded Time Profiler + Hitches recording attached to verified PID 63854 and executable `/private/tmp/notchium-stage27a3/Notchium Profile QA.app/Contents/MacOS/Notchium`, SHA-256 `5649663fe3817af035521da45f76dc628cc88e2b7a05256f1e524d61d0ac376e`. It uses the isolated real-service configuration plus diagnostic-only `get-task-allow`; that entitlement is absent from the canonical Release. The trace ran 20.962 s (08:10:21–08:10:42 EDT), finalized normally, and is 23 MiB. It disabled kernel/context-switch/high-frequency sampling, included waiting stacks, checked >3 GiB free before recording, and enforced raw-size/free-space/runtime guards. No guard fired.

Exported evidence: zero `potential-hangs` rows at the 250 ms reporting threshold; 2,424 time samples; 151 application update intervals (maximum 44.201 ms, p95 40.033 ms), including 10 labelled Red by the instrument; 881 render intervals (maximum 16.408 ms); 837 frame lifetimes (maximum 115.847 ms). These are different pipeline intervals, not 837 hitches or a proof of perfect frame pacing. Accessibility frames appear in 93 main-thread samples; waiting stacks include idle `mach_msg2_trap`. Sample weights are therefore not converted to CPU time. No reproducible multi-second main-thread stall was established. Short colored intervals remain disclosed; no zero-hitch claim or speculative performance patch follows from this trace.

No production motion adjustment was made. Main shell response 0.40/damping 0.80, fixed 524×266 pt expanded shell in its 740×322 pt panel, instant direct page navigation and gesture page crossfade remain intact. Fixture captures demonstrate rendering with simulated activities; they are separate from production-service resource benchmarks. Actual screen capture cadence must be read from frame timestamps, not labelled 60 fps.

## F. Regression

| Check on current source | Result |
|---|---|
| Full package main XCTest | 744 executed: 738 passed, 6 expected skips, 0 failures |
| Proactive XCTest | 38 passed, 0 failures |
| Swift Testing, ordinary profile | 5 passed in 2 suites |
| Canonical Xcode unit/integration | 744 XCTest: 738 passed, 6 expected skips; 5 Swift Testing passed; TEST SUCCEEDED |
| Native functional XCUITest | 24 passed; supplementary capture helper failed/unqualified, separate from functional count |
| Address Sanitizer, targeted final source | 92 passed, no sanitizer diagnostics |
| Thread Sanitizer, targeted final source | 93 executed: 91 passed, 2 expected skips, no sanitizer diagnostics |
| Free-distribution flag assertions | 2 Swift Testing cases passed |
| Transfer order stress | 5,040 permutations / 15,120 transfers, zero mismatches in passing final runs |
| Xcode static analysis | ANALYZE SUCCEEDED |
| Debug | Canonical Xcode unit build/test succeeded |
| Optimized Release | Fresh canonical free-distribution arm64 build succeeded; staged artifact verifier passed |
| Release script safety | 5 Python tests passed |
| Production source heuristic scan | 264 files passed; heuristic limits apply |
| Whitespace | `git diff --check` passed |

Receipts: `package-final-verified`, `xcode-unit-final`, `asan-final-verified`, `tsan-freeze`, `analysis`, `free-profile` command/result/log files. The native full GUI bundle is `Test-Notchium-2026.10.19_07-40-16--0400.xcresult` in the QA workspace's Xcode DerivedData test logs. Its complete historical summary is 774 tests: 766 passed, 6 skipped, 2 failed (hover-clock unit assertion and capture sandbox denial). It is not labelled an all-green GUI plan. All 24 functional UI cases passed in that bundle; later canonical package/Xcode unit runs validate the repaired unit tests. Subsequent supplementary capture-only attempts were canceled or reported a crash and remain unqualified.

The final ASan confirmation initially found an existing Spotify lifecycle assertion racing provider publication: the fake script's read-start acknowledgement did not guarantee committed playback. The test now subscribes before relaunch and awaits the actual restored-media event with a bounded XCTest expectation, retaining its final state assertion. All four media additions, transfer correction and lifecycle assertion repairs pass the final listed runs.

All failure receipts are retained. Initial new media setup omitted a required test clock and was repaired. A stale Stage15 assertion expected Home where the owner's current policy requires Music; its comment/name/assertion were aligned while retaining remote-media coverage. The earlier GUI run passed all 24 functional native cases but had two unit failures: a yield-budget Audio test and one transfer stress ordering. The first transfer patch failed the existing stale-event regression and was replaced at the service boundary; no test was disabled, deleted or weakened. Two earlier CLI UI invocations executed zero cases because automation mode could not be enabled; native Xcode GUI testing succeeded without changing global authorization/security settings. Only the external QA project's signing overrides mirror the approved ad-hoc CLI build.

The six default skips are opt-in hardware or diagnostic-visual tests; hardware owner acceptance remains separate from default-suite execution. Targeted sanitizer counts include the actual selected methods and are not substitutes for the full package suite. Existing warnings include FocusService's synchronous API alternative, diagnostic-test actor-isolation/weak-variable warnings and AppIntents metadata extraction with no framework dependency. No new production warning was found in the changed service. No linter is configured; whitespace uses `git diff --check`.

## G. Release Build Hygiene

The canonical staged app is `/private/tmp/notchium-stage27a3/final-staged/Notchium.app`, SHA-256 of its executable `5d36d3e56bd220854afa7000aeb20a13edcd2f21d5445695a910fc4f7d3a606e`. This is the fresh final-source optimized Release, with release-script-equivalent prefix maps, notices, symbol stripping and ad-hoc signing. `verify-release.py --app … --version 1.0.0 --build 2` passes. Verified bundle `com.marcusyu.notchium`, display name/icon Notchium, version 1.0.0/build 2, minimum macOS 26.0, arm64, one intended executable, empty entitlements and ad-hoc identity. This establishes the existing arm64 release policy, not Intel qualification or notarization.

Release free-distribution conditions explicitly reach Swift package compilation. Coverage is disabled globally; no profile instrumentation, test entitlements, QA identifiers/storage routing, fixture startup or diagnostic helper is included in the canonical artifact. The verifier checks executable/resources, forbidden debug/test artifacts, identity, signing and metadata. App resources retain LICENSE and THIRD_PARTY_NOTICES plus required assets. Usage descriptions cover Spotify Apple Events, audio capture, Calendar, Camera, screenshot folders, Downloads, Focus and Reminders. Existing owner-approved provenance/notices are preserved; no dependency or asset was added. The source heuristic secret scan passed (264 files); this is not a mathematical absence-of-secrets guarantee. Production listener observation found no TCP listener in the measured process; it is not a whole-system network claim.

The zero-byte ignored coverage output was preserved with its original path/hash/mtime before removing it from synchronized source inputs. The failing earlier artifact is retained and excluded. The final verifier's first invocation supplied build 1 by mistake; rerunning against the actual configured build 2 passed without modifying metadata. Neither the original contaminated artifact nor the wrong-argument check is counted as a release pass.

## H. Source Freeze

Starting and ending HEAD: `9e91a125e50144bc071e168d4f66038cec18977e` on `main`; no commits were made. Thirteen pre-existing owner paths remain byte-for-byte unchanged from entry. Seven tracked files changed during this verification, plus this report. The final tested tracked-file manifest and binary patch are outside the repository at `/private/tmp/notchium-stage27a3/final-source-manifest.json` and `final-source.patch`. Manifest SHA-256: `723155a8a3a9cd7f29a283d2a1d52a1c5bd5726a28c7afb121af447fb22f496c`. The manifest covers all 576 tracked entry files; this subsequently written report is documentation, excluded from that tested-source fingerprint.

Working tree: 20 modified tracked paths and this new report; nothing staged. The current reviewed candidate comprises:

- [NOTCHIUM_HANDOFF.md](/Users/marcusyu/Projects/notch/NOTCHIUM_HANDOFF.md)
- [NotchiumPackage/Sources/NotchiumDynamicIsland/ActivityCoordinator.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumDynamicIsland/ActivityCoordinator.swift)
- [NotchiumPackage/Sources/NotchiumDynamicIsland/Pages/NotchPageModel.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumDynamicIsland/Pages/NotchPageModel.swift)
- [NotchiumPackage/Sources/NotchiumServices/FileTransferService.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Sources/NotchiumServices/FileTransferService.swift)
- [NotchiumPackage/Tests/NotchiumFeatureTests/AudioMixerTests.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Tests/NotchiumFeatureTests/AudioMixerTests.swift)
- [NotchiumPackage/Tests/NotchiumFeatureTests/DefaultExpandedPageTests.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Tests/NotchiumFeatureTests/DefaultExpandedPageTests.swift)
- [NotchiumPackage/Tests/NotchiumFeatureTests/FocusedBugFixTests.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Tests/NotchiumFeatureTests/FocusedBugFixTests.swift)
- [NotchiumPackage/Tests/NotchiumFeatureTests/MediaProgressTests.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Tests/NotchiumFeatureTests/MediaProgressTests.swift)
- [NotchiumPackage/Tests/NotchiumFeatureTests/NavigationOwnershipTests.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Tests/NotchiumFeatureTests/NavigationOwnershipTests.swift)
- [NotchiumPackage/Tests/NotchiumFeatureTests/PomodoroAutomaticOpenTests.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Tests/NotchiumFeatureTests/PomodoroAutomaticOpenTests.swift)
- [NotchiumPackage/Tests/NotchiumFeatureTests/SpotifyMediaTests.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Tests/NotchiumFeatureTests/SpotifyMediaTests.swift)
- [NotchiumPackage/Tests/NotchiumFeatureTests/Stage10CoordinationTests.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Tests/NotchiumFeatureTests/Stage10CoordinationTests.swift)
- [NotchiumPackage/Tests/NotchiumFeatureTests/Stage12ActivityTests.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Tests/NotchiumFeatureTests/Stage12ActivityTests.swift)
- [NotchiumPackage/Tests/NotchiumFeatureTests/Stage15StabilizationTests.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Tests/NotchiumFeatureTests/Stage15StabilizationTests.swift)
- [NotchiumPackage/Tests/NotchiumFeatureTests/TransferTerminalStateTests.swift](/Users/marcusyu/Projects/notch/NotchiumPackage/Tests/NotchiumFeatureTests/TransferTerminalStateTests.swift)
- [docs/ARCHITECTURE.md](/Users/marcusyu/Projects/notch/docs/ARCHITECTURE.md)
- [docs/HOME_DASHBOARD.md](/Users/marcusyu/Projects/notch/docs/HOME_DASHBOARD.md)
- [docs/NOTCH_SHELL.md](/Users/marcusyu/Projects/notch/docs/NOTCH_SHELL.md)
- [docs/STAGE10_COORDINATION.md](/Users/marcusyu/Projects/notch/docs/STAGE10_COORDINATION.md)
- [docs/STAGE16_19_UTILITIES.md](/Users/marcusyu/Projects/notch/docs/STAGE16_19_UTILITIES.md)
- [docs/STAGE27A3_FINAL_ENGINEERING_CHECKLIST.md](/Users/marcusyu/Projects/notch/docs/STAGE27A3_FINAL_ENGINEERING_CHECKLIST.md)

The additional production change is confined to FileTransferService; media changes are tests. No package dependency, project configuration, signing setting, entitlement, permission policy or animation parameter changed in the canonical repository. All ad-hoc GUI signing and screenshot helper changes stay in the external QA copy. The personal-data comparison checked nine snapshotted storage/preference files: none missing or changed. Personal Keychain values were not inspected. No reset/restore was attempted.

Proposed commits, subject to owner authorization:

1. Preserve the owner's local-Music fresh-expansion policy and synchronized documentation/tests, including the corrected Stage15 expectation.
2. Correct authoritative transfer timestamp ordering with its regression, and make Audio/hover lifecycle tests await actual completion.
3. Add Spotify duration/quit safety coverage and this final engineering report.

No staging, commit, push, tag, release artifact publication or packaging is authorized/performed. After an accepted freeze, changes should be limited to onboarding/distribution defects and genuine blockers, each with targeted regression verification.

## I. Final Verdict and Next Stage

**CONDITIONAL GO. Stage 27B may proceed in parallel. Public distribution is not approved, and the final release freeze remains provisional.**

The limited conditions are:

1. Obtain native normal- and reduced-motion visual sign-off for UI-03 (settled AirPods restoration after preemption) and UI-04 (clean compact replacements and rapid successive activities). The failed supplementary capture workflow is not acceptance evidence. Use the existing Developer Panel on a stable native session; preserve the current motion values unless a reproducible defect is identified.
2. Carry the original unknown Spotify raw nonpositive-duration case as an explicit limitation. The observed 398 ms song and invalid-input regressions pass; do not claim the original raw-zero case reproduced. No speculative parser change is required absent new evidence.
3. Complete Stage 27B onboarding/persistence and later distribution validation before any public release. Neither was performed here.

No new broad audit is recommended. The current production changes are small, resource measurements are qualified for their declared workloads, full functional regressions pass, and the canonical artifact passes hygiene checks. Stage 27B can validate onboarding and persistence independently while the two visual conditions are completed; approval of an unconditional final freeze must wait for their sign-off. No commit or push was performed. Commit grouping above is a proposal for owner approval after reviewing the candidate and these conditions.

At cleanup, the owned QA apps were closed, camera running count was 0 with no query errors, QA Clipboard capture and timer had been stopped after their runs, and QA app gain was restored to unity. The original debug app remains stopped; its Xcode workspace was preserved. No saved power or global privacy/security setting changed. The Spotify candidate was paused during its test; later external playback state was not overwritten.

Evidence is local under `/private/tmp/notchium-stage27a3`: per-run CSV/JSON, qualified/excluded receipts, camera cycle actions/hardware observations, bounded Spotify probe, actual native screenshots and xcresults, build/sanitizer/analysis logs, isolation records, source manifest and patch. Raw accessibility checkpoints, Calendar/Clipboard context and full-screen captures remain private and are not embedded in this report. Generated build directories may be removed for space after preserving their receipts/apps; logs and results are not release deliverables.

Skills actually consulted: apple-design, emil-design-eng, apple-motion-feel, swiftui-expert-skill (with references), swift-concurrency, apple-swiftui-native-apps, apple-device-validation, instruments-profiling, xcodebuildmcp, context7-mcp and swift-code-review (with references). XcodeBuildMCP was unavailable, so established Xcode CLI/native fallbacks were used. Apple responsiveness guidance was fetched through Context7. No third-party tool was installed or implementation copied into production.
