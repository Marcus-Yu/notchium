# AirPods connection motion

Updated October 26, 2026. Applies to AirPods connection activities on macOS 26+,
including their compact and expanded inline presentations.

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
  informed the original bounded, event-driven turn. The current continuous turn uses a
  view-scoped SwiftUI animation timeline instead.

For additional primary visual research, the installed macOS Bluetooth banner product
movies were inspected locally. They show a rigid pair rotating through 360 degrees about
the vertical axis: stable center, upright stems, changing silhouettes, dark vents and
consistent studio lighting. Their source loops run for six seconds at 60 fps. That is
evidence of macOS product motion, not the current iPhone banner's spin or dwell timing.
Exact current iPhone angle/timing curves could not be measured from available sources.

The Notch adaptation rotates throughout the banner's visible lifetime: forward on
connection and backward on disconnect. A gentle 0.22-second acceleration reaches a steady
1.2-second revolution, with no pause at each full turn. A direction change preserves the
current pose and velocity, then reverses smoothly over 0.22 seconds. These timings are
product choices, not measured iPhone timing. The existing 2.5-second activity lifetime is
unchanged and can be refreshed by confirmed output events. The shell retains its existing
spring and reveal mask; the product's bounded scale follows that same reveal.
Dismissal keeps the artwork rotating while retained content retracts through the mask.
The AirPods exit uses a 0.4-second native smooth spring, or 0.6 seconds when returning
to Music so the earlier slot handoff still leaves a comparable visible flight. Product artwork glides inward,
shrinks gently and fades before the final hardware-mask cutoff; it finishes earlier when
Music is reclaiming the leading artwork slot. Other compact activities keep their existing
exit timing. Reduce Motion uses a stationary fade.

This follows the standard profile of the Apple SwiftUI interface and motion skills:
restrained motion, one owner of shell geometry, stable activity identity, and a static
alternative for Reduce Motion.

## Implementation

- `NotchAirPodsConnectionGlyph.swift` owns product frame selection and a view-scoped
  `TimelineView(.animation)` schedule. `NotchAirPodsMotion.swift` owns the independently
  sampled yaw and velocity model. It supports AirPods, AirPods Pro and AirPods Max. Other
  devices retain their existing symbol treatment and connection policy.
- `NotchAirPodsReveal.swift` projects inward travel, scale and opacity from the shell's
  interpolated reveal, using the same mapping for entry and exit to preserve the live
  presentation when a banner is dismissed early or reopened during retraction. The Music
  return policy stays stable while the media baseline is covered. It completes the fade
  before the retained row is removed, including
  the one-third reveal boundary used when Music returns. `NotchTransitionSurface` remembers
  the outgoing AirPods presentation's exit preset across expiry and equal-width swaps;
  the shell remains the only animation owner. No dismissal timer is added.
- `Resources/*Turn.png` contains original, approximate product illustrations authored with
  public SceneKit geometry. No Apple product movie, private resource path or downloaded
  imagery is used by the app.
- Each transparent sheet contains 61 frames of 96×96 pixels, from −360 to 0 degrees;
  the endpoint pose is identical to the first. Display size is 28 points within the
  existing collapsed row.
- ImageIO decodes only the requested model once. Immutable cropped images share the
  decoded sheet; each animation frame selects a prepared crop. Runtime needs no 3D
  scene, per-frame file access, wall-clock timer or sleeping task. The animation schedule
  exists only while the product is mounted, including the visible retraction; no idle
  schedule remains after removal.
- Motion uses `ContinuousClock` instants, so wall-clock adjustments do not change yaw.
  Sampling is pure and does not schedule work. A smoothstep velocity ramp is integrated
  into unwrapped yaw; retargeting samples the current pose and speed before changing
  direction. Same-direction updates leave the motion anchor intact, so repeated route or
  battery events cannot restart acceleration. Modulo frame selection and matching endpoint
  artwork make full turns seamless.
- A restored, still-visible activity resumes rotation without requiring a new connection
  event; the shell's existing introduction bookkeeping remains separate from product
  rotation. Reduce Motion immediately replaces the timeline with the static front pose
  and discards motion state. Disabling Reduce Motion starts rotation again for the
  currently visible banner. Disconnected artwork uses neutral 72% opacity, with a legible
  gray status label.
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
the HUD and compact activity. AirPods artwork rotates continuously while the banner is
visible, including when switching between two pairs of the same model with unchanged
artwork, label and coalesced banner ID. A same-direction update keeps the current turn
running; a connect/disconnect change smoothly reverses it. Explicit selection in Audio
clears only that device's pending appearance deduplication; feedback still waits for Core
Audio to confirm the new output. Automatic appearance/default-route callback pairs remain
coalesced, and unchanged snapshots do not restart motion.

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

### Refined exit validation: October 26

- 26 focused tests passed after the exit refinement, including native shell captures for
  connection and disconnection, both idle and returning to Music. Pixel measurements verify
  several intermediate fade frames, inward travel, and no remaining product at the end.
- Native early-dismissal and reopen-during-exit captures preserve product position and
  brightness at the reversal. Reduce Motion fades in place. Deterministic tests cover all
  three AirPods models at the battery, unknown-battery and disconnected widths, and confirm
  that the product is invisible before the existing retention boundary removes its row.
- Debug macOS app build succeeded with signing disabled. Captures are in
  `/tmp/notch-airpods-final-exit-captures`; the native capture test took 36.7 seconds.
  `git diff --check` passed. Physical AirPods pairing and compositor profiling remain unmeasured.

### Current validation: October 26, continuous rotation

- 26 focused package tests passed: continuous forward/reverse rotation beyond the banner
  duration, seamless turn poses, rapid reversal pose/velocity continuity, same-direction
  updates, artwork rendering, route reliability, compact geometry and introduction policy.
- The opt-in native shell capture test passed with synthetic audio events. Product-slot
  pixel comparisons confirm motion after 1.7 seconds on connection, coalesced and fresh
  disconnects, all three AirPods styles, Reduce Motion resumption and restored banners.
  It also checks static artwork while Reduce Motion is enabled and coordinator expiry.
  Captures: `/tmp/notch-continuous-airpods-captures`; the test took 25.6 seconds.
- Debug macOS app build succeeded using `Notchium.xcworkspace`, scheme `Notchium`,
  destination `platform=macOS`, signing disabled, and derived data at
  `/tmp/notch-continuous-airpods-dd`. XcodeBuildMCP tools were unavailable; the repository's
  CLI workflow was used.
- `git diff --check` passed. Hardware pairing and compositor frame pacing remain unmeasured.

### Historical validation: October 25, bounded-turn implementation

The results below describe the previous one-turn implementation. Its settlement,
restoration and Reduce Motion replay expectations have been superseded by continuous
rotation. These results are historical evidence, not validation of the October 26 change.

- macOS Debug app built with Xcode 27, workspace `Notchium.xcworkspace`, scheme `Notchium`,
  destination `platform=macOS`, deployment minimum unchanged at macOS 26. Signing disabled
  for the compilation check. XcodeBuildMCP tools were unavailable; the repository's CLI
  build workflow was used.
- Manual-switch validation: 57 focused tests passed, including AirPods event reliability, sleep/wake rendering,
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

### Current verification recipe

Run the focused checks and captures against the current implementation:

```sh
NOTCHIUM_AIRPODS_CAPTURE_DIR=/tmp/notch-airpods-captures \
swift test --package-path NotchiumPackage --disable-sandbox \
  --filter 'AirPodsConnectionAnimationTests|AirPodsConnectionVisualTests|AirPodsRetractionTests|AirPodsBatteryPresentationTests|CompactActivityTests|AirPodsTransitionReliabilityTests|Stage13DeviceBatteryTests|AirPodsSleepWakeTests|SleepWakeRenderingTests|Stage27A1UIQualityTests'
```

Remaining qualification: physical AirPods pairing, execution on macOS 26, and compositor
frame pacing/Instruments on supported hardware. Offscreen captures validate rendered
content and sequence, not display frame rate or energy. No Apple Fidelity score is
claimed without those runtime measurements.
