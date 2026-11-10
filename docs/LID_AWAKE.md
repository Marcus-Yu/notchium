# Closed-lid keep-awake (experimental, direct distribution)

**November 8, 2026: the free release ships the helper.** Caffeine keeps the Mac awake with the lid
closed in both direct builds; only the sandboxed App Store profile omits it. The owner chose this
over paid Developer ID signing, accepting a weaker peer check in the ad-hoc build (see *Free-build
trust model* below). The Developer ID build keeps its Apple-anchored requirements unchanged.

Ordinary Caffeine uses public idle-sleep assertions; those do not override lid-close sleep. In the direct-download app, clicking Caffeine turns its shortcut orange and keeps the Mac and display awake indefinitely; the native right-click menu offers 15/30/60/120 minutes. Activation also requests the existing separate `SMAppService` launch daemon. First-time administrator approval in Login Items & Extensions is required: the app opens those settings, and the Caffeine menu offers an approval shortcut while pending. Approval is detected automatically (checked every 2 seconds for up to 10 minutes) and, if Caffeine is still on, the lease starts without toggling it again. A never-registered daemon can report `.notFound` instead of `.notRegistered`; both trigger registration, and the resulting status (not a thrown registration error) decides between ready, pending approval and failure. Settings → Closed-lid keep-awake also remains available. The helper defaults inactive at launch and is never registered by mocked services. Turning Caffeine off, timed expiry, or app shutdown releases the lease. The built-in panel still turns off when the lid closes.

## Switching signing profiles on the same Mac

The free build uses its own system-wide helper registration. macOS can pin a
previous helper registration to an Apple signing team, which blocked the
first free candidate on a Mac that had run the Xcode build. A separate macOS
account still shares these registrations. The new free helper gets its own
approval in Login Items & Extensions.

Before replacing an old build, turn Caffeine off. To remove the old helper,
use **Settings → Caffeine → Remove Closed-Lid Helper** in the old copy and
wait for confirmation, then quit it. The current free and signed helpers use
the same lock and recovery journal, so only one can own the sleep override.

To verify closed-lid keep-awake, wait for the app to report that it is active
and confirm that `pmset -g` shows `SleepDisabled 1`. Close the lid and verify
that the Mac continues a task. The built-in display turns off. Turn Caffeine
off and confirm that `SleepDisabled` returns to `0`.

## Privilege boundary

The signed build uses `com.marcusyu.notchium.lid-awake`; the free build uses
`com.marcusyu.notchium.lid-awake-free`. Each name matches its launchd label,
Mach service and code-signing identifier. In the Developer ID build, both XPC endpoints enforce Apple-anchored signing requirements with team `ZU27M973HX` and their exact peer identifier. Its interface accepts only renewal and release, with no caller-provided command, path, timeout, or executable. Signing-team changes must update `LidAwakeIdentity` and the Xcode signing configuration together.

The daemon runs `/usr/bin/pmset -a disablesleep 1` and verifies `SleepDisabled` before reporting success. This is a system-wide setting, **including manual Sleep**, not a public idle assertion or guaranteed cross-version clamshell API. Physical testing is required on each supported macOS/hardware combination. No privileged operation is performed by a SwiftUI view, shell interpolation, password capture, sudoers change, or private kernel API.

### Free-build trust model

The free build is ad-hoc signed and has no certificate chain, so `LidAwakeIdentity.requirement` (compiled
with `NOTCH_FREE_DISTRIBUTION` into both the app and, by `scripts/build-lid-awake-helper.sh`, the helper)
requires only the peer's signing identifier. The helper also accepts a connection only when the
kernel-reported executable of the client (`proc_pidpath`, symlinks resolved) is `Contents/MacOS/Notchium`
inside the same app bundle that contains the helper. The mach service is registered by launchd from the
app's own `SMAppService` job, so the app's check of the helper is not spoofable without root.

Residual risk, accepted by the owner: a local process running as the user that can place a binary at
that exact bundle path, or reuse the client identity, could hold the keep-awake lease. The interface is
unchanged and verb-only, so such a client can keep the Mac from sleeping, still bounded by the 15-second
lease, the 15% battery floor and the thermal cutoff. It cannot run commands, choose paths or change any
other setting.

## Recovery

- One XPC connection owns the override. Other sessions cannot renew or release it.
  A root-owned file lock also excludes the other distribution profile until restoration finishes.
- The app renews every 5 seconds. The helper checks a 15-second monotonic deadline every second.
- Client disconnect, lease expiration, battery at or below 15% while on battery power, or serious/critical thermal pressure releases the override.
- Before mutation, a root-owned journal at `/var/db/com.marcusyu.notchium.lid-awake` records ownership. Existing `SleepDisabled=1` from another utility is rejected; Notchium does not take ownership of it.
- Normal release verifies `SleepDisabled=0` before deleting the journal. Failed restoration leaves the journal and retries every second.
- `RunAtLoad` and `KeepAlive` restart the daemon after a crash and at boot; startup restores any journaled override. SIGTERM also attempts restoration.
- `pmset` subprocesses have a 3-second deadline. Restoration therefore may take longer than the nominal lease deadline during failures.
- Removing the helper first obtains a successful restore reply, then unregisters it. Do not manually delete the app while a lease is active. No daemon can guarantee recovery if its files or launch registration are removed externally, or if the OS refuses power-setting changes.
- Another power utility changing the same global setting concurrently cannot be fully attributed. Avoid combining closed-lid utilities.

The app shows active only after a successful helper reply. Losing helper connectivity turns the option off; the helper lease then expires independently. Do not put an awake Mac into a bag or other enclosed space.

## Build and validation

The app's build phase compiles the daemon with Swift 6 and strict concurrency for each requested architecture, embeds it in `Contents/Library/HelperTools`, installs its plist in `Contents/Library/LaunchDaemons`, and signs it with the app's identity (ad-hoc, without Hardened Runtime, in the free build). The build phase omits the helper for `NOTCH_APP_STORE`. `release.sh` builds with signing disabled, then seals the helper ad-hoc with its fixed identifier before the app. `verify-release.py` requires exactly this helper and launchd job (exact plist equality, identifier, ad-hoc signature, system-only links) and fails on any other privileged component.

`Helpers/LidAwakeTests/main.swift` tests the power adapter with an injected fake command runner and a temporary journal; it never changes system settings or requires root. Scenarios: acquire, idempotent renewal, release, foreign ownership rejection, unsafe-condition rejection, concurrent helper exclusion, crash recovery, and failed restoration followed by retry.

Live validation still requires administrator approval and physical lid closure: test indefinite and timed Caffeine on AC and battery, Caffeine off, app exit, killed app, killed helper, expiry, and helper removal. Check `pmset -g` before/after. Do not treat a successful command or unit test as proof of physical lid behavior.
