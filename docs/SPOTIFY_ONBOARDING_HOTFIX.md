# Spotify onboarding hotfix — 1.0.1 / build 3

19 October 2026. Baseline: `1a65187c7dedffe2747352591c1a141c43b1b180`.
The owner's untracked `STAGE27C_PRODUCTION_RELEASE_VALIDATION.md` is preserved.
No comprehensive audit was reopened. No tag, push, publication, TCC reset,
Keychain reset, production-app replacement or tester notification was performed.

## Diagnosis and evidence

The reproduced policy defect is a permanent completion block for a denied or
unresolved Spotify requirement. Baseline `OnboardingModel.isSatisfied` accepts only
real grants or the generic unavailable/restricted/nonpregrantable acknowledgments.
Its existing `testEveryMissingGrantBlocksCompletion` expressly verifies that denied,
not-determined, unknown and stopped-Spotify states block Finish Setup. There was no
explicit Spotify opt-out. The new exception regression demonstrates denied Spotify →
explicit choice → eligible Final Review → durable Ready, while another Calendar
denial still blocks completion and Spotify remains labeled denied.

The baseline action is `OnboardingView` → `OnboardingModel.request` →
`NativeOnboardingPermissions.request` → Spotify discovery/launch → PID nonprompting
preflight → `SystemSpotifyScriptExecutor.requestAutomationPermission` → five-second
AppleScript `get version` event → preflight → refresh of all requirements. The model
keeps `isBusy` true until all of this returns. Permission checks and AppleScript share
one serial queue. A stalled event or preflight can therefore also stall refresh and
keep the entire wizard busy. LaunchServices completion was used without explicitly
checking `isFinishedLaunching`. Errors were collapsed to a generic message.

**The affected Mac's actual Apple Event failure remains unconfirmed.** No failing
OSStatus, native dialog receipt, or separate account/Mac was supplied or available.
The old five-second script path is a fragile consent mechanism, but this session
cannot prove whether its timeout, Spotify readiness, denial, target loss, an OS issue,
or the ad-hoc application identity caused that user's original Request Access error.
No development fixture result is presented as production TCC evidence.
Both inspected 1.0.0 and 1.0.1 packaged Info.plists retain
`com.marcusyu.notchium` and the nonempty `NSAppleEventsUsageDescription`. The new
free candidate retains the existing ad-hoc/empty-entitlement policy; no paid signing
identity or user-approved signing equivalence is inferred. A missing usage string
is not present in the inspected 1.0.0 candidate.

The inspected macOS 27 SDK `AE.framework/Headers/AppleEvents.h` documents that
`AEDeterminePermissionToAutomateTarget` requires a running target, supports an explicit
prompt using `askUserIfNeeded: true`, and may take arbitrarily long; it must not run
on the main thread. The exact constants were checked in that header and
`CarbonCore.framework/Headers/MacErrors.h`. Context7 supplied Apple's Mojave release
notes; the API declaration was also checked against [Apple's API reference](https://developer.apple.com/documentation/coreservices/3025784-aedeterminepermissiontoautomatet).

## Source changes and ownership

- `SpotifySetupAuthorization` owns injected application discovery/launch, native
  authorization and clock adapters. It uses the live finished-launching Spotify PID
  and wildcard Apple Events. Consent and nonprompting checks have separate worker
  queues, independent of existing playback AppleScript. No OAuth, Web API, helper,
  metadata read or playback command was introduced for onboarding.
- Launch readiness polls for up to five seconds after LaunchServices returns. The
  overall request UI wait is thirty seconds and each status wait is three seconds.
  A blocked OS operation stays owned and coalesced; timeouts release UI waiters only.
  A real sheet remains answerable. Repeated clicks cannot queue another native
  request, and a late result is verified on subsequent refresh. No timer grants access.
- OSStatus 0 means granted; −1743 denied; −1744 not determined; −600/−609 Spotify
  unavailable/stopped; −1712 timeout; other codes report their exact value. The model
  displays Spotify-specific recovery text. Denial opens the supported Privacy &
  Security path and explains the Automation subpane; a known denial is not reprompted.
- `Continue Without Spotify` explains unavailable local controls and records `.spotify`
  in the existing durable `reviewed` set. OS status stays separate. All fifteen
  requirements remain visible and all other completion policies are unchanged.
  Settings keeps repair actions available. A later real grant is displayed normally.
- Stopped/cancelled model operations cannot apply stale status/error completions or
  clear a newer request. Existing local playback continues to enforce actual access.
- Configuration is incremented from 1.0.0/build 2 to 1.0.1/build 3 because candidate
  1.0.0 was manually shared according to the user report. Data stores, encryption,
  Keychain, Shelf and Clipboard capture implementations were not changed.
- Native QA fixtures cover the explicit Spotify denial exception, Ready/Open and
  repeated relaunch. The release verifier rejects the new fixture marker. Permission,
  release and tester replacement documentation is updated.

## Validation

The complete preview pipeline passed on Xcode 27.1 (27A9275), macOS 27.0.1 arm64.

| Check | Actual result |
|---|---|
| Main package XCTest | 784 executed, 778 passed, 6 expected skips, 0 failures |
| Proactive XCTest | 38 passed |
| Default-profile Swift Testing | 5 passed |
| Explicit free-profile Swift Testing | 2 passed |
| New Spotify hotfix regressions | 13 passed (included in the main package total) |
| Existing onboarding regressions | 25 passed (included in the main package total) |
| Release-safety tests | 11 passed |
| Debug and optimized free Release | Both built successfully |
| Xcode static analysis | ANALYZE SUCCEEDED on final hotfix sources in QA workspace |
| Source, app and packaged-app verifier | Passed |
| DMG verify, readonly mount, Applications link, copied-app audit, checksum | Passed |
| Whitespace | git diff --check passed |

XCTest native onboarding automation built its runner but failed before a case ran:
“Timed out while enabling automation mode.” Four planned native onboarding cases
therefore have no XCTest pass receipt. The `.xcresult` and log are retained at
`/private/tmp/notchium-hotfix-qa/`. This is an infrastructure failure, not a product
assertion failure.

A separate direct native UI check using the QA identity and synthetic protected
services passed: Spotify Request Access → Denied → Continue Without Spotify (Denied
still visible) → all remaining requirements → enabled Finish Setup → Ready → Open
Notchium → shell → quit → same-fixture relaunch into shell without setup. This is
one manually driven QA scenario, not four passing XCTest cases or real TCC evidence.
The QA app was closed afterward. Its synthetic `Onboarding.json` was inspected:
`completion: userCompleted`, `step: ready`, `clipboardChoice: false`, and `spotify`
in `reviewed`; it contains no OS grant. The direct observation receipt is
`/private/tmp/notchium-hotfix-qa/manual-ui-receipt.json`.

Existing full-suite regressions cover byte preservation of synthetic preferences,
opaque Clipboard/image/Pomodoro files and Keychain recovery semantics. The hotfix
exception test also verifies unchanged Clipboard consent writes and an unrelated
Calendar denial continuing to block. No personal data was used.

The first preview pipeline was deliberately interrupted during compilation after
review caught an unsupported-profile request guard; logs are preserved in
`dist/1.0.1-preview-interrupted-store-guard/`. The corrected final preview pipeline
passed. Its executable, tests and release tools match the recorded source snapshot.

Preview DMG: `dist/1.0.1-preview/Notchium-1.0.1-preview.dmg` (3,985,241 bytes).

- DMG SHA-256: `86fbfe700ee6363609b66f3d572ce49522ba433504bc58e61472d86065062125`
- Executable SHA-256: `fac6e8dd67f758bddace31ddbadbae756ad591b76116a28bd07937f65dcd07a9`

The manifest contains all source hashes and the baseline commit. This preview is
not publishable. A committed-source production candidate has also passed; its receipt follows.

No separate Mac account or affected MacBook is available (owner confirmed). Real
production consent, installed Finish Setup/Ready/Open Notchium and replacement data
preservation remain unverified. Personal TCC records and Keychain items are untouched.

## Distribution and acceptance

The public GitHub releases API returned `[]` during this session. Local tags contain
no semantic release tag. Only 1.0.0 candidate/preview artifacts exist locally. No
updater is implemented; a source push cannot change installed applications.

The root checkout remains available with the hotfix edits. An isolated hotfix
branch contains only the reviewed hotfix files, excluding the owner’s untracked
Stage 27C report. The existing `--candidate` workflow builds that clean committed
source. Exact packaged real-account recovery, native UI acceptance and
data-preserving replacement must still pass before public distribution is qualified. Existing 1.0.0 artifacts are preserved.

No users have received this build from this session. When qualified, affected testers
must quit Notchium, drag the replacement from its DMG to Applications, confirm Replace,
eject and reopen. Keep all preferences/Application Support/Keychain data. If macOS
asks again, use its supported authorization controls; do not delete encryption keys.

Required real-account receipt: record the exact DMG/executable hashes and OS/CPU;
launch the installed app, reach Spotify, exercise the native grant or recoverable
failure plus explicit exception, finish all other requirements, reach Ready, use
Open Notchium, quit/relaunch without onboarding, verify existing synthetic Clipboard,
Keychain-backed restoration, Shelf and preferences, and repair Spotify from Settings
without reinstalling. No actual fresh-account or macOS 26 runtime acceptance is
inferred from this development host's macOS 27 or synthetic UI tests.


## Final committed-source candidate receipt

**Prepared for isolated-Mac acceptance; NOT approved for public distribution.**

The strict `./scripts/release.sh 1.0.1 --candidate` pipeline exited 0 on clean local
commit `983638408d9b629259b051ac5360de0b39c2beb0`, branch
`codex/spotify-onboarding-hotfix`, in the attached managed worktree
`/Users/marcusyu/.codex/worktrees/spotify-onboarding-hotfix/notch`. No tag or GitHub
push/release was created. The owner's main checkout retains its working-copy hotfix
edits and the original untracked Stage 27C report; that report was excluded from
the isolated commit. Its SHA-256 remains
`222d84af3248d61438dd2d6d3d8d6568039fc3bc1be93bd8a6536cd4cf16d66a`.

Candidate artifacts and private validation records were copied without overwriting
older builds to `dist/1.0.1-candidate/` in the main checkout. After copying, the app
verifier and exact-filename checksum check passed. All current code, tests,
configuration and release-tool hashes match the committed artifact's source manifest.
This final receipt is appended after packaging and is separate from its source snapshot.

- App: `dist/1.0.1-candidate/Notchium.app`
- DMG: `dist/1.0.1-candidate/Notchium-1.0.1.dmg` (3,985,228 bytes)
- Checksum: `dist/1.0.1-candidate/Notchium-1.0.1.dmg.sha256`
- Manifest: `dist/1.0.1-candidate/release-manifest.json`
- DMG SHA-256: `285d4701a87958e32eeea01eba3e5fbb3184cce051065281b989b1526c35905f`
- Executable SHA-256: `fac6e8dd67f758bddace31ddbadbae756ad591b76116a28bd07937f65dcd07a9`

The committed candidate reran and passed 784 main XCTest cases (six expected skips;
778 passed), 38 proactive XCTest cases, five default Swift Testing tests, two
explicit free-profile tests, and eleven release-safety tests. These repeat the preview
suites and are not added together as distinct regression cases. Both app builds,
source/app/mounted-app audits, ad-hoc sealing, DMG verification/readonly mount,
Applications symlink validation, packaged-app extraction and checksum checks passed.
The candidate and preview have the same executable hash; their DMG hashes differ.
Static analysis and the direct synthetic native UI receipt above apply to the same
production source, but neither substitutes for exact packaged fresh-account testing.

Outstanding acceptance: real Spotify OS dialog and genuine grant/denial recovery;
production-identity installed first launch through Ready/Open and durable relaunch;
actual replacement retaining Clipboard/Keychain/Shelf/preferences; later real Settings
repair; XCTest native UI runner acceptance; macOS 26 runtime coverage where required
by the release process. No fresh account/Mac is currently available.

**Publication status:** unpublished local candidate. **Recipients:** none from this
session. **Installed users updated:** none. **Update mechanism:** manual app replacement,
after acceptance; no automatic updater exists. Existing encrypted user data was not
read, reset or migrated by this hotfix session.
