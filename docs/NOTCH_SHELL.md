# Stage 2 Notch Shell

**Status:** Stage 2 polish implemented; hardware motion acceptance remains pending.

**Minimum OS:** macOS 26. **Target:** built-in notched MacBook only.

Stage 2 implements the shell and placeholder content only. No Stage 3 providers, permissions, external-display shell, private APIs, or custom animation engine are enabled.

## Display and panel ownership

`AppKitDisplaySource` reads public screen geometry into immutable snapshots. `NotchiumDisplayCoordinator` selects only a built-in display with valid auxiliary top areas and a positive notch gap. When none exists, it hides the panel; the menu-bar fallback remains available. Existing virtual geometry helpers and explicit DEBUG overrides remain fixtures, not live external-display support.

The measured hardware footprint, screen coordinate calculations, expanded dimensions (450 × 190 pt), and fixed transparent host (640 × 210 pt) are unchanged. `NotchiumPanelController` positions the host only when display identity or screen frame changes. It never animates the NSPanel frame. The top edge remains at the absolute screen top.

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
- Both hover and click use `Animation.spring(response: 0.60, dampingFraction: 0.88, blendDuration: 0.10)` in both directions.
- Reduce Motion uses a native 0.18 s ease-in-out transition, including explicit DEBUG overrides.

Injected clock tasks track hover delays and presentation phase. Cancellation and generation checks reject stale completions; input remains enabled during motion, and SwiftUI retargets the existing shape. Phase timing is bookkeeping, not a frame loop.

Hover and pinned presentations share content. A cancellable view task waits 170 ms after opening before starting a 0.18 s opacity fade. Closing starts an 0.08 s opacity fade immediately, without a delay. Content never scales or slides, and pinning an already-hovered shell does not replay its reveal.

## Validation and acceptance

Regression tests cover timing, pin persistence, timer cancellation, repeated pointer movement, click toggling/outside dismissal, Escape, Reduce Motion, empty passive shape, continuously top-anchored shape geometry, fixed dimensions, display selection, and Space notification behavior.

These tests do not certify visual acceptance. The release gate is a real 60 fps recording on a built-in notched MacBook of passive → hover → expanded → collapse, plus click opening/closing, mid-animation reversal, fullscreen hover, and three-finger Space swipes. Inspect every frame for a separate software notch and horizontal drift. Do not mark PASS from geometry tests, mocked displays, still screenshots, or a synthetic animation recording.
