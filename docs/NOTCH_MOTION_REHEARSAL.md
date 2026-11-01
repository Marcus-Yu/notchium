# Notch motion rehearsal

## Direction and sources

November 1, 2026. The project-local `stageshow` skill is installed from
[`benjitaylor/skills`](https://github.com/benjitaylor/skills/tree/main/stageshow),
with its content hash recorded in `skills-lock.json`.

The [author's workflow](https://benji.org/stageshow) and the skill's
`references/motion.md`, `references/rehearse.md`, and `examples/dynamic-island`
inform this pass. The relevant reference is one persistent black shape with
independent, full-size content, interrupted motion continuing from its current
presentation, stable control footprints, and reviewing intermediate frames.
The React kit and browser filming scripts do not run native SwiftUI views;
this pass applies those principles to the existing implementation and uses
native hosting captures instead. No React runtime or animation dependency was added.

Apple's [scoped animation documentation](https://developer.apple.com/documentation/swiftui/view/animation(_:body:))
supports limiting animation to the visual modifiers that actually change.

## Behavior

- Main opening and closing retain the established 0.40 response / 0.80 damping
  spring, fixed panel, black gate, full-size pages and geometry-based reveal.
  Changing Reduce Motion settles an active spring and rejects its old completion.
  Once content reveals at 75% height, its scoped control feedback remains
  available during the remaining spring tail; inherited geometry animation is
  still cleared.
- Page selection uses the same scoped fade through black for clicks, swipes and
  accessibility navigation: 80 ms exit followed by 120 ms entry, shortened to
  40 ms exit and 60 ms entry with Reduce Motion. Incoming opacity waits for the
  outgoing layout to clear, preventing doubled artwork and controls. Hidden pages
  remain mounted, disabled and hidden from accessibility; feature visibility
  callbacks still update immediately.
- Track changes update title and artist in their existing slots. The waveform
  no longer loses its identity with every track ID. Home keeps its metadata in a
  fixed 72 pt lane (56 pt compact), with a close title/artist pair and spare space
  below. Short and two-line titles retain the same progress/transport positions.
  Native tooltips expose the full title and artist when either truncates.
- Artwork crossfades belong to the mounted view and honor Reduce Motion.
  Asynchronous loading does not inject an animation transaction into model updates.
- Slider fill and thumb coordinates follow pointer, seek and playback values
  directly. Only track thickness, thumb appearance and control feedback animate.
  A fixed thumb slot keeps its center stationary while it grows on interaction.
- `NotchMotionStyle` supplies 160 ms smooth control feedback, 220 ms smooth
  content changes and 100 ms reduced feedback. Shell, notifications and page
  geometry retain their distinct existing timing.
- Search hover/focus animates its fill and ring; typing and clear-button layout
  stay direct. Header, media and Shelf controls share feedback timing.
  Thumbnails and notification replacement explicitly honor Reduce Motion.

Playback commands, optimistic seeking, provider reconciliation and the 10 Hz
visible-playing progress schedule retain their existing ownership. Paused,
hidden and seeking bars do not gain a continuous animation timer.

## Rehearsal

Use the opt-in `NotchMotionRehearsalTests` with `NOTCHIUM_MOTION_CAPTURE_DIR`
set to a local output directory. Its snapshots use real SwiftUI views with
mock media and no production-service startup. Review opening, closing,
reversal, page switching, track changes and reduced motion at actual size.
Frame timestamps describe capture intervals, not display refresh performance.

```sh
NOTCHIUM_MOTION_CAPTURE_DIR="$PWD/dist/motion-rehearsal" \
  swift test --package-path NotchiumPackage --filter NotchMotionRehearsalTests
```

This capture is synthetic native-host evidence. It does not establish live
Spotify propagation, pointer/trackpad feel, fullscreen/Space timing, or a real
60 fps recording on a built-in notched display. Those remain hardware acceptance
checks described in [the shell contract](NOTCH_SHELL.md).

## Validation

- `swift build --package-path NotchiumPackage --target NotchiumMediaFeature`
  passes, including its Design System and Dynamic Island dependencies.
- 135 focused regressions pass with zero failures and no skips. These cover
  shell geometry/interruption, revealed control feedback, navigation ownership,
  slider/progress behavior, paused seeking, transport, audio lifecycle and waveform
  presentation. Because the app composition currently does not compile, these
  ran in a temporary Swift package symlinking the unchanged production targets,
  existing test files and their existing fixture helpers. No app manifest or AI
  source was changed for verification.
- The opt-in native rehearsal passes in both modes: 180 snapshots each, 360 total.
  The reviewed contact sheets show fixed media/control positions through title
  changes, direct track-progress resets, the black opening/closing gate and
  reversals. PNG capture overhead makes this a sparse rehearsal, not complete
  per-refresh coverage: median in-beat samples are approximately 80 ms, with
  maximum gaps of 228 ms (standard) and 352 ms (reduced).
- Final whitespace validation (`git diff --check`) passes.
- The full package test build is blocked by the pre-existing non-exhaustive
  `AIWindowContextError.contextMessage` switch in
  `NotchiumAIFeature/AIWindowContextError+Message.swift:5`, which lacks
  `.windowValidationFailed(_)`. Full app validation remains pending that fix.

Local review artifacts (generated under ignored `dist/`):

- [Standard shell contact sheet](../dist/motion-rehearsal-final/standard/summary-shell.png)
- [Standard media contact sheet](../dist/motion-rehearsal-final/standard/summary-media.png)
- [Reduced shell contact sheet](../dist/motion-rehearsal-final/reduced/summary-shell.png)
- [Reduced media contact sheet](../dist/motion-rehearsal-final/reduced/summary-media.png)
- [Standard animated rehearsal](../dist/motion-rehearsal-final/standard/motion.gif)
- [Reduced animated rehearsal](../dist/motion-rehearsal-final/reduced/motion.gif)

## Unslop implementation follow-up

The [approved visual refinements](UNSLOP_VISUAL_REVIEW.md#approved-implementation)
are implemented. All 139 focused tests, including updated normal/reduced capture,
pass with no skips, and the production media target rebuild passes. The new
rehearsal has 198 frames per motion mode and includes rapid page reversals.
Updated [normal](../dist/unslop-implementation/standard/motion.gif) and
[reduced](../dist/unslop-implementation/reduced/motion.gif) previews supersede
the older crossfade/title-spacing examples for those behaviors. Full package
compilation remains blocked by the same unrelated AI switch error above.
