# AirPods connection motion

Updated October 25, 2026. Applies to the compact connection activity on macOS 26+.

## Reference and design

The reference is the brief iPhone Dynamic Island connection confirmation: shaded white
product artwork on the leading side of a black surface, status/battery opposite, and a
fluid reveal/retraction. This is a different surface from the initial pairing sheet with
an open charging case and a Connect button.

Primary research:

- [Apple's Dynamic Island design session, around 8:19](https://developer.apple.com/videos/play/wwdc2023/10194/?time=499)
  shows the product artwork and explains coherent motion, optical padding and elasticity.
- [Apple's current AirPods setup guidance](https://support.apple.com/en-us/104989)
  identifies the separate initial pairing animation.
- [Apple's motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion)
  calls for purposeful motion and accessibility alternatives.
- [SwiftUI keyframe animation](https://developer.apple.com/videos/play/wwdc2023/10157/)
  supplies a bounded, event-driven sequence without timer coordination.

For additional primary visual research, the installed macOS Bluetooth banner product
movies were inspected locally. They show a rigid pair rotating through 360 degrees about
the vertical axis: stable center, upright stems, changing silhouettes, dark vents and
consistent studio lighting. Their source loops run for six seconds at 60 fps. That is
evidence of macOS product motion, not the current iPhone banner's spin or dwell timing.
Exact current iPhone angle/timing curves could not be measured from available sources.

The Notch adaptation uses a single 1.2-second forward turn on connection and a reverse turn
on disconnect, then rests for the remainder of the existing 2.5-second activity. The turn
eases in, carries through, and decelerates to a readable front pose. There is no planar
wobble or repeated loop. The shell retains
its existing spring and reveal mask; the product's small 0.92-to-1 scale follows that same
reveal. Dismissal retracts retained content through the existing mask.

This follows the standard profile of the Apple SwiftUI interface and motion skills:
restrained motion, one owner of shell geometry, stable activity identity, and a static
alternative for Reduce Motion.

## Implementation

- `NotchAirPodsConnectionGlyph.swift` owns product frame selection and native keyframes.
  It supports AirPods, AirPods Pro and AirPods Max. Other devices retain their existing
  symbol treatment and connection policy.
- `Resources/*Turn.png` contains original, approximate product illustrations authored with
  public SceneKit geometry. No Apple product movie, private resource path or downloaded
  imagery is used by the app.
- Each transparent sheet contains 61 frames of 96×96 pixels, from −360 to 0 degrees;
  the endpoint pose is identical to the first. Display size is 28 points within the
  existing collapsed row.
- ImageIO decodes only the requested model once. Immutable cropped images share the
  decoded sheet; each animation frame selects a prepared crop. Runtime needs no 3D
  scene, per-frame file access, wall-clock timer, sleeping task or idle display loop.
- A genuine connection/reconnection turns forward; disconnect turns back, including a fresh
  disconnect entry. Unwrapped yaw preserves the current pose and native keyframes preserve
  velocity when an event interrupts a turn. Whole-turn endpoint rounding is normalized so
  floating-point residue cannot swallow a subsequent turn. A restored activity begins at
  rest. Reduce Motion and removal destroy the animator immediately; disabling Reduce Motion
  keeps the front pose until another device event. Disconnected artwork uses neutral 72%
  opacity, with a legible gray status label.
- Reported AirPods battery uses a 10.5-point medium neutral-white percentage and a 14-point
  inset charge ring, with a center bolt when charging. Native system green indicates ordinary
  charge/charging and red indicates a displayed 20% or lower while not charging. The largest
  readout, 100%, measures 50×14 points within the 53-point content budget. Symmetric battery
  sides shrink from 86 to 72 points; other device and Mac power readouts retain their style.
  `NotchIncreasedContrast` reuses the shell's native preference and render override to
  strengthen labels and the ring track. The parent retains the spoken percentage/status.
- The existing button, spoken device name/status, notification coalescing, expiry,
  preemption and sleep/wake handling remain the owners of their behavior. Battery data
  still comes only from reported provider values.
- Missing or invalid resources fall back to the corresponding SF Symbol.

### Manual output switching

Confirmed output transitions carry a monotonic revision from `AudioFeatureModel` through
the HUD and compact activity. The renderer watches that revision and the stable device
UID, so switching between two pairs of the same AirPods model animates even when the
artwork, label and coalesced banner ID stay unchanged. Explicit selection in Audio clears
only that device's pending appearance deduplication; feedback still waits for Core Audio
to confirm the new output. Automatic appearance/default-route callback pairs remain
coalesced, and unchanged snapshots do not restart the turn.

### Live battery availability

The production `RealAudioDevicesService` currently reports no AirPods battery value. Core
Audio and the installed public `IOBluetoothDevice` SDK expose no documented precise AirPods
battery property. The public hands-free battery callback is a coarse phone/audio-gateway
indicator, not a precise earbud percentage; Core Bluetooth needs authorization and an
accessory-provided characteristic, with no documented AirPods battery guarantee. No reliable
small integration without another permission or private API was established in this pass.

The percentage UI therefore appears only for fresh provider-reported values; the live
adapter currently falls back to “Connected”. Mock capture values demonstrate layout, not
working hardware battery access. Disconnect never reuses the last known charge as live data.
References: [Core Bluetooth authorization](https://developer.apple.com/documentation/corebluetooth/cbmanager/authorization-swift.type.property),
[hands-free battery callback](https://developer.apple.com/documentation/iobluetooth/iobluetoothhandsfreedevicedelegate/handsfree(_:batterycharge:)),
and [Apple's native AirPods battery check](https://support.apple.com/en-la/119912).

Regenerate artwork on a Metal-capable macOS session:

```sh
swiftc scripts/generate-airpods-artwork.swift -o /tmp/generate-airpods-artwork
/tmp/generate-airpods-artwork
```

The generator uses supersampling and fixed lighting. GPU antialiasing can cause minor
edge-byte differences across regenerations; dimensions, poses and transparent bounds
remain stable. SceneKit is an authoring tool only, with no app runtime dependency.

## Validation

- macOS Debug app built with Xcode 27, workspace `Notchium.xcworkspace`, scheme `Notchium`,
  destination `platform=macOS`, deployment minimum unchanged at macOS 26. Signing disabled
  for the compilation check. XcodeBuildMCP tools were unavailable; the repository's CLI
  build workflow was used.
- Latest manual-switch validation: 57 focused tests passed, including AirPods event reliability, sleep/wake rendering,
  compact geometry, restoration policy, motion monotonicity and settlement, transparent
  asset bounds, matching endpoint poses, and actual SwiftUI artwork rendering at every
  quarter turn, reverse disconnect motion, interrupted turn continuity, endpoint rounding,
  0/5/20/100% layout, charging tone and actual increased-contrast ring rendering.
- Manual-switch regressions cover a selection immediately after appearance, system route
  changes among already available devices, stable banner identity, duplicate snapshots,
  and visible turns for same-model/different-UID and same-UID/new-revision events.
- An opt-in native-host test captured entry, the full turn, hold, disconnect, reconnect,
  Reduce Motion changed during rotation, dismissal and all three product styles. Pixel
  comparisons of the product slot verify rotation on coalesced and fresh disconnects and
  no replay after disabling Reduce Motion. The battery arc and shell mask settle independently.
- An independent native SwiftUI harness confirmed fresh/reconnect turns, still restoration,
  cancellation on removal, and no replay after disabling Reduce Motion.
- SwiftUI static scan of the product and readout: zero high findings. Six heuristic medium
  findings were reviewed: Reduce Motion is supplied explicitly from the shell, and the
  fixed fallback symbol, percentage, bolt and ring fit the existing fixed-height notch
  convention. The combined parent exposes the information to VoiceOver.
- `git diff --check` passed.

Reproduce the focused checks and captures:

```sh
NOTCHIUM_AIRPODS_CAPTURE_DIR=/tmp/notch-airpods-captures \
swift test --package-path NotchiumPackage --disable-sandbox \
  --filter 'AirPodsConnectionAnimationTests|AirPodsConnectionVisualTests|AirPodsBatteryPresentationTests|CompactActivityTests|AirPodsTransitionReliabilityTests|Stage13DeviceBatteryTests|AirPodsSleepWakeTests|SleepWakeRenderingTests|Stage27A1UIQualityTests'
```

Remaining qualification: physical AirPods pairing, execution on macOS 26, and compositor
frame pacing/Instruments on supported hardware. Offscreen captures validate rendered
content and sequence, not display frame rate or energy. No Apple Fidelity score is
claimed without those runtime measurements.
