# Final optimization and button quality pass

October 8, 2026. Scope: the finished Notchium macOS app, with no new features or redesign. Existing uncommitted work was preserved. Nothing was committed, pushed, published or distributed.

This report distinguishes source findings, automated tests, native interaction checks and profiler measurements. A source review or passing test does not certify every hardware/account state. The verification gaps below prevent claiming a complete pre-publish performance/accessibility certification.

## 1. Skills and independent reviews

| Skill / source | Applied purpose |
| --- | --- |
| `swiftui-pro`, [twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill) | Performance/performance-plus, data, views, accessibility and Swift references; observation boundaries, identity, hidden views and resource ownership. |
| `write-swift`, [emilkowalski/skills](https://github.com/emilkowalski/skills) | Swift 6 actor isolation, ignored implementation state, task cancellation and ownership. |
| `apple-design`, same repository | Immediate native press feedback, hit regions and restrained interaction. |
| `emil-design-eng`, same repository | Button hierarchy, hover/press consistency, spacing and native conventions. |
| `improve-animations` and `review-animations`, same repository | Scoped microinteraction review before and after corrections; approved shell motion preserved. |
| `break-ui`, same repository | Long metadata, CJK/emoji, unavailable controls and narrow existing geometry. No production demo feature was added. |
| Impeccable native audit, `optimize`, `polish`, [pbakaus/impeccable](https://github.com/pbakaus/impeccable) and installed Impeccable skill | Native control states, resource use and evidence boundaries. Upstream iOS/Android guidance was adapted to macOS; no blanket 44 pt target rule. |
| UI-UX Pro Max, [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | Secondary checklist and SwiftUI data for focus, contrast, semantics and targets. |
| `code-review-excellence`, [wshobson/agents](https://github.com/wshobson/agents) | Independent scoped regression review. |
| `verification-before-completion`, [obra/superpowers](https://github.com/obra/superpowers) | Fresh builds/tests, inspect exit status, distinguish limitations from passes. |
| Repository `instruments-profiling` and `xcodebuildmcp` | Local xctrace measurements and native build/test fallback. XcodeBuildMCP tools were not exposed, so Xcode CLI was used. |

The exact requested `accessibility-compliance`, `screen-reader-testing`, `systematic-debugging` and `debugging-strategies` skills were unavailable; their use is not claimed. Existing product, Stage 21/22/23, architecture and engineering documentation governed decisions.

Three independent read-only reviewers covered all eight requested perspectives: SwiftUI performance/Swift concurrency; Apple interaction/button craft/native audit/accessibility checklist; and animation/regression. A fourth reviewed final measurement/report accuracy and the Mirror accessibility finding. Findings were consolidated into one implementation. The final Observation/visibility diff was accepted; no geometry or motion regression was identified. Caffeine disabled-hover teardown was re-reviewed after moving its state update into SwiftUI `onChange`, and hosted tests covered disable/re-enable behavior.

Detailed inventories: [button/control audit](FINAL_BUTTON_AUDIT.md), [performance/resource audit](FINAL_PERFORMANCE_AUDIT.md).

## 2. CPU findings and correction

An unchanged Release executable was saved before this pass. Measurements used the same MacBook Air, macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), arm64 and 1470 × 956 pt display at 2×. Production deployment remains macOS 26+, Swift 6 complete concurrency.

Important configuration limit: both saved baseline and final Release contain Swift coverage instrumentation (`-profile-coverage-mapping`, `-profile-generate` and coverage symbols), despite the CLI Clang coverage override. These are optimized, instrumented Release measurements, not certified uninstrumented shipping numbers. The earlier approximate 0.5–1% CPU / 60–65 MB range was not treated as a target.

The baseline Time Profiler's post-warmup samples contained 3,175 ms of sampled thread time. Leading leaf frames were AttributeGraph propagation (633 ms), update stack (485 ms), and subgraph update (382 ms). `SystemAudioMeter.waveformLevels.setter`, `MediaWaveform.body` and `AudioMeterPermissionView.body` appeared on this path. These are sampled costs, not precise body invocation counts.

The source-confirmed cause was broader than required notification delivery: `SystemAudioMeter` used `ObservableObject`, broadcasting each waveform sample to consumers that needed only status or were hidden. The producer can publish up to 30 Hz. The minimal correction uses Observation property reads, ignores private lifecycle/task implementation state, and checks presentation/playback/Reduce Motion before reading sample levels. Settings status no longer subscribes to levels. Existing capture intent, activity grace, producer rate and Spotify reconciliation remain authoritative.

Real-meter observation tests prove that a level sample invalidates a level consumer without invalidating stable status/activity consumers. Hidden/Reduce Motion waveform rendering tests prove suppression while local playback capture remains running. This qualifies as eliminated redundant work; no numerical CPU reduction is claimed from incomparable playing windows.

## 3. Memory, camera and retention

No measured image/cache or camera leak root cause justified a production memory rewrite. Artwork remains one bounded shared cache (eight 160 px thumbnails, about 1 MB target cost, 2 MB response limit). File/screenshot thumbnails remain a 48-entry size/scale-aware LRU. Clipboard keeps bounded 96 px thumbnails and 2048 px copy-back payloads, with bounded history/pins. Mirror uses an AVFoundation preview layer without storing frames or adding capture outputs.

These native stress/scanner checkpoints predate the later accessibility-only Mirror wording correction. Native stress completed on one final Release process: **100 verified notch open/close cycles and 50 verified built-in-camera preview open/close cycles**. Each camera cycle confirmed the app's live-camera state, built-in camera selection and subsequent Off state. Unconfirmed automation attempts were excluded. This is lifecycle/AX evidence, not proof that every rapid cycle decoded a frame or that the physical indicator timing was measured.

System `leaks` scans (without object contents):

| Checkpoint | Malloc nodes | Malloc heap | Unreachable finding |
| --- | ---: | ---: | --- |
| Early final run | 289,040 | 35,811 KB | 0 bytes |
| After ten camera cycles | 336,441 | 41,127 KB | One 80-byte `CFString` |
| Later idle recheck | 325,172 | 40,575 KB | Same 80-byte `CFString`, same address |
| After 100 notch / 50 camera cycles | 345,126 | 42,687 KB | Same one 80-byte finding |

The finding has no recorded allocation stack and is unattributed. It did not multiply in these scans; it is not silently dismissed as a framework leak. Malloc heap at the immediate checkpoints grew, so that table is not evidence that retained heap returned to its starting value.

An isolated mock fixture completed a fresh, sequential **100 Shelf ↔ Clipboard cycles**, checking both selected states. Earlier interrupted/overlapping automation batches were excluded by resetting the automation session. The fixture had empty file/history states, so this does not stress populated Clipboard/image data. Its scanner reported 416 / 415 unreachable blocks (19,936 / 19,888 bytes) before / after the broader fixture run. Heap grew from 29,188 to 42,046 KB, and footprint from 54.3 to 78.0 MiB; native Settings had also been opened before the second scan. These mixed fixture checkpoints cannot attribute retained growth to navigation or certify leak-free behavior. The nonzero initial findings are explicitly retained in the evidence.

Settled closed-window physical footprint averaged 102.72 MiB after ten camera cycles and 102.43 MiB after fifty. Both final windows had zero measured disk bytes. This is evidence of no increasing settled footprint in those two windows, with normal warm caches/framework retention; it is not an Allocations generation comparison. Heap type census after closure contained one Notch panel/root hosting graph and no listed `AVCaptureSession` or `AVCaptureVideoPreviewLayer` instances; AVFoundation device enumeration objects remained. A census is supporting evidence, not deallocation certification.

Two Instruments Leaks/Allocations recordings exhausted available local storage and failed saving their archives. Failed recordings were excluded and removed. The system scanner/census is a bounded fallback. **No leak-free claim is made.**

## 4. SwiftUI, recurring work and ownership

The change narrows notification delivery and hidden waveform reads without introducing a second model, cache or scheduler. Both views retain the same injected meter. No shell-wide hover state, per-click visual task, new timer, ranking change or polling slowdown was added.

The source audit inventories every recurring subsystem: playback/queue/device refresh, waveform/watchdog, Clipboard, Progress/KVO, screenshots/Spotlight, Calendar, Pomodoro, Focus, audio HAL, battery, camera, display/pointer/Space events, Caffeine, optional lid helper and Shortcuts. Cadences and ownership are detailed in FINAL_PERFORMANCE_AUDIT.md.

Notable preserved boundaries: one Spotify playback loop; Up Next refresh only while visible; 30 s device cache; Clipboard idle checks only `changeCount`, with content reads on change and subscriber-owned monitoring; Progress mailbox coalesces at 250 ms while terminal evidence latches synchronously; native screenshot/Calendar/audio/battery notifications; local visible timelines instead of a shell-wide 1 Hz timer. Resource teardown and bounded image representations retain Stage 22 behavior.

The collapsed wrapper gates expansion, not every possible higher-priority collapsed presentation. Therefore this pass does not claim that every retained hidden tree has zero subscriptions.

## 5. Button inventory and corrections

Independent source inventory covers **154 production SwiftUI declaration sites**: 115 Button, 11 Toggle, 11 Picker, six TextField, four Stepper, two DatePicker, and one each Menu, ColorPicker, Slider accessibility representation, NavigationLink and SettingsLink. It also covers the native Audio options NSButton, Caffeine menus, slider input, page swipe and Shelf drag adapters. This is a source count; list/enum-generated runtime instances vary.

Every global/header, Home, Media, Calendar, Audio, Shelf, Clipboard, Focus Timer, Mirror, Settings, HUD and system-panel control family has role/routing/state/target notes in FINAL_BUTTON_AUDIT.md. Twelve production-source files were changed; a separate DEBUG-only fixture correction isolates UI tests from live credentials/network after the Keychain interruption was identified. System-owned panels and native Settings controls intentionally retain platform behavior.

Corrections:

- Caffeine now dims immediately on pointer down; cancel/release resets observed pressed state. Normal clicks create no visual task. Disabled pointer input suppresses hover, cancels a press, and SwiftUI clears hover-only content on disable.
- Calendar Join retains hover/pressed fill feedback with Reduce Motion enabled; existing ordinary scale and routing are preserved.
- Home transport reuses the established Media control style and keeps existing targets/actions.
- Search clear retains its 11 pt glyph inside a centered 24 × 24 pt circle, with local hover/press feedback and help.
- Clipboard uses the inherited Reduce Motion policy. Its named Pin action is omitted at the pin cap; Unpin/Delete availability follows the actual model.
- Caffeine adds a small active checkmark only under Differentiate Without Color. The approved ordinary indefinite state still has no timer border.
- Mirror's header now announces `Preview open` rather than `Camera on` while its preview/permission/recovery surface is presented. Native permission-screen inspection proved that presentation was being confused with successful capture; the model/action/selection/geometry are unchanged. The corrected regression setup reproduced the old `Camera on` value at its value assertion before the change.

## 6. Button states

Shared styles deliberately provide local hover, synchronous pressed feedback and disabled guards. Calendar/Home retain short established motion; reduced motion removes movement while retaining static feedback. Standard native focus and role semantics are preserved. Caffeine/page navigation/shortcuts/sliders have explicit focus treatment. Selected navigation, shuffle/repeat, swatches and toggles retain their native/explicit selected state.

Loading/unavailable controls are guarded by capability or busy state and accompanied by existing status/recovery copy. No decorative pill/card system or blanket target enlargement was introduced. Destructive action contracts were reviewed and left within approved existing behavior; no user data was cleared during this audit.

## 7. Accessibility and keyboard

Native XCUITest verifies Caffeine Space/Return activation, Down Arrow duration menu, Escape cancellation, timed selected/value behavior, search clearing outside the tiny glyph and slider pointer/keyboard actions. The macOS slider regression test now uses XCUIAutomation's mouse drag API (`click(forDuration:thenDragTo:)`) rather than a touch press/drag, retaining its assertions.

AX inspection confirms native button/slider roles, names, selected/disabled states and meaningful values in visited pages. Source review covers named Clipboard actions and control labels/help. This is accessibility-tree QA, **not a spoken VoiceOver session for every control**. Complete Tab/Shift-Tab traversal remains a gap: the native attempts activated/collapsed the panel rather than proving traversal through all controls. No system accessibility setting was changed to manufacture a pass.

Native-hosted tests cover Increase Contrast slider track visibility, inherited Reduce Motion waveform suppression and Reduce Transparency treatment. The quality fixture was also inspected with Reduce Motion enabled. An attempted non-color Caffeine rendering fixture could not override the SDK's read-only system accessibility preference and was removed. The small non-color cue is source-reviewed; no automated or native visual pass under that system preference is claimed.

## 8. UI and hostile content

Native quality-fixture screenshots/AX checks covered Home, Music, Calendar, Audio and Focus Timer. Long CJK/emoji media metadata, long Calendar titles and long output names remained within existing geometry with controls available. Timer Start → Pause → Resume → Pause → End and History → Back were verified in the isolated in-memory fixture. Phase-specific Skip was not exercised natively; feature/control tests cover its routing. Empty Shelf controls and disabled actions were inspected without sending files.

The broader source hostile-content matrix covers filenames, camera/device names, counts, missing artwork/metadata/files, pin caps, errors and unavailable controls. It is not labeled a complete rendered matrix. All eight Settings categories were inspected through native AX and screenshots, including lower Focus Timer actions by scrolling. The colour-mode menu was opened/cancelled without changing its stored choice; conditional static swatches were source/test-reviewed, not rendered during that visit. Standard disabled shortcut actions, selection/radio values, empty Calendar state, Clipboard policy and Caffeine recovery copy were readable. The fixture uses mock services/in-memory histories, but some appearance settings share standard defaults; no setting was changed.

The user-required collapsed-height constraint is preserved: physical collapsed height still comes from `safeAreaInsets.top`; virtual height comes from menu-bar geometry/status-bar thickness. No layout, panel placement, silhouette, top anchor or global shell-motion source was changed. The 740 × 322 pt transparent host used in UI tests is the expanded-capable window, not collapsed visible height. Existing physical-notch/menu-bar geometry tests cover this distinction.

## 9. Regression validation

Final fresh complete run after the DEBUG fixture correction: **17 UI tests passed in 243.768 s; 700 XCTest feature tests passed in 52.814 s with no skips; four Swift Testing tests passed. Zero failures; command exited 0.** The log contained no SecurityAgent interruption or “Modifying state during view update” warning. Mirror's true red/green regression is established. The real screencapture detection test also passed in this final local run; it had been skipped in earlier runs. Explicit final Debug and Release builds succeeded using the documented local-only signing overrides.

Earlier runs and diagnosis:

- Complete suite: 16 UI tests passed; 700 XCTest feature tests passed with one existing screenshot-folder skip; four Swift Testing tests passed (including a parameterized four-case test). Zero failures; command exited 0.
- After the final production Caffeine hover correction: complete 700-test feature suite and four Swift Testing tests passed, zero failures, one existing skip; no “Modifying state during view update” warning.
- After extending the hosted disabled-hover test: eight timed Caffeine feature tests and two Caffeine keyboard/menu UI tests passed, zero failures.
- Debug and Release builds succeeded. No configured lint command was found. Repeated `git diff --check` runs passed; the final documentation-inclusive check is recorded below.

Coverage includes ActivityCoordinator ranking, terminal transfer classification/coalescing, Clipboard encryption/persistence/bounds, screenshot lifecycle, native sharing ownership, Calendar, camera model/service shutdown, media remote/local policy, timer deadlines/open rules and Stage 21/22/23 geometry/accessibility.

A later fresh rendering-test attempt was blocked before tests by a missing development provisioning profile; ad hoc identity alone still required a profile. Project signing configuration was not changed. A local-only fallback additionally omitted profile-dependent entitlements through command-line overrides. After removal of the unsupported preference-injection test, the complete 700-test feature suite and four Swift Testing tests passed again (zero failures, command exit 0). This is local test validation, not verification of distribution signing/capabilities. After the Mirror wording correction, another complete run passed 700 feature tests and four Swift Testing tests but failed nine UI assertions across 17 UI tests. A quiet-desktop rerun passed 12 of 17 UI tests and failed five, with a persistent macOS SecurityAgent dialog explicitly recorded as an unhandled interruption. The Mirror permission-screen value and selected assertions passed in that rerun; its post-close lookup failed after the panel collapsed. The computer-use tool blocks SecurityAgent access. After the user cleared the dialog, the next run again recorded SecurityAgent interruptions and failed nine of 17 UI tests. The user identified the request as access to the Notchium.Spotify Keychain entry. Source tracing found that display-only UI fixtures still constructed production services. The tests now use the existing mock-service fixture; the Settings reopen case retains its real connection controls through a DEBUG-only empty token store and a network-blocking transport, keeping the same assertions. Production services/signing/credential policy are unchanged. A build-for-testing and the subsequent complete run passed as recorded above. Explicit final-source Debug and Release builds passed using local-only signing overrides. The documentation-inclusive `git diff --check` passed after the final source/test changes; it is repeated after report finalization. Attempting the existing Apple Development identity without a team/profile also failed, so that signing path is not claimed as validated.

## 10. Measurements and baseline coverage

The after recordings include the observation/button corrections and predate the final accessibility-only Mirror wording correction. That later correction has no re-recorded CPU/memory window and no numerical performance claim. Activity Monitor captures were 35 s for held states; reported values use the final ~15 s. CPU is aggregate counter delta / elapsed wall time, with 100% equal to one fully used core. Memory is mean physical footprint, not malloc heap or resident size. Wakeups use the `idle-wakeups` counter delta / the same window. CPU-time and resident measurements are included to avoid conflating quantities. No percentile/confidence interval is claimed from single windows.

| Scenario | Before CPU | After CPU | Before footprint | After footprint | Idle wakeups/s before / after | Notes |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| Mirror active, built-in camera | 1.813% | 1.980% | 147.51 MiB | 151.87 MiB | 225.28 / 226.38 | Valid held camera windows. No demonstrated improvement; no repeated variance estimate. |
| Expanded Music, paused | 0.086% | — | 89.15 MiB | — | 1.02 / — | Baseline held correctly; final comparable window unavailable. |
| Expanded Music, local playing | 19.120% | — | 91.12 MiB | — | 59.60 / — | Baseline track changed within the recording. Final attempts collapsed; excluded rather than compared to a different visible state. |
| Cold notch closed, paused | 0.607% | — | 48.34 MiB | — | 1.12 / — | Cold baseline cannot be compared with warm post-camera final memory. |
| Warm closed after ten camera cycles | — | 0.763% | — | 102.72 MiB | — / 1.02 | Final-only checkpoint, remote/current account state; not an optimization percentage. |
| Warm closed after fifty camera / 100 notch cycles | — | 0.227% | — | 102.43 MiB | — / 0.48 | Final-only settled checkpoint; zero disk read/write delta. |
| Two-minute warm idle after stress | — | 0.272% | — | 102.46 MiB | — / 0.75 | Last 14.658 s of a 120 s recording; closed start/end verified; no matched prolonged baseline. |

Camera CPU time was 264.12 / 289.27 ms over 14.568 / 14.608 s. Mean resident memory was 202.72 / 161.31 MiB; resident difference is not a footprint reduction. Camera threads were 13–14 / 12–13. The final post-stress closed window used 33.41 ms CPU over 14.714 s, 77.32 MiB resident and 7–8 threads. The pre/post camera windows had zero disk counter deltas.

| Required scenario | Evidence status |
| --- | --- |
| Closed idle | Valid cold baseline and warm final checkpoints; no comparable cold final pair. |
| Home open | Source, native UI and tests; attempted baseline did not stay open, excluded. |
| Media playing / paused | Baselines above; final comparable Music windows not established. Source/observation tests verify the correction separately. |
| Clipboard monitor idle | Production capture preference remained off. Count-only/subscriber lifetime validated by source and tests; no live idle-monitor CPU pair. |
| Pomodoro running | Native mock interactions and feature/deadline tests; attempted CPU export had no usable samples. |
| Mirror closed / active | Native 50-cycle checks, held active comparison and warm closed counters. |
| One / several downloads | Progress publisher experiments were not controlled valid pairs; discarded. Coalescing/terminal correctness source and stress tests passed. No actual network-download benchmark. |
| Repeated open/close | 100 native notch cycles, 50 live camera cycles, 100 fresh sequential Shelf/Clipboard cycles in the empty fixture, scanner/census and settled footprint. |
| Prolonged idle | Two-minute final recording completed with closed start/end; final footprint 102.46 MiB. No matching prolonged baseline. |

The SwiftUI/body-update Instruments template failed its local database setup. No body-count, frame-rate, request-count or full energy certification is claimed. Time Profiler's final collapsed recording uses a different visible state from the expanded baseline and is excluded from numerical comparison. Network requests and filesystem ownership were source-audited; only per-process disk counters above were measured.

## 11. Rejected optimizations

- Another decoded Clipboard-row image cache: small existing representations, no demonstrated heavy decode cost; new invalidation/retention risks.
- Replacing PCM queue/FFT processing: hypothetical backlog without reproduced growth; preserve approved activity/local-versus-remote detection.
- Splitting MediaState into multiple authorities: extra synchronization for an unmeasured provider-cadence gain.
- Replacing Clipboard polling or slowing Spotify: supported low-cost count-only polling and approved responsiveness take priority over speculative wakeup savings.
- ActivityCoordinator sort/identity rewrite: small active set, equality guards/coalescing, no measured hotspot; preserve ranking.
- Evicting completed-transfer tombstones: would risk resurrection from late progress; service epoch/acknowledgment design requires evidence first.
- Blanket 44 pt buttons, taller collapsed notch, new glass/card shapes or global spring changes: conflicts with approved compact macOS geometry and this pass's scope.
- Styling every plain/native button without native evidence: source absence of a custom modifier does not prove missing platform feedback.

## 12. Remaining evidence-backed issues and gaps

One persistent, unattributed 80-byte `CFString` leak is reported by the system scanner. Successful Allocations/Leaks generation analysis is unavailable because recording archives exhausted storage. Full retained-heap/resource release therefore remains uncertified.

The requested twelve-state matched before/after benchmark matrix is incomplete. Unheld/mixed windows, empty exports, coverage instrumentation and real playback changes limit conclusions. There is no numerical CPU or memory optimization claim beyond the reported raw comparable camera pair; the accepted performance change eliminates redundant notification work.

Full spoken VoiceOver QA and complete Tab/Shift-Tab traversal remain outside the completed evidence. The final native Share/AirDrop attempt was blocked by the Mac locking again; the disposable fixture file was created but no sharing dialog was opened and nothing was sent. A repeated check confirmed the Mac remained locked. The unlock request is pending. Further agent-executable verification also remains: all rendered hostile-content/control states, native Share/AirDrop open/cancel, repeated real Quick Look/artwork changes, many screenshots and actual concurrent downloads. These are outstanding audit tasks, not all hardware-only manual checks. Clipboard's initial focus visibility and plain-control feedback remain native-verification candidates, not established defects. No speculative production correction was made for them.

## 13. Manual/hardware checks

Checks requiring human hearing/visual judgment or hardware observation remain: spoken VoiceOver announcements, optical button/focus feedback, and physical camera-indicator/release timing. Instruments retained-allocation analysis needs adequate storage. The other incomplete native/workload/benchmark checks are listed as verification tasks above; they are not mislabeled as requiring human judgment. Use the approved display geometry and preserve existing data/preferences.

Temporary playback on the Mac was restored to the iPhone after the authorized measurement. Camera measurement was explicitly authorized. Production Clipboard capture was not enabled and no user files/history were removed or sent. Analyzed profiling/test/scanner diagnostics and the temporary test checkout/builds were removed. The unchanged baseline executable, initial source snapshot and initial diff remain temporarily because the requested matched benchmark matrix is still unfinished; they support continuation once the Mac is unlocked. They are not committed or distributed. The final cleanup/diff outcome is recorded below; no publishing work follows this pass.

Final checks: the final documentation-inclusive `git diff --check` passed. The initial-source comparison confirmed exactly twelve production-source edits plus the DEBUG-only fixture; panel/layout/display/silhouette/transition sources remained byte-for-byte unchanged. The final read-only reviewer checked the passing test/build logs and report accuracy. All analyzed diagnostic/build artifacts and their logs were removed, and the owned mock QA process was stopped. Only the unchanged baseline executable, initial source snapshot and initial diff remain outside the repository for the outstanding matched benchmark continuation. Native verification remains blocked by the locked Mac; no complete performance/accessibility certification is claimed.
