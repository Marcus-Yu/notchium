# Stage 27B — First-launch permissions and durable setup

Date: 19 October 2026. Version 1.0.0, build 2. Starting HEAD:
`d2b8ce9096fae05fa1eb23637a1b3cb981997dca`. The starting working tree was clean.
Implementation is uncommitted. No reset, clean, history rewrite, push, tag, publication,
DMG packaging, or Stage 27C work was performed.

## Product behavior and screens

A new profile opens a standard, resizable native AppKit window with SwiftUI content.
Its initial content size is 680 × 620 points, with a 620 × 520 minimum content layout.
It uses system typography, SF Symbols, native buttons, semantic colors, a scrolling
content area, and a fixed navigation footer. The normal 524 × 266 shell and 740 × 322
host geometry are unchanged.

1. **Welcome:** concise explanation of the one-time setup; Get Started.
2. **Permissions Overview:** all fifteen implemented requirements, purpose/feature,
   current status, and a Review action. Set Up Permissions starts the sequence.
3. **Permissions:** one requirement at a time, its data handling, current result,
   and its appropriate request, selection, Settings, or acknowledgment action.
   Continue moves to the next row; Review All opens the consolidated review.
4. **Final Review:** separates Permissions granted, Requirements completed,
   Exceptions reviewed, and Needs attention. Finish Setup stays disabled until
   every applicable requirement satisfies the documented policy.
5. **Ready:** completion has already been committed atomically. Open Notchium
   starts normal feature observation and opens the shell. Quitting here still
   preserves completion for the next launch.

There is no Skip All. Quit & Resume Later remains available while waiting for a
system response. Closing the setup window quits, preserving progress. Normal shell
startup and feature observation are gated; the menu offers Resume Setup and Quit.
Settings cannot initialize its feature controls while setup is incomplete.

The setup window uses normal window level, regular activation, and fullscreen
auxiliary/active-Space behavior, so it does not overlay higher-level system dialogs.
Opening Spotify for consent returns activation to Notchium before the request.
Real permission-dialog/fullscreen acceptance remains unverified, as detailed below.

The step transition uses a restrained 0.3-second smooth animation. Reduce Motion
disables this app-authored motion. Buttons have native keyboard/focus/press behavior;
Return activates the step’s default action and Command-Q exits. Status text and symbols
provide information independently of color; acknowledgments never get green grant checks.

Native minimum-size fixtures: [dark audio disclosure](assets/stage27b/dark-systemAudio-620x520.png),
[light denied-access layout](assets/stage27b/light-volumeKeys-620x520.png), and
[dark pasteboard setup](assets/stage27b/dark-clipboardAccess-620x520.png).
These are AppKit/SwiftUI renders of synthetic states, not genuine permission-dialog receipts.

## Actual permissions inventory

All OS status checks are live adapter results, not values restored from onboarding.
The table describes the implemented setup mechanism, not grants observed on the owner’s Mac.

| Requirement / feature | Setup mechanism and authoritative status | Recovery, limits, and data handling |
|---|---|---|
| Calendars / Calendar and Home | `EKEventStore.authorizationStatus(for: .event)`; request full access with `requestFullAccessToEvents()` | Already granted does not prompt. Write-only access offers a full-access upgrade. Denial needs Privacy & Security → Calendars. No event or calendar is fetched during setup. |
| Reminders / Quick Reminder | Separate EventKit reminder authorization; `requestFullAccessToReminders()` | Denied choices are not repeatedly requested. No list is read and no reminder is created to verify permission. |
| Spotify Automation / local music | Verify installed/running `com.spotify.client`; PID-targeted nonprompting `AEDeterminePermissionToAutomateTarget`, then an explicit normal Apple Event reading only the application version, which is discarded | Follows the existing local controller’s consent approach because its source records that the prompting preflight form can stall before showing UI. A stopped installed Spotify must be opened by the explicit action. No song data or playback command is used. Missing app is an explicit unavailable exception. Unknown/contact failure blocks completion. Denial routes to Automation. No OAuth/Web API was added. |
| Camera / Mirror | AVFoundation authorization through the existing camera adapter; request video access only when not determined and hardware is present | No camera session, preview, image, or microphone capture. Missing hardware is distinguished from its underlying OS authorization in the explanation. Existing grants remain labeled granted even if hardware is later absent. |
| System Audio Recording / waveform and per-app mixer | Explicitly reviewed non-pregrantable requirement | Core Audio process taps prompt when capture starts and expose no independent public authorization query/request in the inspected SDK. Setup creates no tap, aggregate device, or audio stream. Samples stay in memory. Screen Recording is a different permission and is not requested. System Settings/quit-and-reopen may be necessary. |
| Accessibility/event-post access / optional volume HUD replacement | `AXIsProcessTrusted()` plus `CGPreflightPostEventAccess()`; explicit `AXIsProcessTrustedWithOptions` and, when needed after trust, `CGRequestPostEventAccess()` | Current checks must both pass. Granting trust leaves the existing replacement preference unchanged. No general keyboard capture or Input Monitoring request is added. Store distribution reports unavailable. |
| Screenshot folder / new screenshot activities | Native `NSOpenPanel` directory selection; persisted bookmark | “Folder Selected” is a completed selection, not a universal OS grant. New selections constrain folder watching and Spotlight supplementation to that folder. A successful security-scope acquisition is released at teardown. A changed selection takes effect after reopening Notchium. No screen capture is used. |
| Clipboard History | Separate explicit Enable / Keep Monitoring Off choice | Capture stays stopped during setup. The existing monitoring preference is written only after a deliberate choice. macOS pasteboard privacy is independent and cannot be pregranted by acknowledgment. Saved payloads remain local and encrypted. |
| macOS pasteboard access | Separate read-only `NSPasteboard.accessBehavior` status | Always Allow is an OS grant; Always Deny is a denial; Default and Ask are not grants and have no independent upfront request API. No contents are read to trigger an alert. A current denial blocks setup when monitoring is enabled. When the user explicitly keeps monitoring off, they must separately acknowledge the current OS state as an inactive-feature exception; the denial remains visible and is never relabeled granted. |
| Shelf and file/folder Quick Actions | Explicit review of native user-selected access | Future selections cannot be authorized universally. Existing bookmarks and files are preserved; setup does not enumerate Downloads or import files. |
| Apple Shortcuts / Quick Actions | Explicit review of each shortcut’s own future permissions | Setup does not run a shortcut, read its output, or claim permission for arbitrary actions. No blanket Shortcuts Automation request is invented. |
| System Focus status | Request `INFocusStatusCenter` authorization only if the build actually has the required entitlement and supports the capability | Free distribution reports unavailable; timer-only Focus remains available. Restricted states are separate from denial. Setup does not read the actual Focus value. |
| In-app notifications | Explicit acknowledgment that no OS notification authorization is required | Current alerts are presented in Notchium, not posted using UserNotifications. No third-party Notification Center reader exists. |
| Keychain / Clipboard encryption | Explicit review of per-item, non-pregrantable Keychain authorization | Setup never reads, replaces, deletes, exports, or authenticates a key. Temporary lookup failure is not an empty history or authority to create a replacement key. Ad-hoc updates can need OS reauthorization separately from app-owned completion. |
| Caffeine and closed-lid mode | Ordinary Caffeine requires no permission; helper limitations are reviewed explicitly | Free/Store distributions report the helper unavailable. Developer builds explain the separately signed/installed helper and administrator-mediated enablement. Setup never installs or approves a helper. |

Other scanned services do not introduce a genuine setup authorization: system-volume
controls and battery observation need no TCC grant; public Progress subscription does
not enumerate Downloads; system monitoring/browser/meeting scaffolding is unavailable.
Removed Keyboard Lock and window-snapping concepts do not justify permissions.
There is no new microphone, Full Disk Access, Contacts, Bluetooth, administrator,
Input Monitoring, or Screen Recording request. Existing unused purpose strings are
not treated as evidence that a corresponding permission is needed.

## Completion policy versus present authorization

**Onboarding complete** means every technically grantable, available required OS
authorization is verified, the screenshot folder has been selected, Clipboard has an
explicit choice, and all applicable non-pregrantable/unavailable/restricted exceptions
have been reviewed. A denied or unknown available requirement does not satisfy setup.
An OS-managed restriction cannot be changed by the wizard and is an explicit exception.
The app’s Clipboard consent and the separate macOS pasteboard decision have independent
rows. Choosing Keep Monitoring Off does not grant OS access; a denied OS state can only
be accepted as an explicitly reviewed inactive-feature exception while monitoring stays off.
Switching the app choice back on immediately makes that denial block completion again.
If absent hardware/application becomes available before Finish, the refreshed state
must meet its real authorization requirements; an old acknowledgment cannot bypass it.

**Permissions currently granted** means macOS currently reports those specific OS
grants. Setup completion does not imply that audio, future files, shortcuts, or
Keychain access were pregranted. It does not survive as a cached substitute for TCC.

No real OS grant is claimed by this session. The owner explicitly selected **“Keep
real permission prompts unverified for now.”** Native UI tests use simulated grants,
denials, folder selection, and unavailable/non-pregrantable outcomes. Their successful
Ready screen is evidence of the application state machine, not real TCC acceptance.

## Persistence and returning installations

`OnboardingState` is a small Codable value owned by `OnboardingModel`.
`OnboardingStore` atomically writes a single authoritative `Onboarding.json` under
the existing Notchium Application Support directory. It stores schema version,
incomplete step/current requirement, reviewed exception IDs, the explicit setup
Clipboard choice, and completion provenance. It stores no OS grants or sensitive payloads.
The existing Clipboard preference remains the runtime monitoring choice; later
Settings changes are never overwritten from historical setup state on ordinary launch.

| Launch condition | Behavior |
|---|---|
| No setup record and no genuine app-owned configuration/storage | Save a new incomplete record before feature constructors can seed defaults; show Welcome. |
| Incomplete record | Resume its stored screen and requirement, refreshing OS truth. Persist the selected step before a native request. |
| `userCompleted` record | Launch normally; no build/version/launch-count/reset condition exists. |
| No record, but existing app preferences, Shelf/Home configuration, Clipboard directory, or Pomodoro archive | Save `legacyRecognized`; preserve configuration; launch normally and offer Settings → Permissions. This is not falsely labeled verified full setup. |
| Revoked permission, missing app/peripheral, temporary Keychain error, Settings visit | Keep completion; show current affected feature/checklist state and recovery path. |
| Reinstalled binary with surviving Application Support | Read the surviving record/configuration; binary creation/deletion dates are irrelevant. |
| Corrupt/unreadable setup record or failed initial save | Preserve original bytes, fail closed with an actionable error and safe exit. Do not overwrite or silently complete. |
| Newer completed schema | Preserve the record and returning-user behavior; disallow overwriting with an older schema. |

Completion is committed before Ready is shown. Final completion rechecks every
requirement instead of trusting a previous overview snapshot. Requests and activation
refreshes are serialized and owned by the model; no dialog flood or duplicate refresh
request is issued. OS dialogs cannot be forcibly canceled by Swift task cancellation;
quitting remains a safe process exit and resumption path.

## Data and Keychain protection

No preference domain is reset by production onboarding. Migration only checks known
app-owned keys and existence of storage paths; it does not open encrypted history or
consult Keychain. Incomplete setup defers Clipboard history hydration/key access as
well as pasteboard observation. After setup, existing Clipboard recovery and encrypted
storage code retain their original behavior.

Regression fixtures verify byte preservation of representative Calendar/Spotify/
Clipboard/Home/Shelf/Pomodoro settings and opaque history/image/archive files. Existing
encryption, pinning, bookmark-scope, retention, timer restoration, exact OSStatus,
create-only key insertion, authenticated legacy recovery, and retry concurrency tests
remain in the full suites. Targeted sanitizer runs include Keychain/recovery regressions.
No owner encryption key or real history was read or altered by this stage’s new tests.
The exact packaged same-identity upgrade/Keychain path remains a Stage 27C acceptance gate.

`scripts/tests/test_onboarding_crash.py` compiles the actual state/store source and
uses disposable processes and directories. Both partial and complete records survive
SIGKILL immediately after the atomic save, then ten subsequent independent process reads.
This validates committed application records, not filesystem durability through hardware
power loss or an actual macOS restart.

## Corrections made in this stage

- Removed the Calendar model’s startup permission-request side effect; the wizard owns
  the upfront request and normal Calendar startup only observes existing authorization.
- Added the launch gate, durable new/legacy distinction, interrupted-step restoration,
  final authoritative recheck, and explicit exception/Clipboard choices.
- Deferred Clipboard hydration while a new setup is incomplete; no key access or
  monitoring is needed merely to display onboarding.
- Added a selected screenshot-folder bookmark path with bounded observation and balanced
  security scope, preserving the legacy configured-folder path for returning installations.
- Added permission-only Spotify consent, returning app activation after explicitly opening
  Spotify, without reading personal metadata or controlling playback. A minimal app-version
  event follows the established consent path instead of the known-risk prompting preflight.
- Kept the menu and normal Settings gated through Ready until Open Notchium starts the
  feature lifecycle; final review explicitly shows the Clipboard choice and hardware issues.
- Corrected parent SwiftUI accessibility identifiers that initially overwrote child button
  identifiers, and tightened initial setup-window activation ordering.
- Extended the Release verifier to reject the new onboarding fixture markers.
- Recognized the existing `audio.*` and `media.waveform.*` preference namespaces even
  when no other configuration remains, preserving customization-only legacy profiles.
- Separated the read-only macOS pasteboard privacy result from app-level Clipboard
  consent, including deterministic Allow/Deny/Ask/Default and inactive-feature tests.

No completed Stage 27A general engineering audit was reopened. No unrelated feature,
shell geometry, media architecture, signing policy, encryption format, or data migration
was redesigned.

## Validation and evidence

Evidence is stored locally under `/private/tmp/notchium-stage27b`; source hashes are
recorded in `final-source-manifest.json`. The normal workspace is
`Notchium.xcworkspace`, scheme `Notchium`, macOS arm64, Xcode 27.0 / macOS 27.0.1.
XcodeBuildMCP tools were unavailable; established Xcode CLI/native test fallbacks were used.
UI tests build a temporary source copy with bundle `com.marcusyu.notchium.qa27b`,
mock protected services, and UUID-isolated setup stores. The owner’s running app is
not stopped or replaced. The final Release artifact retains `com.marcusyu.notchium`.

| Check actually performed | Result |
|---|---|
| Complete Swift package XCTest | 771 main cases executed; six expected opt-in skips; zero failures |
| Proactive XCTest | 38 passed |
| Swift Testing in the package run | Five tests passed |
| Explicit free-distribution Swift Testing | Two tests passed with `NOTCH_FREE_DISTRIBUTION` |
| Xcode unit/integration suite and Debug build | 771 XCTest cases executed; six expected skips; zero failures; Swift Testing also passed |
| Complete functional native UI regression | 25 unique cases passed at the full-suite checkpoint |
| Final focused native onboarding | Three cases passed on the final fifteen-requirement implementation: completion and ten relaunches, denied/interrupted setup, keyboard quit/close and resumption |
| Onboarding policy/permission/persistence tests | 25 deterministic cases passed, including all four pasteboard behaviors, denied active monitoring, explicitly inactive monitoring, missing hardware, migration, and fail-closed bookmarks |
| Targeted Address Sanitizer | 41 passed; no sanitizer diagnostic |
| Targeted Thread Sanitizer | 41 passed; no sanitizer diagnostic |
| Minimum-window rendering | One rendering test passed; six native fixtures at 620 × 520, covering long audio disclosure, denial, and pasteboard setup in both appearances |
| Controlled unexpected termination | Partial and complete records survived SIGKILL, with ten subsequent reads each |
| Xcode static analysis | `ANALYZE SUCCEEDED` |
| Optimized arm64 free Release and artifact verifier | Passed; version 1.0.0/build 2, minimum macOS 26.0, expected production identity, empty entitlements, ad-hoc signature, one executable |
| Production source secret heuristic and release-safety tests | Passed; five release-safety tests |
| Whitespace gate | `git diff --check` passed |

The final app-only candidate is
`/private/tmp/notchium-stage27b/candidate/Notchium.app`. Its executable SHA-256 is
`2ff65fa893b12c7a0a69b96d22be83d485834453271aa0453094e55b8c32e5f0`.
The verifier rejects the new onboarding CLI/QA markers as well as existing debug,
coverage, profiling, identity, entitlement, and artifact problems. Production composition
selects real providers; no new runtime mock-provider selector ships. Dormant reusable test
double types in the existing package architecture are not evidence of active QA providers.

The default skips are existing opt-in hardware/diagnostic cases, not onboarding failures.
No real macOS permission acceptance is inferred from these suites. Full UI regression
and focused onboarding counts overlap; they are not 28 distinct functional cases.
The final focused run completed with `TEST EXECUTE SUCCEEDED`; its log and result bundle
are `onboarding-final.log` and `onboarding-final.xcresult` in the evidence directory.
The installed SDK’s read-only pasteboard behavior is observed separately from app consent;
neither Ask nor Default is reported as granted.

Excluded/superseded attempts are retained in the private evidence directory. An initial
sandboxed package invocation could not use the compiler cache; a later sandboxed runtime
stalled in the test waiter and was stopped before rerunning with native test-host access.
Early UI attempts exposed inherited accessibility identifiers and activation ordering;
both were corrected. One full QA run’s Settings test still queried the production bundle
identifier and failed against the owner’s different running process; only the temporary QA
test copy was corrected, then the complete 25-case suite passed. A focused handoff assertion
initially expected an automatically expanded shell. Ready now enters normal shell startup;
the final test explicitly expands it using the established native interaction. The first
analysis invocation rejected a test-only coverage flag; the corrected analysis passed.

Existing warnings include the Focus service’s older synchronous authorization callback,
legacy diagnostic-test actor/unsafe-cast warnings, and AppIntents metadata extraction without
an AppIntents dependency. No new production warning was found in the final Release build.
There is no configured linter. No source signing setting, user security preference, timeout
in production, or personal permission was changed to force a pass.

## Remaining acceptance and verdict

**CONDITIONAL GO.** Genuine first-install OS dialogs, real allow/deny/revoke transitions,
system-dialog placement in fullscreen, actual macOS restart, VoiceOver operation, and
the exact packaged upgrade/reinstall/Keychain authorization path remain unverified.
No real personal TCC reset, Keychain reset, fresh macOS account creation, reboot, or
system accessibility preference change was performed to force an acceptance result.

Stage 27C distribution testing and public release have not begun. This report does
not authorize publication or imply that the owner granted permissions during this work.

Relevant native references consulted through Context7 and the installed SDK include
[EventKit access](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui),
[camera authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media),
and [Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).
Applied installed guidance includes apple-swiftui-native-apps, apple-design,
emil-design-eng, apple-motion-feel, swiftui-expert-skill, swift-concurrency,
macos-patterns, apple-device-validation, and xcodebuildmcp. No dependency was added.
