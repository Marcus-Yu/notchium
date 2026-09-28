# Stage 2 Notch Shell

**Status:** Stage 2 polish implemented; hardware motion acceptance remains pending.

**Minimum OS:** macOS 26. **Target:** built-in notched MacBook only.

Stage 2 implements the shell and placeholder content only. No Stage 3 providers, permissions, external-display shell, private APIs, or custom animation engine are enabled.

## Display and panel ownership

`AppKitDisplaySource` reads public screen geometry into immutable snapshots. `NotchiumDisplayCoordinator` selects only a built-in display with valid auxiliary top areas and a positive notch gap. When none exists, it hides the panel; the menu-bar fallback remains available. Existing virtual geometry helpers and explicit DEBUG overrides remain fixtures, not live external-display support.

The measured hardware footprint, screen coordinate calculations, fixed transparent host (740 × 322 pt), and panel positioning are preserved. Music, Calendar, and Audio share the 524 × 266 pt expanded shell, 12 pt physical top corners, and 26 pt bottom corners defined by `ExpandedNotchLayout` in `NotchPanelLayout.swift`. Navigation stays 32 pt high across pages. All four pages use `ExpandedPageStyle` for their interior rhythm: 30 pt horizontal inset, 8 pt top inset and 12 pt bottom safe zone. Music uses a 76 pt artwork/metadata/progress composition, a compact native 20 pt Player/Up Next picker, a centered 32 pt transport row, and a separate volume/output row. Calendar uses whitespace between its columns; Audio constrains its system slider row so two mixer rows remain usable. See [expanded page composition](EXPANDED_PAGE_COMPOSITION.md). `NotchiumPanelController` positions the host only when display identity or screen frame changes. It never animates the NSPanel frame. The top edge remains at the absolute screen top.

`NotchPanel` is borderless, nonopaque, non-key, clear, shadowless, nonactivating, and uses `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, and `.ignoresCycle`. Space-change notifications first call the existing `collapse()` method, which cancels pending hover timers and uses `setExpanded(false)` to close hovered or pinned presentations with the normal animation. They then reassert the existing panel without selecting another display, recreating it, or repositioning it. The shell remains passive until fresh hover entry or a click. Fullscreen uses the same panel contract.

`NSWorkspace.activeSpaceDidChangeNotification` reports a Space change; Apple does not guarantee notification delivery at the beginning of the three-finger gesture. Collapse starts on notification delivery. First-frame swipe timing requires hardware verification.

## One continuous surface

One persistent `NotchShape` interpolates width, height, shoulders, and bottom radius with SwiftUI's native animation system. Its top never moves. There is no shell scale transform, view replacement, crossfade, popup, or AppKit frame animation.

The measured hardware rectangle is permanently subtracted from the drawable path, including its content clip. At the passive endpoint the drawable path is empty: no black overlay, chin, text, icon, reflection, or shadow remains. The invisible pointer target retains the existing hardware region and five-point input tolerance. DEBUG geometry outlines are also suppressed in passive mode.

Expansion reveals the shape's growing perimeter directly around the hardware footprint. The black fill remains dominant. One restrained native glass surface sits inside the expanded content, with an opaque fallback for Reduce Transparency. Content has a fixed expanded layout below the hardware region, avoiding resize-induced text movement.

## Interaction and motion

`DynamicIslandPresentationModel` owns collapsed, temporarily hovered, and pinned-expanded states. Pointer-region edges drive timers; movement inside a region does not continually restart them.

- Hover entry: 120 ms.
- Hover leave grace: 200 ms.
- Click: pin immediately; second click collapses.
- Pinned ignores pointer exit; outside click and Esc collapse.
- Both hover and click use one symmetric `interactiveSpring(response: 0.40, dampingFraction: 0.80, blendDuration: 0)` on shell geometry only. Pinning an already hovered shell does not start another morph.
- Reduce Motion uses a native 0.12 s ease-out geometry transition, including explicit DEBUG overrides; media remains opaque.

Injected clock tasks retain interaction/hover bookkeeping (400 ms nominal). They do not reveal content. The persistent SwiftUI `NotchTransitionSurface` owns a separate visual state machine: collapsed → openingBlack → expanded → closingBlack → collapsed. Every new geometry target hides content synchronously, before the shell begins moving. On opening, expanded content appears at 75% of the height expansion and is clipped to the current animated shell, at its full final size. Closing content stays hidden until SwiftUI's `.removed` animation completion, including the spring tail. Generation tokens reject completions from superseded targets; input remains enabled and reversal retargets the existing spring.

The black shape alone receives animated width, height, center, corner radius and auxiliary geometry. Expanded and collapsed content remain separately mounted at their intended dimensions, with no scale, positional retraction, matched geometry or fade. A binary visibility mask hides actual content; this is not a cover over an animated page. The content clip follows the interpolated shell geometry; the page layout itself stays fixed. Child animation transactions are suppressed while black, while normal open-page control animations remain available after settling. All pages share this gate, including utilities, reminders and compact HUD content. Root-host updates no longer inject animation transactions. The NSPanel frame remains stable.

Content hide and reveal are immediate (0 ms); opening reveal is geometry-based rather than delayed until spring completion. Reduce Motion retains the black choreography with 0.12 s ease-out shell geometry. Services continue receiving target-state visibility changes, never per-frame animation progress.

Motion reference: [current BoringNotch ContentView](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift), inspected September 25, 2026. The reference uses a shared interactive spring (response 0.38, damping 0.8) and separate open/close springs (0.42/0.8 and 0.45/1.0). Notchium independently implements the requested symmetric 0.40/0.80 spring and black-only choreography. No GPL source was copied.

## Validation and acceptance

Regression tests cover timing, pin persistence, timer cancellation, repeated pointer movement, click toggling/outside dismissal, Escape, Reduce Motion, empty passive shape, continuously top-anchored shape geometry, fixed dimensions, display selection, and Space notification behavior.

These tests do not certify visual acceptance. The release gate is a real 60 fps recording on a built-in notched MacBook of passive → hover → expanded → collapse, plus click opening/closing, mid-animation reversal, fullscreen hover, and three-finger Space swipes. Inspect every frame for a separate software notch and horizontal drift. Do not mark PASS from geometry tests, mocked displays, still screenshots, or a synthetic animation recording.

Black-transition regression coverage includes stale completion rejection, repeated reversals, full-size opaque endpoint content, and 60 Hz sampled raster invariants across sampled shell sizes. These are synthetic samples, not a live capture. The current computer-use interface exposes still screenshots but no video recording API; live 60 fps acceptance remains unverified.

## Stage 9 notification geometry

Calendar and Audio now use the shared notification target in the persistent
`NotchTransitionSurface`. Its geometry has independently animatable 12 pt concave
shoulders and 34 pt lower corners. Calendar content is 88 pt tall; Audio is 56 pt.
Notification geometry uses response 0.26 / damping 1.0 on entry and response 0.20 /
damping 1.0 on exit, with blend duration zero. This overrides neither the main
0.40 / 0.80 expansion spring nor the canonical 524 × 266 expanded size.
Content reveals at 75% of height growth at its final dimensions. Notification-to-
notification resizing retains content under the live shape mask; equal-size replacement
uses a 100 ms opacity transition. Dismissal hides content immediately before contraction.
The target-shape mask was removed: only interpolated presentation geometry clips content,
so reversals cannot prematurely crop to a closing endpoint.
See [Unified notifications](STAGE9_NOTIFICATIONS.md) for ownership and validation.

## Stage 10 activity and gesture coordination

Notification transitions preserve the persistent media row independently of the content
reveal gate. Main expand/collapse still uses the established black gate. Expanded
notifications hide while the full shell is open and expire independently;
pages remain mounted and selected. Horizontal page navigation now receives native phased
scroll events only in the empty navigation area, replacing the full-page event monitor.
Source-keyed auxiliary retention protects native menus and the Spotify picker, and Escape
defers to children. See [Stage 10 coordination](STAGE10_COORDINATION.md) for current
priority, restoration, gesture thresholds, Reduce Motion, review findings, and test results.

## Icon-only header refinement

The 32 pt header contains Home, Music, Calendar and Audio on the left, using 28 pt
circular SF Symbol buttons. Neutral selected background and outline, native help text and VoiceOver
labels identify each page. Caffeine, Quick Reminder and Settings form the right utility
group, with an 18 pt gap before Close. The center remains the empty page-swipe region.
Caffeine colors and its 0.75-second hold ring, canonical dimensions,
and the main black-shell spring are unchanged.

Notification defaults are centralized in `NotchNotification.Kind.defaultDuration`:
Calendar 5 s, output changes 2.5 s, volume/mute 1.75 s. `NotificationCoordinator`
owns `createdAt`/`expiresAt` and one cancellable task per accepted update. Meaningful
Audio updates coalesce with stable identity and refresh expiry; duplicate snapshots do
not. Calendar reminders have discrete identities. No hover, drag, page selection or
expand/collapse operation changes the deadline. The normal activation area always wins.
