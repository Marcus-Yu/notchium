# Stage 23 — product quality, accessibility and privacy

Audit date: October 4, 2026. Starting revision: `5972b14`. The initial audit was read-only across all user-facing surfaces before selecting changes. Stage 24 is out of scope. Implementation and automated verification are recorded below; native release sign-off remains pending the explicitly listed checks.

## Prioritized findings, recorded before implementation

P0 means a functional, accessibility or security defect; P1 an obvious product-quality issue; P2 a meaningful consistency improvement; P3 a subjective adjustment. Findings below are source-confirmed unless native evidence is specified. No P3 visual redesign is planned.

| ID / priority | Surface / files | Category and evidence | Root cause / correction | Regression risk |
| --- | --- | --- | --- | --- |
| Q1 / P0 | Panel; `NotchPanel`, `NotchiumPanelController` | Keyboard: `canBecomeKey` is always false. Native baseline Tab cannot traverse the expanded panel. | Permit deliberate expanded keyboard focus while preserving passive collapsed/hover behavior; native focus tests. | Medium: activation, auxiliary windows and outside dismissal. |
| Q2 / P0 | Shell/pages; `NotchiumShellView`, `NotchPagesView` | Native baseline AX tree on Home exposes hidden Music, Calendar, Audio and Shelf descendants; collapsed AX tree still exposes disabled expanded controls. | Retained page hierarchy does not establish effective AX isolation; hide inaccessible descendants at a real presentation boundary without alternate model truth. | Medium: retained view/session ownership and focus. |
| Q3 / P0 | Clipboard; `ClipboardStore` | Index, text, URLs, file paths, fingerprints, thumbnails and PNG assets are plaintext on disk. | Encrypt index/assets with CryptoKit and a local Keychain key, preserve serial utility queue; non-destructive migration and failure handling. | High: migration, locked/corrupt data and cleanup order. |
| Q4 / P0 | Clipboard; model, settings and production wiring | Automatic capture starts at launch; no explicit capture opt-in despite permission contract. | Persist an explicit default-off capture choice; cancel owned work on disable and preserve usable history. | Medium: fixture behavior, stale images and relaunch. |
| Q5 / P0 | Media; `MediaViews` | Shuffle/repeat have action names but no spoken setting value/state. | Add values/selected semantics without changing commands. | Low. |
| Q6 / P0 | Pomodoro; `PomodoroEngine`, `PomodoroModel` | Decoded settings can contain zero/negative cadence or extreme minutes; unchecked closed range and integer multiplication can trap. | Validate configuration at the authoritative value boundary using established settings ranges; focused hostile-persistence tests. | Medium: existing supported timer fixtures and settings. |
| Q7 / P1 | Mirror; `CameraPreviewPanel` | `devices.prefix(4)` makes fifth and later cameras unreachable. | A bounded scrolling native choice list with stable device identity. | Low: presentation only; capture owner retained. |
| Q8 / P1 | Calendar/Home/Media; page visibility and timelines | Retained Calendar ticks after collapse; both progress copies tick while other pages are shown; Home calendar schedules regardless of visibility. | Derive visibility once at shell/page boundaries and gate presentation timelines; leave provider cadence unchanged. | Medium: shared progress and camera cover. |
| Q9 / P1 | Shell; `NotchiumShellView` | Resolved Reduce Motion/Transparency render overrides reach the model but not child environment. | Inherit resolved system preference policy from the shell boundary. | Low. |
| Q10 / P1 | Compact activity, Clipboard, Shelf, Pomodoro | Motion: unconditional scale/spring/progress/phase animations bypass Reduce Motion; a device flip can continue after preference changes. | Targeted opacity/static feedback and settling, preserving IDs, shape and deadline ownership. | Low/medium: interruption paths. |
| Q11 / P1 | Caffeine; `CaffeinePressButtonStyle` | Primitive button is an AppKit mouse overlay with accessibility action but no keyboard responder behavior. | Provide keyboard activation/focus using existing press ownership and duration actions. | Medium: pointer hold/cancel behavior. |
| Q12 / P1 | Clipboard; `ClipboardPageView` | Rows use a tap gesture plus button trait, lack primary accessible copy action/selected state; Space is omitted. | Native primary action and keyboard/selection semantics; keep pin/delete as separate actions. | Medium: selection, copy and arrows. |
| Q13 / P1 | Spotify; loopback callback/authorization | First matching callback resolves listener before state validation; a silent connection can occupy it for five minutes. | Validate expected attempt before completion, reject stale/malformed requests without consuming it, bound each connection. | Medium: legitimate callback, cancel and reconnect. |
| Q14 / P1 | Reminder; `QuickReminderModel` | Debug log formats raw/effective title, due date and list identity. | Remove sensitive payload fields; preserve coarse outcome diagnostics. | Low. |
| Q15 / P2 | Shared slider; `NotchiumSlider` | Low-contrast track and unconditional clear-glass thumb ignore Increase Contrast/Reduce Transparency. | Preference-aware track/opaque fallback and visible keyboard focus, keeping pointer binding lifecycle. | Low/medium: pointer and AX representation. |
| Q16 / P2 | Media progress | Spoken seek value is only colon time with no known duration. | Spoken elapsed and total duration; retain fixed-width visual time. | Low. |
| Q17 / P2 | Audio/Calendar availability | Mixer warning is hover-only followed by false empty copy; Calendar granted/unavailable fixture appears as no events. | Compact visible unavailable/recovery semantics distinct from empty/denied. | Low. |
| Q18 / P2 | Settings | Technical distribution enum, verbose entitlement explanation and absolute password-manager exclusion claim. | Short intent-based copy and precise best-effort privacy explanation. | Low. |

Pending evidence, not classified defects: Audio battery combined-label value preservation; Mirror permission-button grouping; real VoiceOver speech; transient focus restoration; controlled production CPU/wakeups/memory. Baseline full package run: 655 tests, one failure at the previously documented mixer permission assertion. Unchanged Debug workspace build passed.

## Read-through coverage and preserved contracts

Reviewed collapsed shell, expansion, activity routing, takeovers and minor HUDs; Home Media/Calendar/shortcut row; Media playback/seek/artwork/devices and provider states; Calendar main/preview/reminders/Join/permission/settings; Audio output/mixer/battery/unavailable controls; Shelf toolbar/Quick Look/native drag/Share/AirDrop/bookmarks; Clipboard kinds/search/pins/retention/persistence/capture; Pomodoro engine/running/paused/history/statistics; Mirror preview/devices/permissions/capture lifecycle; Caffeine/Reminder/Settings/Home customization/Shortcuts; downloads/screenshots/battery/device/volume/brightness fixtures; empty/loading/error states.

Activity ranking, manual page ownership, stable transfer identity and terminal monotonicity, timer grace/expiry, paused seek, Home composition, Shelf move/Option-copy and no-alias behavior, auxiliary session ownership, display generation/panel ownership, and Stage 22 caches/scopes/cancellation/coalescing remain the governing contracts. Source views derive presentation state; feature models/providers remain authoritative.

Clipboard recovery: the app’s private Keychain access group is declared in both entitlement profiles. Without it, the data-protection Keychain cannot supply the clipboard key even on an unlocked Mac. Keychain interaction errors are distinguished from missing keys, entitlement failures and corrupt files. Opening Clipboard after failure or selecting **Try Again** reloads authenticated, committed history before capture and edits resume. Captures and edits are ignored while storage is unavailable; pending changes that failed to save are never merged into restored history because that could resurrect deleted entries or undo pin changes. Existing ciphertext is preserved and missing keys never cause replacement keys to be generated.

## Skills loaded and applied

- `apple-design`, `emil-design-eng`, `break-ui`, `improve-animations`, `review-animations`, `write-swift` — `emilkowalski/skills`, native principles, hostile content, motion inventory/diff review and Swift quality.
- `accessibility-compliance`, `screen-reader-testing`, `stride-analysis-patterns`, `code-review-excellence`, `multi-reviewer-patterns`, `debugging-strategies` — `wshobson/agents`, native semantics, trust boundaries, independent review dimensions and root-cause investigation.
- `security-review`, `gem-design-md-guidelines` — `github/awesome-copilot`, privacy/security and secondary desktop cross-check. The latter was recovered from upstream revision `b7329669435af0c410b7889843bddfc62e19724d` after removal from main; no substitute.
- `systematic-debugging`, `test-driven-development`, `verification-before-completion` — `obra/superpowers`, reproduce/isolate/fix/regression and fresh evidence.
- Existing XcodeBuildMCP guidance was read; no XcodeBuildMCP tools are exposed in this session, so the existing workspace/scheme uses Xcode CLI. Context7 supplies current Apple API documentation. No bundled third-party scripts were executed or app dependencies added.

## 23A — Apple-native design

The existing permanently black shell, geometry, page order, content layout and toolbar roles were retained. Changes address functional focus, semantics, contrast and overflow rather than subjective restyling. `NotchiumSlider` now has an opaque thumb fallback, a stronger track with Increase Contrast, and a keyboard focus outline. `NotchPageButton` shows focus and clearer contrast selection. Mirror's camera list scrolls within its existing footprint instead of silently omitting devices after the fourth. Existing 28–32 pt header/toolbar targets remain appropriate to the compact desktop layout; no blanket touch-sized redesign was applied.

Native Home, empty Music, empty Audio and unavailable timer screenshots were inspected before the Mac locked. The original visual composition remained intact. Long player metadata is also covered by a fixed-viewport raster regression. The permanent DEBUG quality fixture supplies Unicode/long media and Calendar labels, battery components, seven cameras and utility feature flags for remaining native inspection; its services are mocks and its clipboard store is in memory.

## 23B — Accessibility

- Expanded panels can become key; passive reconciliation does not take focus. **Open Notchium** deliberately expands and focuses the existing panel. Collapsed and hovered panels remain ineligible. `Stage23ShellAccessibilityTests` verifies that eligibility follows every presentation state.
- Native CUA confirmed that Home exposes only visible Home content and header controls. Hidden Music/Calendar/Audio/Shelf descendants are absent. Escape collapses the shell and removes expanded controls from the AX tree. Retained page mounting and provider identity remain intact.
- Native Tab focused Caffeine with a visible ring. Return toggled its mocked state; Down opened its native duration menu; Escape dismissed that menu and restored focus. Standard buttons continue to follow macOS Keyboard Navigation settings. Full traversal with that setting enabled remains a native check.
- Shuffle and Repeat expose current values and selection. Playback position has an elapsed/total spoken value. Clipboard rows are native copy buttons with selected semantics, pin/delete actions, and Space support. Decorative waveform output is hidden from accessibility.
- Reduce Motion and Reduce Transparency use optional inherited presentation overrides with the native read-only environment values as defaults. Increase Contrast follows the same policy. Tests exercise actual waveform suppression, Calendar material fallback and native slider track pixels.
- In-process SwiftUI AX test experiments did not expose real descendants under the package host and were removed rather than accepted as proof. Native AX inspection is the evidence. Actual VoiceOver speech, battery grouping, camera permission grouping and transient focus restoration remain unverified.

## 23C — Motion

The pre-edit inventory covered shell morphs, notifications/takeovers, page changes, compact activity identity, Home, Calendar, Media, utility press feedback, Mirror, Shelf progress, Clipboard and timer phases. Existing shell/page/notification roles and their constants remain authoritative. No competing animation framework or new default springs were introduced.

Reduced motion removes compact insertion scale, progress-level springs, timer-wide phase animation and Shelf progress animation, and uses static Clipboard copy feedback. Device flip work settles when the preference changes. The existing shell interruption/generation machinery remains intact. Hidden Home Calendar, retained Media progress copies and Caffeine presentation timelines now pause when their surface is not visible; provider cadence and timer deadlines are unchanged.

Independent `review-animations` review approved the scoped diff with no source-confirmed regression. A later independent shell review also found no reachable defect in visibility, retained lifecycle callbacks, keyboard eligibility or motion. This is a source review verdict; it does not claim a measured frame rate or completed live interruption matrix.

## 23D — UX and copy

The menu's stage/status jargon and Settings' distribution enum were removed. Focus capability copy states what the user can expect. Focus Timer steppers reuse the configuration's supported ranges. Audio now distinguishes unavailable per-app mixing from an empty app list; Calendar distinguishes unavailable data from no events and exposes retry. Clipboard has an independent capture toggle, a visible storage error and honest sensitivity/exclusion wording. Locked-history recovery offers retry after unlock and warns that recent changes may not have saved.

## 23E — Security and privacy

Reviewed trust boundaries: OAuth browser → IPv4 loopback → state/PKCE/token exchange → Keychain; pasteboard → capture service → bounded model → disk; external files/URLs → Shelf/native actions/bookmarks; EventKit and camera permissions; configuration decode; provider generations; diagnostic logging and signing/entitlement configuration.

Concrete fixes:

- Clipboard metadata and assets use AES-GCM with identity-bound authenticated context and a distinct 256-bit local, non-synchronizing Keychain key. Keychain reads use an `LAContext` with interaction disabled. Missing keys/authentication errors never generate replacement keys for existing ciphertext or fall back to plaintext.
- Descriptor-relative directory/file operations reject symlinks, non-regular payloads and hard links, bound reads, and create private files/directories. Ordered atomic writes sync the file and directory. Migration authenticates committed index/assets and makes renamed entries durable before deleting legacy sources. Corrupt/incomplete history blocks writes and cleanup, preserving evidence for recovery.
- Capture defaults off for the production service and is independently persisted. Disabling cancels the owned capture task and rejects stale generation deliveries without deleting accepted history.
- Loopback validates method/path, unique expected state and code/error shape before accepting an attempt. Invalid traffic closes only that connection. Limits remain 8 KiB input and five minutes per attempt, with ten seconds per connection. Generation guards reject stale completions. An invalid authorization callback no longer consumes the valid attempt. UI cancellation retains task ownership until provider cleanup ends.
- Reminder logs no longer format title, date or list identity. The initial source/history credential scan reviewed 450 text files and 1,412 reachable text blobs with no committed credentials found; a skill documentation placeholder was excluded. No secret values were emitted.

STRIDE cross-check: OAuth state/identity handles spoofing; authenticated payloads and constrained file operations handle tampering; coarse diagnostics avoid logging payloads; local encryption/opt-in address information disclosure; input/time bounds and preference validation address denial of service; existing permission and signing boundaries remain the privilege boundary. These controls do not prevent a compromised process running as the same user from reading live clipboard memory or invoking the app's Keychain identity.

Residual risks: best-effort source attribution/secret exclusion; lost keys make encrypted history unrecoverable; pending changes that fail to save may be lost on recovery; no new reset-encrypted-data flow was added. Existing Downloads/Desktop screenshot observation still has no independent opt-in matching the broader permissions ledger; changing those previously approved feature contracts was not silently folded into Clipboard polish. Real signing/Keychain/TCC revoke flows still need native validation.

## 23F — Swift and architecture

Feature models and platform services remain authoritative. Visibility derives from expansion, page selection and camera cover at the page boundary. Accessibility preferences are inherited presentation inputs, not alternate feature state. The plaintext store was replaced by focused encryption/directory/persistence files, retaining its Stage 22 serial queue and ordering barriers. Failure callbacks publish model state on MainActor outside the store lock, with stale-state filtering and weak ownership.

Restored timer preferences are normalized within the established ranges before use; explicit short engine fixtures still work. Duration conversion avoids integer overflow. No third-party dependency was added. Stage 21 display/session generations, Stage 22 coalescing/caches, provider ownership, stable activity identity, Shelf operation semantics and real timer deadline handling were retained. Independent Clipboard review found durability and observation issues; both were fixed and regression coverage added. OAuth and shell/concurrency reviews found no remaining high-confidence actionable defect in their scoped diffs.

## 23G — Performance

Two bounded Activity Monitor traces attached only to the task-created mock app after collapse. They use the same Stage 11 services and Reduce Motion setting. Measurements below are short observations, not a benchmark or proof of leak freedom. The second trace yielded fewer valid CPU samples, and machine/input/lock conditions were not controlled well enough to attribute the full numerical difference to code.

| Closed mock process | Before | After |
| --- | ---: | ---: |
| Valid CPU samples | 20 | 13 |
| Mean CPU, percent of one core | 0.7815% | 0.0084% |
| Maximum sampled CPU | 0.9012% | 0.0647% |
| Footprint, first → last | 44,008,528 → 43,959,376 B | 43,697,208 → 43,762,744 B |
| Idle wakeups, counter delta | 2 | 1 |

The after sample is consistent with the source fix pausing hidden presentation timelines. It does not quantify production playback, scrolling, camera switching, long-session allocations/leaks, GPU work or animation hitches. Those measurements require the remaining live workload matrix. No app-level polling was added. Raw task profiling bundles are temporary and are removed after aggregate extraction.

## 23H — Validation

- Baseline: unchanged Debug build passed; 655 XCTest tests ran with the mixer permission publication test failing before any Stage 23 source edit.
- Meaningful pre-fix failures established plaintext/symlink persistence, corrupt persisted timer configuration, invalid OAuth consuming an attempt and expanded keyboard eligibility. The missing encrypted-image regression also failed before its fix. No false claim is made for the removed AX harness.
- Final focused run: 75 XCTest tests passed, covering Spotify/OAuth, Clipboard opt-in/security/observable failure, accessibility rendering, expanded-panel eligibility and the mixer readiness fix. Four parameterized Swift Testing timer tests also passed in the full run.
- Native contrast rendering: 4/4 raster tests passed. The slider test uses a real hosting view, correct Retina scaling and inherited contrast policy; waveform/Calendar fallback and long media layout use raster checks.
- The old mixer test used four yields to wait for a serialized actor task chain. The assertion remains unchanged; a bounded wait for status publication replaces that scheduling assumption.
- Final Debug and Release workspace builds passed after the noninteractive Keychain API update. No new compile warning remains; the existing App Intents metadata-extraction warning remains. Rasterizing the complete player with `ImageRenderer` produces a test-only FocusState warning; that renderer does not validate focus behavior.
- Final full-suite run: **673 XCTest tests passed, zero failures, 49.833 seconds; four Swift Testing timer tests passed** (one test covers four hostile integer arguments). Logs: `/tmp/notchium-stage23-final-full-tests.log`, `/tmp/notchium-stage23-final-focused.log`, `/tmp/notchium-stage23-final-debug.log`, `/tmp/notchium-stage23-final-release.log`. No configured lint task was found. `git diff --check` passed; new source/test/document files were also inspected directly.
- Native AX, Caffeine menu/focus and collapsed isolation checks passed as listed above. The remaining native fixture pass was blocked when the Mac locked and CUA could not unlock it; the user was asked to unlock while build/review work continued.

## Remaining issues

No source-confirmed release-blocking regression remains in the reviewed Stage 23 diff. This is not full release certification. Verify on the unlocked Mac: actual VoiceOver speech/rotor values and hidden content; Keyboard Navigation traversal and **Open Notchium**; focus restoration after Settings, Reminder, Mirror and native menus; all seven camera choices and permission grouping; battery component values; Unicode/long Calendar metadata, dense shortcuts and Shelf/Clipboard rows; real drag/Share/AirDrop and external display/fullscreen transitions; live Reduce Motion/Transparency/Increase Contrast changes; real Keychain/signing, pasteboard denial/revoke and camera/Calendar TCC lifecycle; prolonged production CPU/wakeups/allocations/leaks and frame behavior. The loopback connection deadline has source review but no deterministic stalled-connection test. Existing Stage 22 tombstone lifetime and the broader Downloads/screenshot consent mismatch remain outside this scoped patch.

The mock UI, focus, raster/layout and instrumentation checks can continue with agent tools once the Mac is unlocked; they are pending work, not checks delegated to the user merely to finish the report.

## Manual checks requiring the user

Unlock the Mac to restore native UI access. Audible VoiceOver experience requires human listening because AX inspection does not establish spoken output. Real account authorization, TCC permission decisions/revocation, camera hardware behavior, AirDrop to another device, and display/lid/fullscreen hardware combinations require the user's accounts, consent or physical setup. No automatic permission grant or production credential change was performed during this audit.
