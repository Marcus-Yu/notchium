# Stage 27A.1 — final audit

Date: October 16–17, 2026 (America/Toronto). Working tree: `main` at `7ef5522`, on top of the uncommitted Stage 27A corrections. Nothing was committed, tagged, packaged or published. Onboarding validation, DMG packaging and GitHub release were not started.

Scope note: the original Stage 27A.1 brief is not in the repository. Its performance, regression, concurrency, security and code-quality evidence is the Stage 27A record in [STAGE27A_AUDIT.md](STAGE27A_AUDIT.md), which remains the authority for those areas. This stage re-ran the complete package suite after its own changes (below) and replaced Phase 6 with the expanded UI audit in the addendum. No Stage 27A conclusion was re-qualified beyond that re-run.

> **Latest receipt:** the [Codex continuation](#codex-continuation--october-17-2026) below supersedes the initial receipt and unavailable-tool statements where explicitly stated. The original offscreen audit, its counts and findings are preserved as historical evidence. The latest overall verdict remains **NO-GO**.

## Overall gate

**NO-GO.** Stage 27A's blockers are unchanged: the native XCUITest runner does not bootstrap, the hardware/permission matrix is unqualified, and source provenance is unverified. The UI verdict below is **CONDITIONAL**. Six UI defects were found and corrected with rendered before/after evidence, but on-screen input, frame pacing and assistive-technology checks could not be executed in this session.

| Run (after all changes) | Result |
|---|---|
| Complete package suite (`swift test --disable-sandbox`) | Main XCTest **736 executed, 0 failures, 6 skipped** (4 existing opt-in hardware tests, 2 opt-in visual-capture tests); proactive XCTest **38/38**; Swift Testing **5/5** |
| New regression tests (`Stage27A1UIQualityTests`) | 2/2 pass |
| Debug and Release app builds (`CODE_SIGNING_ALLOWED=NO`) | `BUILD SUCCEEDED` (both) |
| `git diff --check` | Clean |

## Apple-Native UI & Motion Quality Report

### How the UI was examined

| Method | What it shows | Limits |
|---|---|---|
| **Offscreen shell renders** (`Stage27A1VisualCaptureTests`, opt-in) | The real `NotchiumShellView`, composed by `NotchiumApplicationController` over mock services, hosted in an offscreen `NSWindow`. It captures every page, transient activities, Mirror and Settings, plus frame sequences sampled every 25–35 ms during open, close, reversal, compact swaps and Mirror. It runs once with normal motion and once with a Reduce Motion override. All content is synthetic `break-ui` data. | Not on screen. `cacheDisplay` does not reproduce 3D transforms or glass faithfully, and an offscreen window bypasses the compositor, so these frames prove geometry, order and opacity, not frame pacing. |
| **Native fixture app** (Debug, `--ui-testing --notchium-stage11-fixture --notchium-quality-fixture`) | Panel placement (740 × 322 pt at the top centre of the built-in display, screen-saver level) and the collapsed shell rendered by the real window server, captured by Notchium's own window ID only. Idle CPU sample. | Synthetic input is not permitted for this terminal (`CGPreflightPostEventAccess` = false) and computer-use tools were unavailable. No native hover, click, keyboard, VoiceOver or expanded-state check was possible. |
| **Existing composition tests** (`ExpandedPageCompositionTests`) | Each page in isolation. | Pages are hosted without the shell. The focus rings they show around Caffeine and a slider are a harness artifact: they do not appear in full-shell renders. |
| **Source review** | Every animation call site (203 matches across feature and shell sources), all button styles, the design tokens and the shell transition state machine. | Source review alone is not counted as visual verification anywhere below. |

Host: MacBook Air `Mac16,12` (Apple M4), built-in Liquid Retina display 1470 × 956 pt, **60 Hz maximum** (`NSScreen.maximumFramesPerSecond`; no high-refresh display available). macOS 27.0.1 (26A434), Xcode 27.0 (27A266a). Deployment target unchanged (macOS 26).

Privacy incident: the first native attempt used a screen-region capture. It included personal desktop content (widgets and a System Settings window) and no Notchium pixels. The file was deleted immediately, was never shared, and contributes no evidence. All later native captures used the Notchium window ID only. Evidence images stay in the session scratchpad and are not repository artifacts. To regenerate them:

```sh
NOTCHIUM_VISUAL_CAPTURE_DIR=/path/to/out swift test --package-path NotchiumPackage --disable-sandbox --filter Stage27A1VisualCaptureTests
NOTCHIUM_VISUAL_REDUCE_MOTION=1 NOTCHIUM_VISUAL_CAPTURE_DIR=/path/to/out-rm swift test --package-path NotchiumPackage --disable-sandbox --filter Stage27A1VisualCaptureTests/testCaptureExpandedPagesAndMotion
```

### 1. Visual consistency

- **Typography:** system font throughout. Page titles, body, captions and section labels mostly follow `ExpandedPageStyle`. The Calendar page used a one-off 10 pt / 0.6 calendar-name label beside the 11 pt `sectionTitle` "Up Next" label on the same row. That was corrected (UI-02). Home says "Next events" and Calendar says "Up Next"; they list different sets (Home includes the current event), so the wording was left.
- **Spacing and alignment:** the header (page buttons, utilities, close) and the outer 30 pt inset are consistent on all six pages and Clipboard. The Calendar right column sat about 8 pt above the left column (UI-02, corrected). Shelf and Clipboard toolbars share `NotchToolbarMetrics` and align.
- **Controls:** every pressable notch control uses fill-based hover. Press feedback was intended to be one convention (0.97 scale, 0.16 s smooth), but the toolbar used 0.93/0.08 s and Join used 0.96 plus a 1.03 hover grow (UI-06, aligned).
- **Materials and colour:** black shell, white-opacity fills, glass only on header utilities. No new glass, gradient or shadow was added.
- **Extreme content (break-ui):** CJK, emoji, 400-character and URL clipboard entries, long multilingual track, artist, event, location, device and file names, a two-hour track, 0%/5%/100% levels and empty Local Audio Apps. All truncated or wrapped within their columns with no clipping or overlap, **except the two-hour duration (UI-01)**. Shelf file icons are generic because the synthetic paths do not exist.
- **Legitimate differences left in place:** the Audio page puts the mute control after its volume slider, where Music puts a speaker glyph before it. They are different controls (mute action versus decoration).

### 2. Animation inventory

"Rendered" means observed in offscreen frame sequences. "Source" means code review only.

| Animation | Before | Issue | Correction | Verification |
|---|---|---|---|---|
| 1–2 Collapsed ↔ expanded shell | Spring 0.40 / 0.80; black gate; content at 75% height | None in the reviewed frames. Shell overshoot is visible. The skill guidance would use damping 1.0 for tap and hover, but 0.80 is a documented product decision ([NOTCH_SHELL.md](NOTCH_SHELL.md), handoff §11). | None (constraint preserved) | Rendered: content revealed by about 105 ms, geometry settled by about 250 ms; close restores collapsed content at about 315 ms |
| Reversal mid-transition | Same spring retargeted from live geometry | None: close→open continues from the current shape with no jump | — | Rendered (`40-reverse-close`, `41-reverse-open`) |
| 3 Hover enter/exit | 120 ms enter / 600 ms grace | Not exercisable without input | — | Source + existing unit tests only |
| 4 Page switching | Header/Home clicks instant; trackpad swipe 0.2 s critically damped crossfade | The two input paths differ. Left as is: instant switching suits navigation used tens of times a day, and the swipe crossfade confirms a threshold gesture. Recommended as a product decision. | None | Source; click switch rendered as an instant cut |
| 5 Home → Music / Calendar | Instant selection | None | — | Rendered |
| 6–7 Track / artwork change | Old artwork kept until the new image loads, 0.18 s crossfade | None found in source; real artwork never loaded in fixtures (no network) | — | Source only |
| 8 Playback controls / progress | Press 0.97 / 0.16 s; progress timeline ≤10 Hz while visible | None | — | Rendered static states |
| 9 Volume HUD | Compact grow (0.36 / 0.86 in, 0.30 / 1.0 out), level spring | None: glyph and level grow out of the notch | — | Rendered (`50-volume-hud`) |
| 10 AirPods connect / restore | 0.8 s half turn on connect | **UI-03:** a restored waiting entry replayed the connect turn | Slot remembers introduced entries | Rendered before/after + unit test |
| Compact activity swap | Symmetric opacity crossfade, 0.22 s (Reduce Motion 0.12 s) | **UI-04:** two right-aligned rows overlapped as garbled text | Faster exit; Reduce Motion removes the old row | Rendered (Reduce Motion deterministic; see UI-04 for the normal-motion limit) |
| 11 Download / transfer | Progress glides via `compactLevel`; terminal state crossfades | None found | — | Source + existing terminal-ordering tests |
| 12 Screenshot / notifications | Notification in 0.26 / 1.0, out 0.20 / 1.0; content change 0.10 s | None in the reviewed frames | — | Rendered (Calendar reminder, Charging, dismiss) |
| 13 Clipboard / Shelf changes | Hover 0.12 s; copied feedback 0.18 s; notice 0.15 s | None found | — | Static renders + source |
| 14 Drag and drop | Drop affordance 1.03 scale (Reduce Motion none) | Not exercisable without input | — | Source only |
| 15 AirDrop / native dialogs | Native presentation | Not exercisable without input | — | Stage 27A native cycles remain the evidence |
| 16 Pomodoro | Phase 0.3 s, controls 0.2 s, history 0.24 s, numeric countdown | None found | — | Static render + source |
| 17 Mirror open / close | Downward mask reveal (`compactIn`); page fades and scales to 0.985 | **UI-05:** on close, Mirror text drew over the returning page | Opaque black backing + `zIndex(1)` | Rendered before/after |
| 18 Settings / utility presentations | Native window, popovers | Offscreen render shows non-key-window artifacts only | — | Not visually qualified |
| 19 Loading / empty / error | Camera status 0.25 s; empty states static | None found | — | Rendered Mirror starting / live; empty Local Audio Apps |
| 20 Simultaneous / interrupted | Activity arbitration; shell retarget | Covered by UI-03/04 and reversal | — | Rendered + existing stress tests |
| Reduce Motion (all) | 0.12 s ease-out geometry; opacity substitutes | Swap overlap (UI-04) | As UI-04 | Rendered Reduce Motion run |

### 3. Responsiveness and motion performance

| Measurement | Result |
|---|---|
| Input-to-feedback latency | **N/A**: no input injection was available |
| Frame pacing, dropped or late frames | **N/A**: no on-screen interaction to trace. Offscreen sampling does not pass through the compositor. Only 60 Hz hardware was available. |
| Main-thread stalls during animation | **N/A** (not traced this stage) |
| Transition timing (offscreen, 35 ms sampling) | Open: content at about 105 ms, settled by about 250 ms. Close: collapsed content restored at about 315 ms. Reduce Motion open: content at about 105 ms. |
| CPU while idle, collapsed (Debug fixture, quality fixture with a Calendar reminder) | 0.11 s CPU over 20 s, about **0.55% of one core**. Debug build, not a production benchmark. Stage 27A's coverage-free optimized mock idle was about 0.0001%. |
| CPU during animations | **N/A** |
| Memory / resource retention after animations | **N/A** for this stage. Stage 27A's 1,000-cycle model stress remains the only retention evidence. |

The corrections add no timer, display link or polling. UI-03 adds an 8-entry bounded array per compact slot. UI-05 adds one opaque fill inside an existing mask.

### 4. UI problems found and corrected

#### UI-01 — P2: long media durations read as minutes only

- Reproduction: a 7,265 s item showed `121:05` on Home and Music (Up Next used the same arithmetic).
- Cause: `MediaProgressView.time` always formatted `m:ss`.
- Change: `h:mm:ss` from one hour, matching Spotify and Apple Music; `UpNextView` reuses the formatter. Files: `MediaProgressView.swift`, `UpNextView.swift`.
- Verification: `testMediaTimesFromOneHourIncludeHours`. The rendered Home and Music pages now show `2:01:05`.

#### UI-02 — P3: Calendar column headings misaligned and mismatched

- Reproduction: with a meeting event, the left "● Calendar" label sat about 8 pt below "Up Next", in a different size and opacity.
- Cause: the main event column had an 8 pt vertical inset that the Up Next column lacked, and the calendar name used ad-hoc 10 pt / 0.6 styling.
- Change: matching 8 pt top inset; calendar name uses `ExpandedPageStyle.sectionTitle` / `secondary`. File: `CalendarActivityView.swift`.
- Verification: the rendered Calendar page shows both headings on one line with the same style. Without a meeting link the main event stays vertically centred by design.

#### UI-03 — P3: restored device activity replayed its connect animation

- Reproduction: AirPods connect (the turn finishes in 0.8 s); a battery activity preempts; it is dismissed and the AirPods entry is restored. Before the fix, the glyph was mid-turn in every frame from 0 to 245 ms, about 2 s after the actual connection.
- Cause: the slot re-inserts a restored entry under `.id`, so `NotchDeviceTurnGlyph` started a fresh turn from new `@State`.
- Change: `NotchCompactActivitySlot` remembers the last 8 introduced entry IDs, and a restored entry starts at rest. A reconnect of a live entry still turns through the existing `onChange(TurnKey)` path (source-verified, not rendered). Files: `NotchCompactActivityView.swift`.
- Verification: restored frames are at rest from the first frame; `testRestoredCompactEntryIsNotIntroducedAgain`. An earlier top-left glyph position seen mid-turn is a capture artifact: settled frames show it centred.

#### UI-04 — P3: compact activity swap overlapped two rows

- Reproduction: Charging ↔ AirPods or On Battery ↔ AirPods. With Reduce Motion it reproduces every time: frames showed `82%67%`, `40%55%` and a headphone glyph over "Charging". Under normal motion it was observed once (`82%67%`). Staged normal-motion runs did not reproduce it, because a swap that also changes shell width runs while `NotchSurfaceFrame` disables content transactions (an instant cut).
- Cause: a symmetric opacity crossfade of two right-aligned rows of different widths in one slot.
- Change: the outgoing row exits in 0.1 s while the incoming row keeps its 0.22 s entrance. With Reduce Motion the outgoing row is removed immediately and the new row fades in over 120 ms. Files: `NotchCompactActivityView.swift`, `NotchCompactActivity.swift` (`NotchMotion.compactSwapExit`).
- Verification: Reduce Motion frames show no overlap. Under normal motion, outgoing content cleared by about 105 ms (previously about 175 ms) with no ghost under the incoming banner. The exact normal-motion overlap frame could not be re-staged, so that path is evidenced only as reduced exposure.

#### UI-05 — P2: Mirror close drew its text over the returning page

- Reproduction: open Mirror, then close it. For about 3 frames (about 70–140 ms) "Mirror / FaceTime HD Camera / Mirrored" overlapped "October 2026 / 17" and the media title.
- Cause: the preview has a transparent background, and as a removed `ZStack` child it lost its order, so the fading-in page drew through it.
- Change: black backing (the shell's own colour) and an explicit `zIndex(1)`, so the retracting mask wipes over the page. File: `Pages/NotchPagesView.swift`.
- Verification: rendered close frames show a clean upward wipe. The first attempt (backing only) did not fix it; the `zIndex` was the decisive change.

#### UI-06 — P3: press feedback differed between equivalent controls

- Reproduction: source comparison. Header, page and media controls press to 0.97 with a 0.16 s smooth animation. Shelf/Clipboard toolbar buttons pressed to 0.93 over 0.08 s. Join pressed to 0.96 and was the only control that grew (1.03) on hover.
- Change: the toolbar and Join styles adopt the authored 0.97 / 0.16 s convention (Reduce Motion: no scale, 0.1 s). Join's hover is fill-only. Files: `NotchToolbar.swift`, `CalendarJoinButtonStyle.swift`.
- Verification: build and suite only. Pressed and hover states need pointer input, which was unavailable, so **no rendered evidence is claimed**.

#### Observed but not changed

| Observation | Reason |
|---|---|
| Header utilities absent in offscreen frames while Mirror is open | Glass rendering under `cacheDisplay` is suspected; no source path hides them. Needs a native check. |
| Mirror opening showed no intermediate reveal frames at 35 ms sampling | May be a sampling or offscreen artifact; needs a native recording. |
| Settings renders: black sidebar selection, dimmed rows | Offscreen non-key-window artifacts, and several models were deliberately passed as `nil`. No conclusion drawn. |
| Main shell damping 0.80 versus the skill guidance of 1.0 for tap-driven motion | Documented product decision; reported, not overridden. |

### 5. Accessibility results

| Check | Executed | Result |
|---|---|---|
| Reduce Motion | Offscreen run with the shell override | Shell uses 0.12 s ease-out geometry; compact swaps and Mirror use opacity substitutes. The swap overlap was found and corrected here (UI-04). |
| Reduce Transparency / Increase Contrast | Existing `Stage23RenderingTests` pass in the suite | No new native check |
| Light / dark | Settings rendered in both (artifacts noted). The notch is always dark by design. | Partial |
| VoiceOver labels / order | **Not executed natively.** Source labels unchanged by this stage. | Unverified |
| Keyboard navigation / focus visibility | **Not executed** (no input) | Unverified. The focus ring after a mouse click on Caffeine (the existing UI test expects click-then-Space) needs a native look. |
| Scaling, resolutions, Spaces, multiple displays, menu-bar fallback | Not executed | Unverified |

### 6. Skills and references used

| Skill (source) | Invoked or consulted | Phase | What it informed |
|---|---|---|---|
| `apple-design` (`~/.codex/skills`, Emil Kowalski–derived) | SKILL.md read in full | 6.2–6.3 | Spatial consistency (Mirror wipe symmetry, UI-05), interruptibility check of reversal frames, Reduce Motion as substitution (UI-04) |
| `emil-design-eng` (`~/.agents/skills`) | SKILL.md read in full | 6.2–6.4 | Asymmetric enter/exit (UI-04), crossfade-of-two-objects diagnosis, 0.95–0.98 press-scale rule (UI-06), frequency-based decision on page switching |
| `apple-motion-feel` (`~/.agents/skills`) | SKILL.md read; its `grep` checks used for the inventory | 6.3 | "Adopt the deliberately authored value" (UI-06); one animation context per property; damping-by-trigger finding on the shell spring (reported, not changed) |
| `swiftui-expert-skill` (repo `.agents/skills`, AvdLee) | SKILL.md and checklist read | 6.1–6.4 | `.animation(_:value:)` and transition placement review; ZStack transition-order diagnosis (UI-05); state ownership of the introduced-entry memory (UI-03) |
| `review-animations`, `improve-animations`, `animation-performance`, `break-ui`, `write-swift` (github.com/emilkowalski/skills) | **Not installed.** SKILL.md fetched read-only from GitHub and consulted; nothing was installed or executed. | 6.3, 6.6 | Standards checklist and fix priority (delete → reduce → easing → interruptibility); `break-ui` worst-case catalogue for the fixture data; `animation-performance` "verify on device, not by feel" (frame pacing therefore reported N/A); `write-swift` for keeping the fix synchronous and value-typed |
| `anthropic-skills:computer-use` | Invoked | 6.1, 6.7 | Its tools were not available in this session, so native interaction was not possible |
| `macos-patterns`, `liquid-glass`, `instruments-profiling` (repo) | Listed, not applied | — | No glass was added; no Instruments trace was recordable without on-screen interaction |
| Apple HIG, WWDC23 *Animate with springs* | Referenced through the skills above | 6.2–6.3 | No new framework API adopted |

### 7. UI quality verdict

**CONDITIONAL.** No known major clipping, layout or stuck-state defect remains in the rendered surfaces, and the six confirmed defects are corrected. Conditions:

1. On a Mac where input automation is permitted, run the native hover, click, keyboard and VoiceOver passes, including the Caffeine focus ring after a mouse click.
2. Confirm UI-06 pressed and hover states and the Mirror open reveal on screen.
3. Record an Instruments trace (Animation Hitches / SwiftUI) of expand, collapse, page switch and compact activities on the release build. Frame pacing and latency remain N/A until then.
4. Confirm UI-04 under normal motion with real providers.
5. Run the Reduce Transparency, Increase Contrast, scaling and multi-display matrix natively.

## Changes in this stage

- Source: `MediaProgressView.swift`, `UpNextView.swift`, `CalendarActivityView.swift`, `CalendarJoinButtonStyle.swift`, `NotchToolbar.swift`, `NotchCompactActivity.swift`, `NotchCompactActivityView.swift`, `Pages/NotchPagesView.swift`.
- Tests: `Stage27A1UIQualityTests.swift` (2 cases); `Stage27A1VisualCaptureTests.swift` (opt-in harness, skipped by default).
- Docs: this report; handoff timing table; `FINAL_BUTTON_AUDIT.md`; `STAGE16_19_UTILITIES.md` (Mirror).
- No dependency, service, timer, design token family, distribution setting or shell geometry was changed. The main shell spring and black-content choreography are untouched.

## Final verification

After the last source edit (comment-only): 19 targeted tests (`Stage27A1UIQualityTests`, `NotchTransitionSurfaceTests`, `ExpandedPageCompositionTests`, `Stage23RenderingTests`, `CalendarSelectionTests`) passed; the Debug and Release workspace builds succeeded; `git diff --check` was clean. The complete suite above ran before that comment-only edit, with all functional changes in place. The fixture app processes started by this stage were each verified by their fixture arguments before being stopped; none remain. The native XCUITest plan was not re-attempted: Stage 27A's runner bootstrap failure is unresolved.


## Codex continuation — October 17, 2026

This continuation followed the supplied Claude handoff rather than restarting Stage 27A. Baseline remains `main` / `7ef5522d287fe5c6d498dd5251958d49cbf566db`. An initial private manifest captured **44 modified/untracked files** and the complete tracked diff. All prior fixes were preserved. Concurrent user activity and additional media layout/test/document edits were observed; the user confirmed other activity. The candidate hashes in the sanitized results identify the source actually validated. No reset, cleanup of user changes, commit, tag, push, production DMG, publication or Stage 27B work occurred.

New receipts: [sanitized counters, trace summaries, cadence and preservation results](STAGE27A1_CONTINUATION_RESULTS.json) and [automated test ledger](STAGE27A1_AUTOMATED_RESULTS.tsv). Raw traces, exports, process samples, private preference snapshots and images are **not** repository artifacts.

### A. On-screen QA and evidence provenance

The supplied handoff reports subsequent on-screen work that had not reached the original report above. Claude used a disposable **Notchium QA**, bundle **`com.marcusyu.notchium.qa`**, copied from an optimized, coverage-free Release build with DEBUG mock fixtures. Its separate non-LSUIElement bundle allowed computer-use targeting of the menu-bar agent without replacing the installed app. Mock services and controlled data do not establish original-identity permissions, live integration behavior or shipped free-profile capability behavior.

Reported native interactions included hover expansion; approximately 600 ms exit collapse; Space/focus collapse; rapid page changes and expand/collapse; closing reversals; native Add to Shelf open/cancel; Calendar/Media layout; Mirror close frame sequences; and pressed/hovered Join and Shelf controls. Calculator served as a harmless frontmost app. Instant navigation clicks, swipe crossfades and the authored 0.40/0.80 shell spring were preserved.

| Correction | Subsequent Claude handoff evidence | Fresh Codex evidence / remaining limit |
|---|---|---|
| UI-01 hours in media duration | Automated and on-screen | Formatter regression passes; long-item offscreen renders regenerated. New interactive fixture used a 3:45 item. |
| UI-02 Calendar heading alignment | On-screen | Full-suite layout checks and regenerated offscreen Calendar; no new native alignment measurement. |
| UI-03 restored AirPods starts at rest | Offscreen; exact native restoration not reproduced | Restoration regression passes; regenerated normal-motion first restore frame shows the resting glyph. Native fixture exposed the AirPods label, but computer-use capture did not supply reliable compact pixels. **Native restoration remains unqualified.** |
| UI-04 no overlapping compact text | Offscreen, deterministic with Reduce Motion; native reproduction incomplete | Normal and Reduce Motion frame sequences regenerated and inspected, including the incoming 82% state. **Native normal-motion/Reduce Motion reproduction remains incomplete.** |
| UI-05 clean Mirror close wipe | On-screen high-frequency sampling | Regenerated Mirror sequence and executed native rendered fixture cycles; no new pointer/frame-by-frame native overlap pass. |
| UI-06 consistent Join/Shelf + press feedback | On-screen pixel measurements, approximately 0.97; Join hover no longer grows | Styles preserved, builds/regressions pass. No fresh pressed-state pixel measurement. |

Claude's handoff reports that its preference backup matched, all **24** then-captured Application Support files matched their hashes, the QA app was removed, and temporary diagnostics were removed. These are historical preservation claims, not this continuation's results.

Codex used six separately identified disposable QA bundles under a private temporary directory, with identities prefixed `com.marcusyu.notchium.codex27a1`. A compiled launcher always supplied `--ui-testing`, Stage 11 and quality fixtures, and mock display arguments, including on ordinary relaunch. Initial computer-use checks rendered expanded Home/Music and playback controls. Extra QA identities were subsequently denied by the computer-use tool. No OS Accessibility, VoiceOver, privacy or global appearance setting was changed to overcome that restriction. Programmatic fixture transitions below are distinguished from pointer input.

**Isolation incident and recovery:** `xctrace --launch` resolved a disposable wrapper to **two newly started installed-app processes**, dropping the guard's fixture arguments. Both were stopped after their exact paths, start times and arguments identified them. That trace was excluded and deleted; subsequent recording attached to a verified QA PID whose executable path, fixture arguments and runtime bundle identity matched. The launch incident changed the production cached-track entry and reserialized Shelf metadata. Shelf JSON content remained identical, with one reference before and after. With the user's **explicit approval**, only the cached-track entry was restored from the private pre-incident snapshot. Disk readback verified the restore and **zero changes to other preference keys during restoration**. No production preference-domain reset/import was performed.

All **25 captured Application Support files** still matched their original hashes at final cleanup. The production preference file was not an immutable baseline because the user confirmed other activity; a byte-identical whole-preferences claim would be false. All six disposable QA apps and their unique QA preference domains were removed. No personal Clipboard history, key, Keychain item, document, event or reminder was deliberately altered. The incident prevents a blanket claim that every interval was fully isolated; the exact narrower preservation results are retained.

### B. Media progress correction: correctness and CPU evidence

The inherited change replaces `.animation(minimumInterval: 0.1, paused: ...)` with `MediaProgressSchedule`: dates are 100 ms apart, and a paused schedule yields its initial date then ends. The view pauses that schedule when playback is paused, its page/shell is hidden, or seeking is active. SwiftUI owns the schedule; no independent timer/task is installed by the view. This bounds timeline content evaluation without moving provider logic into presentation.

The handoff attributes excessive refresh work to the animation schedule and reports **19.6% → 6.5% of one core**, approximately **67% less CPU**, in its optimized mock fixture. Those figures remain explicitly **Claude-reported**, not a new production benchmark. The exact earlier workload and CPU windows were not reconstructed, and the new comparison did not reproduce that magnitude.

A temporary log probe in the timeline closure of an optimized disposable copy measured four-second steady windows, excluding setup and transition activity:

| State | Visible callbacks / 4 s | Hidden callbacks / 4 s | Result |
|---|---:|---:|---|
| Music visible, playing | 40 | 0 | **10 Hz**, median interval 100.012 ms; observed intervals 98.623–101.139 ms |
| Paused | 0 | 0 | No periodic evaluation in the steady window |
| Playing on hidden Music/Home, Calendar visible | 0 | 0 | No periodic evaluation in the steady window |
| Playing after 100 page round trips | 40 | 0 | **10 Hz**, median 99.980 ms; no accumulated cadence |
| Paused again after the sequence | 0 | 0 | No stale periodic evaluation |

The probe existed only in disposable source and was excluded from CPU measurement binaries. A state transition can legitimately render once; these results do not claim that parent-driven invalidations can never evaluate a paused view. Apple also permits system throttling of [TimelineView](https://developer.apple.com/documentation/swiftui/timelineview), so this is observed cadence, not a real-time delivery guarantee.

The inherited schedule test passes. The **26-test targeted run** also covers elapsed interpolation, pause/resume rebasing, seek state, buffered confirmations, failure/release behavior, visibility ownership and hosted native pointer dragging. Existing paused-seek tests prove that seeking sends no Play command and remains paused. Live Spotify and subjective smoothness with actual artwork/audio taps remain unqualified. The schedule was preserved; it was not rewritten for style.

The matched new CPU pair used the **original SwiftUI.App entry**, the same guarded quality services, fixed expanded Music state held by a QA-only presentation lease, `Release -O`, coverage disabled, and sequential approximately 20-second windows with no concurrent build/test/trace. Only the schedule was reverted in the before source; both variants retained the other inherited changes.

| New original-app fixture metric | Before: animation schedule | After: periodic schedule |
|---|---:|---:|
| Window | 20.069 s | 20.017 s |
| CPU, percent of one core | **0.4854%** | **0.4975%** |
| End physical footprint | 54.142 MiB | 54.532 MiB |
| Peak sampled RSS | 132.281 MiB | 137.594 MiB |
| Interrupt wakeups/s | 60.391 | 60.597 |

**No meaningful CPU improvement was reproduced in this pair.** One window per variant and different fixtures from Claude do not support a speedup, slowdown or general production percentage. Ten timeline evaluations per second also does not imply ten process wakeups per second. The 19.6%/6.5% receipt must not be combined with these numbers as one controlled experiment.

A separate custom `NSApplication` harness over the same optimized modules measured playing **0.5283%**, paused **0.0007%**, hidden playing **0.0085%**, and playing after 100 page round trips **0.5345%**. Its collapsed windows measured approximately **0.0001% / 46.251 MiB** initially and **0.00005% / 50.251 MiB** afterward. The warmed footprint difference is not leak attribution. Its own schedule pair was 0.5051%/0.4859%. This different entry point is diagnostic evidence of bounded work and no obvious accumulation, not production qualification or confirmation of Claude's reduction.

### C. Instruments and remaining delays

Fresh host verification: Apple M4 / `Mac16,12`, 10 cores, 16 GiB; macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4 compiler / Swift 6 language mode. The only display was 1470 × 956 pt, maximum **60 Hz**. Minimum deployment remains macOS 26. The correct fixture executable, mock arguments, bundle identity and lack of coverage instrumentation were checked. A production Release build was separately built and checked for absence of fixture/LLVM coverage markers; it was not launched for benchmarking.

| Trace | Hitches | Total / worst hitch | Main-thread delay rows | Interpretation |
|---|---:|---|---|---|
| Claude pre-fix, from handoff | 17 | 533 / 66.7 ms | 11, about 42–66 ms; no reported hang risks | Approximately seven seconds of clicking in a longer recording; collapsed idle about 0.3% / 47 MB. Historical. |
| Codex post-fix original-app QA, Animation Hitches **plus Time Profiler**, attached PID | **13** | **1,999.983 / 1,033.326 ms** | **4**: 33.255, 521.749, 1,062.701 and 269.071 ms; classified as one potential delay, two hangs, one microhang | 20.859 s recording; programmatic page/shell/Mirror sequence. Capture began partway through the first cycle: 19 page selections, three shell opens and four Mirror/close cycles were in range. **Not matched to the earlier clicks.** |
| Exploratory custom-NSApplication SwiftUI trace | 940 | 15,982.714 / 199.992 ms | 0 potential-hang rows | Different harness and heavily instrumented SwiftUI graph; retained as diagnostic evidence, not discarded or presented as a before/after result. |

The 33 ms event correlated with Mirror creation and showed main-thread SwiftUI/AttributeGraph/AppKit layout work, including native scroller setup. The three longer native delay windows contained only **25, 40 and 7 ms of sampled main-thread running time**, respectively. Running-only Time Profiler samples cannot identify the missing blocked/unscheduled stack. The sparse samples do **not** justify declaring a CPU-bound app function responsible for the full interval.

The longer intervals coincided with fixture page changes: Audio → Shelf, Music → Calendar and Focus Timer → Audio. The scripted scenario took **11.704 s under Instruments**, versus **10.005 s** in one repeat without Instruments (observed with the separate `sample` tool at 1 ms). In the latter run, phase gaps were close to their scheduled 250/400/500 ms waits, and the dominant main-thread stack was the ordinary AppKit/CoreFoundation event wait; the one-second page gap did not recur. This suggests instrumentation/harness sensitivity. It does **not** prove absence of real click stalls, diagnose every late frame, or establish a production root cause. No speculative source change, arbitrary delay, animation disablement or broad refactor was made.

The helper's exploratory SwiftUI correlation percentages assumed 1 ms sampling although that trace used 0.1 ms sample weights. Those percentages were not accepted; native running-time summaries use the actual exported weights. Raw nanosecond hitch durations, rather than rounded display strings, supply the totals above.

A matched native pointer workload, blocked-stack/scheduling attribution and production-service matrix remain required. The progress change is **not** claimed to have resolved Claude's per-click stalls. Real Spotify playing/paused, artwork, local waveform/audio taps, continuous Clipboard capture, populated Calendar, Pomodoro, actual camera open/close, mixer and combined live workloads were not benchmarked. No live-account or personal-data scenario was substituted for missing QA permissions.

**Leaks:** the ordinary QA probe was restricted and reported **417 allocations / 19,952 bytes**. A separate disposable QA signature with `get-task-allow` enabled readable inspection without changing production signing or OS settings; that instrumented diagnostic process reported **4,298 / 204,336 bytes**. Its graph was dominated by framework/Metal/AppIntents structures, with no app-owned allocation stack established and no allocation-stack logging. Counts from these different processes/conditions are not a before/after experiment. Neither is accepted as a confirmed application leak or a clean production leak result. Production allocation ownership remains unverified.

### D. Native UI and accessibility limits

- **UI runner:** a disposable project used distinct app/test bundle IDs and ad-hoc test signing. The runner executed its startup but **zero UI test cases ran**: `Timed out while enabling automation mode.` The system log states **`Writer daemon requires authentication to enable automation mode.`** This is an OS automation authorization gate, not evidence of a failing Caffeine/Escape assertion. No authentication, TCC reset, security reduction or production signing change was attempted. A human must complete the supported OS/Xcode authorization flow before a new runner receipt can exist.
- **Keyboard:** the earlier handoff's Tab delivery and Escape interception remain the only input-tool evidence. The new intended keyboard/Escape XCUITest was blocked by initialization. Exact Escape dismissal, complete focus order, keyboard activation and native focus-ring quality remain unqualified.
- **VoiceOver:** speech, labels and ordering were not executed with VoiceOver; global accessibility settings were left alone. Source accessibility labels and test assertions are narrower evidence.
- **Reduced effects:** fresh normal/Reduce Motion offscreen runs passed; they do not qualify native reduced-motion/transparency/contrast settings or compositor behavior. No native contrast measurement was added.
- **Native presentation:** earlier handoff and Stage 27A picker/AirDrop cancellation receipts remain valid in their stated mock scope. No fresh recipient transfer, hardware, multi-display/Spaces or real camera/permission pass is claimed.
- **UI-03/UI-04:** offscreen reproduction and regression evidence were renewed; exact native restoration/replacement is still incomplete. Extra QA-app computer-use authorization was denied, and no bypass was attempted.

### E. Regression, correction and source/asset provenance

The first fresh complete package run executed **737 main cases with six skips**, but one artwork case failed two assertions. An isolated rerun reproduced it. A direct ImageIO/AppKit probe showed a **320 × 160 CGImage**, logical NSImage size 320 × 160, and a Retina `NSCGImageSnapshotRep` reporting 640 × 320 backing pixels. The test measured the representation rather than the decoded image.

The only Codex code correction is in `MediaArtworkTests.swift`: it obtains the [CGImage](https://developer.apple.com/documentation/appkit/nsimage/cgimage(forproposedrect:context:hints:)) and retains the **320 × 160** size/aspect assertions. No assertion was removed or loosened; no production cache, layout, timer or service was changed. Inherited source fixes and user-authored changes were preserved.

| Fresh final check | Result |
|---|---|
| Targeted media/artwork/progress/visibility/UI-quality | **26 passed** |
| Complete package XCTest, main | **737 executed, six skipped, zero failures** |
| Complete package proactive XCTest | **38 passed** |
| Complete package Swift Testing | **5 passed** |
| Xcode unit/integration target on isolated project copy | **737 executed, six skipped, zero failures**; **5 Swift Testing passed** |
| Opt-in normal offscreen capture | **2 passed**, 120 PNGs |
| Opt-in Reduce Motion capture | **1 passed**, 98 PNGs |
| Native UI test cases | **0**; one runner-initialization error, as above |
| Current-source Debug build and static analysis | **BUILD SUCCEEDED / ANALYZE SUCCEEDED** |
| Current-source coverage-free Release build | **BUILD SUCCEEDED**, arm64/x86_64; fixture/profile markers absent |
| `git diff --check` | Clean |

The six default skips remain four opt-in hardware cases and two opt-in capture cases; the capture cases were separately executed above. No test was newly skipped to pass. Existing warnings remain: `FocusService.swift:61` suggests an asynchronous alternative; AppIntents metadata extraction is skipped without that framework; rendering tests can report FocusState access outside a View body. No new sanitizer claim is made for a test-only correction; Stage 27A's ASan/UBSan and targeted TSan receipts remain historical. No linter is configured.

Current local Spotify control entered history in **`f903e7d`** (October 15, “Control local Spotify through stateless scripts”). The bundled logo entered in **`7883365`** (October 7, “Bundle official Spotify logo image”). These identify introduction points, not independent authorship or an asset grant. Contrary to a broad reading of Stage 27A's search note, repository documentation **does** cite BoringNotch as a motion/Shelf/system-feedback reference and asserts independent implementation. Those assertions, absence of GPL headers and similar use of Apple APIs are not sufficient provenance proof.

The upstream [Boring Notch repository](https://github.com/TheBoredTeam/boring.notch) declares GPL-3.0. [Spotify's branding guidance](https://developer.spotify.com/documentation/design) supplies usage requirements, and [its terms](https://developer.spotify.com/terms) do not make the logo part of Notchium's MIT license. Obtain author/source-generation records or a defensible independent-implementation record, plus the original asset URL/checksum, applicable permission and usage review. No copying allegation, relicensing decision or MIT-only compliance certification is made. No third-party code, dependency, scanner or remote script was installed or executed.

Applied installed skills: Instruments profiling, SwiftUI expert (including trace/latest-API references), Apple device validation, Xcode workflow, and Context7 documentation lookup. XcodeBuildMCP callable tools were absent, so installed Xcode/Swift CLI tools were used. Current Apple TimelineSchedule/TimelineView and NSImage documentation was fetched through Context7. No motion redesign or new glass treatment was introduced.

### F. Final engineering decision

| Area | Verdict | Reason |
|---|---|---|
| UI / visual quality | **CONDITIONAL** | Six original corrections preserved; rendered regressions renewed; native restoration, contrast/scaling and complete accessibility remain incomplete. |
| Animation / interaction | **CONDITIONAL** | Lifecycle/cancellation regressions pass; historical native checks retained; fresh pointer/frame-pacing and Escape/VoiceOver gates remain open. |
| Performance | **NO-GO** | 10 Hz and lifecycle behavior verified, but the reported CPU reduction was not reproduced; instrument-sensitive delays, blocked-stack attribution, live-service energy/memory and leak qualification remain unresolved. |
| Security / licensing | **NO-GO for qualification** | Earlier security evidence is retained with its limits; source and asset provenance remain unproven. The launch isolation incident and authorized narrow recovery are documented. |
| Regression | **GO for executed scope** | Main/proactive/Swift Testing/Xcode regressions, builds, analysis and whitespace checks pass after the display-scale test repair. Native UI runner/hardware skips are explicitly excluded. |
| Overall Stage 27A.1 / entry to Stage 27B | **NO-GO** | Required native automation authorization, hardware/system permission matrix, native accessibility, production performance/leak attribution and provenance evidence are still missing. |

No unresolved app-owned P0/P1 defect was established by this continuation, and a successful automated suite is not a release qualification. Next work is the supported OS/Xcode automation authorization, then matched native pointer profiling with blocked-stack attribution and the live integration matrix; establish source/asset provenance before distribution. Stage 27B, Stage 27C and publication remain unstarted.


## Stage 27A.2 superseding verification — October 17, 2026

See [Stage 27A.2 final verification](STAGE27A2_FINAL_VERIFICATION.md) for the latest runner, production-performance, memory, integration, provenance and release-gate conclusions. It fixes a sampled startup DNS stall and adds two locality regressions; the final native run passes 24/24 cases and all four distinct opt-in audio hardware cases now have passing receipts. Full package/Xcode regressions, sanitizers, builds and analysis pass with exact counts in the new report. The gate remains **NO-GO for completed engineering qualification / Stage 27B** because material Spotify provenance/usage questions and named performance, native-transition and hardware/service conditions remain unresolved. Earlier offscreen evidence is preserved and is not upgraded to native acceptance. The personal-data baseline spans owner-confirmed original-app use; the fresh final nine-file checkpoint matches, with no reset or restoration performed.
