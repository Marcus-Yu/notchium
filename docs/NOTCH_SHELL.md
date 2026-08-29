# Stage 2 Notch Shell

**Status:** Implemented shell contract

**Minimum OS:** macOS 26

Stage 2 implements one prioritized placeholder shell. It proves public display geometry, panel lifecycle, interaction state, native Liquid Glass, accessibility behavior, and deterministic test control. It does not implement pages, media, activities, permissions, Ambient Edge, Snap Zones, or any product provider.

## Selection and ownership

`NotchiumDisplayCoordinator` owns one `NotchiumPanelController` and one `DynamicIslandPresentationModel`.

1. Prefer the first eligible built-in display with `safeAreaInsets.top > 0`.
2. Otherwise use the primary available display for a virtual pill.
3. With no displays, hide the panel and leave the menu-bar fallback available.

`AppKitDisplaySource` is the only shell type that reads `NSScreen`. It converts screens to immutable `NotchiumDisplaySnapshot` values with stable Core Graphics display IDs. Feature and domain code do not retain `NSScreen` or use `NSScreen.main`.

Only one shell is active. Display identity or mode changes collapse it before immediate relocation. Screen-parameter, active-Space, display sleep/wake, and workspace activation notifications drive reconciliation. A built-in eligible notch continues to win when external displays are attached.

## Physical and virtual strategies

Physical mode derives the notch gap from `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. When those areas are absent, it uses a centered bridge based on the safe-area height and a clamped 15-percent display width. A black bridge represents the physical obstruction; the lower shell remains adaptive glass.

Virtual mode draws no hardware bridge. Its collapsed surface is `220 × 44` points and is flush with the display's absolute top edge.

Both modes anchor at display top-center in every presentation state: `panelFrame.maxY == display.frame.maxY`. The dedicated panel hosting view reports zero safe-area insets and the shell root ignores the inherited top container safe area because this panel intentionally owns explicitly computed notch geometry; feature content remains constrained by the shell's own layout. Physical collapsed size is `max(notchGap + 24, 240)` by `max(safeAreaTop + 10, 44)`. Hovered size is at least `272 × 56`. Expanded size requests `420 × 260` and clamps to 16-point horizontal and 32-point bottom margins. Layout values remain nonnegative on unusually small fixtures. DEBUG display fixtures are projected into the selected live screen's global coordinate space so simulated dimensions cannot displace the real panel.

## Panel lifecycle

`NotchiumPanelController` owns one borderless, transparent, nonactivating `NSPanel` at status-bar level. It has no title, traffic-light controls, Dock presence, or global input monitor. Documented collection behavior keeps it available across Spaces and as a full-screen auxiliary surface.

Collapsed and hovered states do not become key. Deliberate expansion activates the app and makes the panel key. Focus loss, Escape, close/toggle, display relocation, and Space changes collapse it. Expanded mode ignores pointer exit. A hosting view with an AppKit tracking area owns pointer entry/exit so panel resizing does not replace hover semantics.

## State and timing

`DynamicIslandPresentationModel` is the only presentation-state owner:

- `NotchStableState`: collapsed, hovered, expanded.
- `NotchPresentationPhase`: each stable state or `transitioning(from:to:)`.
- Hover entry delay: 120 milliseconds.
- Hover exit grace: 180 milliseconds.
- Collapsed/hovered transition: 180 milliseconds.
- Expansion/collapse: approximately 300 milliseconds.
- Reduce Motion: 120-millisecond simple resize/fade without overshoot.

The injected `AppClock` owns timing. Hover and transition tasks are cancelled when superseded; generation tokens reject stale completions.

## Liquid Glass and accessibility

The fully laid-out shell content receives public macOS 26 `glassEffect` inside one `GlassEffectContainer`, with a stable `glassEffectID`. A deep-black tint keeps the shell visually continuous with the hardware notch while preserving restrained system glass response. The top corners remain square at the screen edge and the lower corners carry the adaptive radius. Interactive glass is limited to actual controls: the collapsed/hovered shell control and expanded close control. The expanded container uses noninteractive glass and the panel adds a native shadow only while expanded.

Reduce Transparency substitutes an opaque semantic background. Increase Contrast adds a restrained boundary. Reduce Motion changes both SwiftUI and AppKit timing. System light/dark appearance is automatic in production. The shell exposes explicit accessibility identifiers, labels, state values, keyboard close behavior, and a minimum useful control geometry.

## Debug and test fixtures

DEBUG builds expose one `NotchShellDebugModel` through the feature-composed Developer Panel. It can select live, built-in mock, or external mock displays; automatic, physical, or virtual placement; presentation state; appearance; motion; and transparency overrides. Reset returns every value to automatic.

The same model parses DEBUG-only launch arguments for deterministic UI tests. Production feature flags cannot be unlocked by these settings, and release builds contain no Developer Panel surface.

Named previews and XCUITest fixtures cover physical/virtual collapsed, hovered, expanded, light/dark, reduced motion/transparency, long content, and small/large display contexts. Mocks verify policy and geometry but do not replace physical MacBook qualification.

## Extension points and limitations

Ambient Edge and Snap Zones remain documentation-only future extension points. Each requires an independent AppKit window, lifecycle owner, geometry model, and feature gate. Neither may stretch or repurpose the notch panel.

Public APIs do not grant ownership of the physical notch or guarantee identical behavior across hardware, menu-bar configurations, Spaces, full-screen applications, Stage Manager, display scaling, clamshell transitions, or sleep/wake. The menu-bar fallback therefore remains available in every configuration. Stage 2 requests no protected permission and implements no Stage 3+ behavior.
