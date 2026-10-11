# Native system feedback

Implemented October 10, 2026. Minimum deployment remains macOS 26 on Apple Silicon.
Live qualification used macOS **27.0.1 (26A434)**; macOS 26 hardware was not available.

## Feature matrix

| Feature | Native HUD suppressed? | Actual control works? | Permissions | Limitations |
|---|---|---|---|---|
| Volume | Active tap consumes eligible events; a downstream tap verified suppression for a synthetic built-in volume event. Visual Apple HUD absence and physical keys remain unverified. | One real built-in fine step and authoritative readback verified; deterministic normal/fine/repeat/boundary/channel tests pass. | Explicit Accessibility grant and event-post preflight; no paid signing. | Only outputs with readable, writable master or complete channel controls. Shift alone, Option alone, Command/Control, unsupported outputs pass through. |
| Mute | Active handling implemented. Physical-key and visible native-HUD suppression remain unverified. | Synthetic Bluetooth mute plus held repeat verified against actual HAL readback: one toggle. | Same independent mute capability check. | Outputs without writable mute pass the key through, even when volume replacement works. |
| Brightness | No; every brightness event passes through. | Public IOKit probe could not read a supported value on this machine; no writes attempted. | None added. | No replacement setting or fake level. macOS 26 built-in read/write qualification remains unavailable. External brightness is out of scope. |
| AirPods | No supported public banner-suppression mechanism identified. The Apple banner may also appear. | Available HAL endpoints and selected playback route are observed; no Bluetooth control or battery inference. | None added for connection feedback. | Physical Bluetooth link state is not independently observed. Live animation/banner, cross-device switching, and sleep/wake qualification remain required. |

## State owners and flow

`RealAudioDevicesService` remains the owner of the output list, selected route, volume/mute
truth, HAL listeners, and the single volume-key monitor. `CoreAudioOutputControls` is a
stateless adapter shared by existing UI commands and the key worker, not a second device
manager. It checks property existence/settable status, prefers a writable master, and
requires all output channels when falling back to channel controls. Volume is the maximum
actual channel reading; key operations preserve relative channel balance.

`SystemFeedbackCoordinator` owns the persisted `systemFeedback.replaceVolumeHUD` preference,
one cancellable status stream, and independent feature status. Default is off. The existing
application controller composes it from the same audio service and starts/stops it with Audio.
The Store profile has no active control boundary. No new dependency, helper, entitlement,
window, renderer, or activity ranking was added.

```
eligible key -> existing service's active tap -> serial Core Audio operation/readback
            -> AudioVolumeCommandEvent -> AudioFeatureModel.onHUD
            -> existing notifications/ActivityCoordinator -> existing shell
```

HAL notifications remain authoritative for ordinary passive changes. Active command events
also provide truthful feedback when hardware quantization leaves a value unchanged. The
existing HUD coalescing key, 1.75-second volume lifetime, expanded minor extension, boundaries,
priorities, geometry, and Reduce Motion behavior are reused. The passive command path writes
no audio. HAL and active command feedback may refresh the same coalesced activity; they do
not perform a second hardware operation or restart its shell geometry.

## Input safety and lifecycle

- One tap per service: passive session `listenOnly`, or active HID `defaultTap`. Only
  `NX_SYSDEFINED` auxiliary volume up/down/mute is decoded. General keyboard input is outside
  the event mask. Releases, other media keys, brightness, and unsupported modifiers pass unchanged.
- Default steps are 1/16; Option+Shift steps are 1/64. Shift alone retains native feedback
  sound behavior, and Option alone retains the Sound settings shortcut. Held volume repeats
  apply serialized steps. Held mute repeats do not toggle repeatedly.
- The callback checks eligibility, a mutex-protected capability/route gate, permission,
  copied-event ownership, and a bounded reservation (32 accepted events maximum). It performs
  no HAL I/O, UI work, or synchronous MainActor dispatch. The main run-loop owns tap/source
  creation and teardown; the serial worker owns mutable operation state.
- The worker reads capability/state before each operation and rechecks the selected route
  before each HAL property write and after readback. Requested values are never presented
  as readings. Logical fine steps can accumulate on quantized hardware only while fresh
  actual readback still matches the last operation; outside changes reset that target.
  If an existing mute property cannot be read, it rejects the operation before any write
  rather than treating that output as unmuted.
- Unsupported/unpermitted input passes through. Tap disable/timeout, queue exhaustion,
  operation failure, or permission loss immediately invalidates the gate. Main-thread
  reconciliation tears down the active tap and resumes passive observation where permitted.
  A failed active tap is not blindly reenabled. Route change, wake, or explicit Settings retry
  can qualify it again. Passive observation may itself be unavailable under platform policy;
  HAL-driven feedback continues.
  Failed passive creation is latched until route, activation, wake, or explicit retry;
  individual HAL volume changes do not continuously retry tap creation.
- An accepted event owns one copied `CGEvent`. Rejection/cancellation **before any write**
  can post that copy once at HID level. A synchronized single-use claim and reserved user-data
  marker prevent duplicate reposting and recapture. Accepted work/replays drain in queue order.
  A real synthetic stale-route test verified one marked event reaches a downstream session
  tap without a reposting loop.
- Any submitted write with failure/uncertain readback is not replayed: HAL may already have
  changed one channel or mute state. New keys immediately fall back to macOS. The failed intent
  may be incomplete; this avoids a duplicate action. If permission vanishes before replay,
  posting may be refused. Abrupt process death can lose accepted queued input. Native events
  passing during teardown/overflow may run before older queued replays. Those edge cases
  cannot be claimed as transactional delivery, and physical held-key qualification is still open.
- Sleep closes the tap and suppresses transient asleep snapshots; wake clears failure and
  rebuilds the current route. Stale HAL callbacks are generation-checked. Last stream removal,
  coordinator stop, and deinitialization release owned resources. No new polling loop or timer
  performs capability, Bluetooth, or permission scans.

## AirPods reliability

The existing connected/spinning/disconnected presentation is preserved. A transition tracker
uses stable HAL device UID, not temporary object ID, to combine wearable appearance followed
by output selection within the existing 2.5-second connection-activity lifetime. A later
deliberate route selection remains a new activity. Removal clears the deduplication record,
so rapid disconnect/reconnect still announces. Initial snapshots establish state without a
new connection announcement; stopping Audio resets the tracker.

The existing device adapter now filters unavailable HAL endpoints and listens for their
`kAudioDevicePropertyDeviceIsAlive` changes. Unavailable retained endpoints keep that listener,
so reconnect does not require an object-ID/device-list change. Selected output and available
endpoint state stay distinct. An available audio endpoint is not proof of universal physical
Bluetooth link state, pairing, or activity on another Apple device. No IOBluetooth manager,
continuous scan, or private AirPods battery/banner source was introduced.

The reviewed public surface did not provide a supported way to suppress Apple's connection
banner. No Control Center/SystemUIServer manipulation, notification database editing,
Accessibility click automation, masking, or process injection was added.

## Brightness findings

The read-only public IOKit probe searched `IODisplayConnect`, `AppleBacklightDisplay`, and
`AppleCLCD2`: zero matching services. Three `IOMobileFramebuffer` services existed, but
`IODisplayGetFloatParameter(..., kIODisplayBrightnessKey, ...)` returned **-536870201** and
left the sentinel **-1** unchanged for all three. A readable actual value was not established,
so `IODisplaySetFloatParameter` was not attempted and no supported range/readback was claimed.
Compiling the functions is insufficient evidence of hardware support.

The reference projects use private DisplayServices paths for Apple Silicon brightness.
Those are excluded here. Brightness remains unavailable independently of working volume,
and its fixture renderer was not repurposed as a hardware provider. Automatic brightness,
power transitions, fullscreen, topology changes, limits, and native-HUD appearance have no
replacement backend to qualify. Native brightness input remains untouched.

## APIs and reference review

Public APIs used: `CGEvent.tapCreate/tapEnable/tapIsEnabled`, `CGEvent.copy/post` and event
user data, `CFMachPort`/run-loop sources, `NSEvent` auxiliary-event decoding with public
IOKit HID constants, `AXIsProcessTrusted/AXIsProcessTrustedWithOptions`, event-post preflight,
Core Audio `AudioObjectHasProperty/IsPropertySettable/GetPropertyData/SetPropertyData`,
HAL property listeners, NSWorkspace sleep/wake, NSApplication activation, and UserDefaults.
The temporary brightness probe used public IOKit service matching and display parameter reads.

[BoringNotch](https://github.com/TheBoredTeam/boring.notch) and
[volumeHUD](https://github.com/dannystewart/volumeHUD) were reviewed for tap location,
media-key decoding, capability checks, and brightness feasibility. Implementation is independent;
no GPL code was copied and no third-party code/dependency was added. Relevant Apple surfaces:
[Core Graphics events](https://developer.apple.com/documentation/coregraphics/cgevent),
[Core Audio](https://developer.apple.com/documentation/coreaudio), and
[IODisplayGetFloatParameter](https://developer.apple.com/documentation/iokit/1574900-iodisplaygetfloatparameter).

## Validation evidence

Hardware tests are explicitly opt-in and restore original volume/mute state only while the
same output remains selected. They never request permission.

| Check | Actual result | Log in this session |
|---|---|---|
| Full package suite | 724 XCTest cases, four opt-in hardware skips, zero failures; five Swift Testing tests passed | `/tmp/notchium-feedback-all-tests-final.log` |
| Focused deterministic suite | 25 cases, three opt-in hardware skips, zero failures | `/tmp/notchium-feedback-focused-final.log` |
| Final focused suite with hardware opt-in | 26 cases, one built-in-only skip, zero failures; real mute/replay and service last-subscriber teardown passed | `/tmp/notchium-feedback-focused-hardware-final.log` |
| Settings UI regression | Passed: standard Settings shortcut, supported output toggle, education/cancel, preference stays off, no brightness toggle | `/tmp/notchium-feedback-ui-tests-final.log` |
| Free compile profile | Two Swift Testing checks passed with `NOTCH_FREE_DISTRIBUTION` | `/tmp/notchium-feedback-free-profile-tests.log` |
| Debug app build | Passed on arm64/macOS 27, deployment 26, including the final UI-test invocation | `/tmp/notchium-feedback-ui-tests-final.log` |
| Release app build | Passed with free-distribution flags, signing disabled during build, then local ad-hoc signing | `/tmp/notchium-feedback-release-free-build.log` |
| Release safety scripts | Five tests passed; source heuristic secret scan passed (242 files) | `/tmp/notchium-feedback-release-safety.log`, `/tmp/notchium-feedback-source-audit.log` |
| Artifact/DMG | App audit and strict signature passed; compressed DMG verified and mounted read-only; packaged app audited and copied to a temporary installation | `/tmp/notchium-feedback-artifact-audit.log`, `/tmp/notchium-feedback-mounted-audit.log`, `/tmp/notchium-feedback-dmg-final.log` |
| Installed release smoke | Earlier packaged build survived 20-second launch/sample and education/cancel. Final DMG app launched through native LaunchServices with collapsed shell, Audio Settings, replacement off, no brightness control, and normal quit | `/tmp/notchium-feedback-installed-launch.log` plus native UI observations |
| Whitespace | `git diff --check` passed | Command exit 0 |

The initial existing gear/reopen UI test failed while opening Settings; it was not changed.
The new settings test uses the standard shortcut, and the final run passed. Snapshot-render
tests retain existing FocusState warnings; Debug retains the existing App Intents metadata
warning. The installed binary smoke emitted a nonfatal sandbox-extension diagnostic while
remaining alive. Native UI observation briefly encountered a ScreenCaptureKit capture error;
AX state confirmed the Audio row action and subsequent education/cancellation succeeded.
These results do not establish fresh-user Gatekeeper or permission continuity.

Hardware evidence already obtained:

- Built-in speakers: a synthetic Option+Shift volume event was consumed before a downstream
  session tap, changed actual volume by exactly 1/64, and produced one readback command.
  The original channels/mute state were restored. Log: `/tmp/notchium-feedback-hardware-tests.log`.
- Bluetooth output: synthetic mute followed by a held repeat produced one actual mute toggle;
  stale-route rejection produced one marked replay reaching the session with no loop. Two
  tests passed; the built-in-only volume test skipped after the route changed to Bluetooth.
  Original state was restored. Log: `/tmp/notchium-feedback-hardware-final.log`.
- Final service lifecycle: real service reached active replacement without requesting a grant,
  then left active mode after the final command consumer was cancelled. This also verifies
  that status observation alone does not keep interception running. The final focused suite
  reran Bluetooth mute/replay: 26 cases, one built-in-only skip, zero failures.
  Log: `/tmp/notchium-feedback-focused-hardware-final.log`.
- These prove real control and event handling for synthetic input on this host, not physical
  key delivery or visual absence of the native Apple HUD.

Still required on real hardware: physical up/down/mute/holds/modifiers and boundaries;
native HUD visibility; permission denial/revocation during queued work; OS-induced tap
timeout; quit/relaunch and changed ad-hoc-build TCC continuity; supported USB/other Bluetooth
devices; macOS 26; live AirPods connect/disconnect/switch/sleep/wake/animation/banner;
fullscreen/Spaces and display topology. Deterministic gate/operation tests cover several
failure models, but are not a substitute for these checks. Fresh-user Gatekeeper override
and the separately documented Clipboard Keychain continuity remain release gates.

## CPU, memory, and wakeups

Each sample used `proc_pid_rusage` on the child app after five seconds of warmup, then a
15-second interval. CPU percent is CPU seconds / elapsed seconds / one logical core. Memory
is the final resident size/physical footprint. Wakeup columns are changes in Darwin interrupt
and package-idle counters; they are not an Instruments attribution of timer sources.

| Sample | CPU % | Resident MB | Footprint MB | Interrupt wakeups | Package-idle wakeups |
|---|---:|---:|---:|---:|---:|
| Before implementation, original mock fixture | 0.174 | 92.64 | 39.73 | 20 | 3 |
| After implementation, same mock fixture | 0.0007 | 116.83 | 37.77 | 8 | 0 |
| Real audio service, replacement off | 0.621 | 114.69 | 95.41 | 1,683 | 129 |
| Real audio service, confirmed active replacement | 0.570 | 113.97 | 95.22 | 1,576 | 322 |

The real-service pair used the same Debug build and explicit real-service fixture. Status logging
confirmed `disabled` and `activeReplacement` with no fallback. Launch arguments temporarily
selected the mode without saving a preference. Existing Spotify audio-meter capture ran in
these samples, accounting for substantial audio wakeups. The earlier before/after samples
spanned playback/output changes and concurrent Clipboard work, so their memory/CPU difference
cannot be attributed to this integration. Even the final pair is too short to establish a
regression or improvement; no precise incremental CPU/wakeup claim is made. These samples
preceded the final failure-path/lifecycle hardening; failure costs were not profiled. Longer controlled
traces remain useful. Inspection confirms no new idle polling, Bluetooth scanning, repeating
permission checks, or high-frequency timer was introduced.

Logs: `/tmp/notchium-feedback-baseline-probe.log`, `/tmp/notchium-feedback-after-probe.log`,
`/tmp/notchium-feedback-passive-idle-final.log`, `/tmp/notchium-feedback-active-idle-final.log`.

## Exact files in this change

Paths are repository-relative; this inventory includes files committed by another session
while this task was paused. This task did not issue any commit, tag, push, or publishing action.
Concurrent Clipboard source and recovery documentation were preserved.

| Directory | Files |
|---|---|
| `Notchium/` | `NotchiumApp.swift` |
| `NotchiumPackage/Sources/NotchiumAudioFeature/` | `AudioFeatureModel.swift`, `OutputDeviceState.swift` |
| `NotchiumPackage/Sources/NotchiumFeature/` | `NotchiumApplicationController.swift`, `NotchiumSettingsView.swift`, `Stage11Fixtures.swift`, `SystemFeedbackCoordinator.swift`, `SystemFeedbackSettingsSection.swift` |
| `NotchiumPackage/Sources/NotchiumServices/` | `AudioDevicesService.swift`, `CoreAudioOutputControls.swift`, `SystemFeedbackControl.swift`, `SystemVolumeKeyMonitor.swift`, `VolumeKeyOperation.swift`, `VolumeInputGate.swift`, `VolumeEventReplayGuard.swift` |
| `NotchiumPackage/Tests/NotchiumFeatureTests/` | `VolumeBoundaryHUDTests.swift`, `VolumeReplacementTests.swift`, `VolumeReplacementHardwareTests.swift`, `AirPodsTransitionReliabilityTests.swift` |
| `NotchiumUITests/` | `NotchiumUITests.swift` |
| `docs/` | `AUDIO.md`, `ARCHITECTURE.md`, `PERMISSIONS.md`, `SYSTEM_FEEDBACK.md` |
