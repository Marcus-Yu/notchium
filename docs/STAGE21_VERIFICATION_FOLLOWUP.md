# Stage 21 verification follow-up — 2026-10-03

Verification of the current uncommitted Stage 21/22 checkout. No production code, tests, user files, or Git history were changed during this follow-up. The original display resolution and Xcode desktop window were restored. No files were sent through Share or AirDrop.

## Automated checks

| Check | Result | Evidence |
|---|---|---|
| Complete host-access Swift package suite | **624 passed, 0 failed**, 61.7 seconds | `/tmp/notchium-stage21-followup-tests.log` |
| Debug workspace build | **Passed** | `/tmp/notchium-stage21-followup-debug.log` |
| Release workspace build | **Passed** | `/tmp/notchium-stage21-followup-release.log` |
| Whitespace validation | **Passed** | `git diff --check` |

Workspace: `Notchium.xcworkspace`; scheme: `Notchium`; destination: My Mac. Builds used `CODE_SIGNING_ALLOWED=NO`. The package suite used the existing Stage 21 scratch path, module caches and `--disable-sandbox`, with host access for native integration tests. Xcode also rebuilt and launched the current source; its app process was PID 24212. All 16 Stage 21 tests passed. The previously intermittent mixer assertions passed in this run; they were not changed or proven fixed. No separate lint configuration was found.

## Manual/native matrix

The user confirmed that only the built-in display was available. “User-assisted” means the user performed the physical/foreground action and supplied the result; it is not an independently captured visual trace.

| Requested check | Result | Evidence or limit |
|---|---|---|
| 1. MacBook display only | Passed for inspected states | Native collapsed/expanded screenshots and AX state; physical-notch geometry and one `notchium.shell.panel` identifier |
| 2. MacBook + external monitor | Unavailable | No external display connected/available |
| 3. Interact on external display | Unavailable | Requires external display |
| 4. Interact on built-in display | Passed | Native expansion and direct Shelf page selection |
| 5. Disconnect active monitor | Unavailable | Requires external display |
| 6. Reconnect monitor | Unavailable | Requires external display |
| 7. Close/open lid with external display | Unavailable | Requires external display; built-in-only lid closure is not the clamshell case |
| 8. Enter/leave standard-app fullscreen | Partial; classification unresolved | Xcode's menu confirmed Exit Full Screen, then Enter Full Screen after restoration. Its editor was off-screen to automation. User confirmed active fullscreen Safari; see classification finding below |
| 9. Fullscreen video | User-assisted pass | User reported that the fullscreen video/HUD/Space checks worked fine. No independent video-state capture |
| 10. Presentation app | Not run | No presentation app was exercised |
| 11. Volume/brightness HUD in fullscreen | User-assisted pass | Included in the user's “it works fine” response. Native automation rejected `XF86AudioRaiseVolume` as an unsupported key. The app still has no production brightness HUD provider |
| 12. Calendar alert in fullscreen | Not run natively | Existing automated eligibility/ranking tests passed; no real or developer-fixture alert was triggered during active fullscreen |
| 13. Download completion in fullscreen | Not run natively | Existing automated transfer/policy tests passed; no completion was triggered during active fullscreen |
| 14. Share/AirDrop while fullscreen | Desktop paths checked; fullscreen variant unverified | Share popover rendered in front and was cancelled. AirDrop dialog was cancelled without selecting a recipient. One cancellation collapsed Shelf; a repeat at original scale returned to expanded Shelf. Active fullscreen affinity was not certified |
| 15. Finder drag with multiple displays | Unavailable | Requires multiple displays; no native Finder drag was performed |
| 16. Sleep/wake | User-assisted, partial native verification | User performed sleep/wake/unlock and replied “awake.” Afterwards native inspection showed the collapsed shell, original geometry and resting level. A fresh sleep-to-normal diagnostic sequence was not captured; subsequent UI inspection failed in the provider |
| 17. Resolution/scaling change | Passed | Changed 1470×956 → 1280×832 → 1470×956 through System Settings; live app geometry changed accordingly and restored |
| 18. Repeated Space changes | User-assisted pass | Included in the user's reported successful checks; pinned-page continuity across every transition was not independently traced |

## Native geometry and findings

At the original scale, the live screen was `(0, 0, 1470, 956)`, safe top 32, and panel `(365, 634, 740, 322)`. At 1280×832, safe top became 28 and the same-sized panel moved to `(270, 510, 740, 322)`. The top edges match each screen's top. Returning to the default restored the original frame. Inspected shell screenshots showed no clipping or duplicate visible shell. Still images do not certify animation seams or absence of transient flashes.

**Fullscreen classification remains unresolved.** While the user confirmed fullscreen Safari, the running app's redacted diagnostics continued to report `fullscreen=false`, with no `fullscreenApp` transition. A separate read-only public-AppKit diagnostic observed frontmost bundle `com.apple.Safari`, presentation options raw value 0, and `fullscreen=false`; see `/tmp/notchium-stage21-followup-environment.log`. It read PID/layer/bounds, not window titles or file contents. These observations do not validate context-specific quieting during real fullscreen. They identify a gap between the intended classifier and the observed public evidence on this host (macOS 27.0.1). Root cause is not established; synthetic option tests cannot settle it. The conservative normal fallback can preserve visible feedback while leaving routine-notice quieting unverified.

**AirDrop return was intermittent in this session.** The first inspected cancellation settled to collapsed Shelf. The repeat at the restored scale settled to expanded Shelf with Shelf selected. Both used native Cancel, and neither sent files. Event ordering/pointer-boundary effects were not traced, so this is an observation requiring follow-up, not a proven code root cause.

Native automation could inspect and interact with several windows but could not certify Xcode's fullscreen Space (`cannotClickOffscreenElement`). Safari inspection later failed with ScreenCaptureKit errors -3811 and -3812, and post-wake inspection eventually also failed with -3812. These are tool limitations, not app-crash evidence. User-assisted observations are retained separately above.

## Performance sanity

A 15-second sample of the running process reported 10 idle wakeups, 142 interrupt wakeups, 0.0750 CPU seconds and 62.84 MiB footprint (`/tmp/notchium-stage21-followup-idle.log`). Playback and manual checks were active, so this is not comparable to the earlier idle samples and does not establish a regression or improvement. The passing burst/lifecycle tests and source inspection still verify coalesced event handling and no continuous topology/fullscreen polling in the Stage 21 implementation.

## Acceptance status

Automated checks are green. Native/manual acceptance is **partial**, with the exact unavailable and unexecuted checks listed above. The next engineering investigation should establish the live fullscreen evidence/classification behavior before claiming context-specific activity quieting is verified. Also repeat AirDrop cancellation with an event trace. Multi-display hardware coverage, presentation-app coverage, and fullscreen Calendar/download completion remain open.
