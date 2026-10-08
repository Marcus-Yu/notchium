# Closed-lid keep-awake (experimental, direct distribution)

**Stage 24 free release:** The helper is omitted and its controls report unavailable.
Its Apple-anchored XPC requirements cannot authenticate an ad-hoc build. Ordinary
Caffeine remains available. The architecture below is preserved for an edition
with an appropriate trusted signing identity; its requirements are not weakened.

Ordinary Caffeine uses public idle-sleep assertions; those do not override lid-close sleep. In the direct-download app, clicking Caffeine turns its shortcut orange and keeps the Mac and display awake indefinitely; the native right-click menu offers 15/30/60/120 minutes. Activation also requests the existing separate `SMAppService` launch daemon. First-time administrator approval in Login Items & Extensions is required: the app opens those settings, and the Caffeine menu offers an approval shortcut while pending. After approval, toggle Caffeine off/on again to acquire the lease. Settings → Closed-lid keep-awake also remains available. The helper defaults inactive at launch and is never registered by mocked services. Turning Caffeine off, timed expiry, or app shutdown releases the lease. The built-in panel still turns off when the lid closes.

## Privilege boundary

The bundled daemon is signed as `com.marcusyu.notchium.lid-awake`. Both XPC endpoints enforce Apple-anchored signing requirements with team `ZU27M973HX` and their exact peer identifier. Its interface accepts only renewal and release, with no caller-provided command, path, timeout, or executable. Signing-team changes must update `LidAwakeIdentity` and the Xcode signing configuration together.

The daemon runs `/usr/bin/pmset -a disablesleep 1` and verifies `SleepDisabled` before reporting success. This is a system-wide setting, **including manual Sleep**, not a public idle assertion or guaranteed cross-version clamshell API. Physical testing is required on each supported macOS/hardware combination. No privileged operation is performed by a SwiftUI view, shell interpolation, password capture, sudoers change, or private kernel API.

## Recovery

- One XPC connection owns the override. Other sessions cannot renew or release it.
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

The app's build phase compiles the daemon with Swift 6 and strict concurrency for each requested architecture, embeds it in `Contents/Library/HelperTools`, installs its plist in `Contents/Library/LaunchDaemons`, and signs it with the app's identity. The build phase omits the helper for `NOTCH_APP_STORE`.

`Helpers/LidAwakeTests/main.swift` tests the power adapter with an injected fake command runner and a temporary journal; it never changes system settings or requires root. Scenarios: acquire, idempotent renewal, release, foreign ownership rejection, unsafe-condition rejection, crash recovery, and failed restoration followed by retry.

Live validation still requires administrator approval and physical lid closure: test indefinite and timed Caffeine on AC and battery, Caffeine off, app exit, killed app, killed helper, expiry, and helper removal. Check `pmset -g` before/after. Do not treat a successful command or unit test as proof of physical lid behavior.
