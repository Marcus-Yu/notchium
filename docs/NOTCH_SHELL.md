# Stage 2 Notch Shell

**Status:** Implemented shell contract

**Minimum OS:** macOS 26

Stage 2 implements one prioritized placeholder shell. It proves public display geometry, panel lifecycle, interaction state, native Liquid Glass, accessibility behavior, and deterministic test control. It does not implement pages, media, activities, permissions, Ambient Edge, Snap Zones, or any product provider.

## Selection and ownership

`NotchiumDisplayCoordinator` owns one `NotchiumPanelController` and one `DynamicIslandPresentationModel`.

1. Prefer the first display with `safeAreaInsets.top > 0` and valid left/right auxiliary top areas.
2. Otherwise use the display containing the pointer for a virtual pill.
3. Otherwise use the primary available display, then the first available display.
4. With no displays, hide the panel and leave the menu-bar fallback available.

`AppKitDisplaySource` is the only shell type that reads `NSScreen`. It converts screens to immutable `NotchiumDisplaySnapshot` values with stable Core Graphics display IDs. Feature and domain code do not retain `NSScreen` or use `NSScreen.main`.

Only one shell is active. Display identity or mode changes collapse it before immediate relocation. Screen-parameter, active-Space, display sleep/wake, and workspace activation notifications drive reconciliation. A built-in eligible notch continues to win when external displays are attached.

## Physical and virtual strategies

Physical mode derives `NotchHardwareGeometry` from the horizontal gap between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. Its vertical frame is always `display.frame.maxY - safeAreaInsets.top ... display.frame.maxY`. In collapsed physical mode, Notchium paints zero software pixels: the hardware obstruction supplies the entire visible black footprint. No padding, minimum shell size, menu-bar height, placeholder content, fake bridge, fallback model table, or inferred percentage width is added. A snapshot without both valid auxiliary areas is not treated as a physical-notch placement and uses the virtual strategy instead.

Virtual mode uses the same absolute top-center origin. Its width is 180 points. Height is `max(display.frame.maxY - display.visibleFrame.maxY, NSStatusBar.system.thickness)`. The closed virtual surface touches the absolute display top and remains inside the menu-bar-height region.

`NotchPanelLayout` keeps `hardwareNotchGeometry`, `collapsedVisibleFrame`, `collapsedHoverFrame`, `visibleSurfaceFrame`, and `panelFrame` explicit. The host panel remains a stable transparent `420 × 260` (or larger only when a supplied expanded size or collapsed footprint requires it), centered on the target display and anchored to its absolute top. Collapsed uses the exact physical/virtual footprint only as the visible-surface geometry. Hovered is at least `272 × 56`; expanded is `420 × 260`. These visible surfaces grow downward and horizontally outward from the top center while the host panel frame remains unchanged. In every state, `panelFrame.maxY == display.frame.maxY`.

## Panel lifecycle

`NotchiumPanelController` owns one borderless, nonopaque `NSPanel` with a clear AppKit background at status-bar level. It has no title, traffic-light controls, Dock presence, AppKit shadow, or painted AppKit background. Its fixed `NSHostingView` matches the panel, autoresizes in width and height, opts out of intrinsic sizing, and reports zero AppKit safe-area insets. SwiftUI fills that host but aligns the visible surface to the top and ignores the top safe area. Documented collection behavior keeps the panel available across Spaces and as a full-screen auxiliary surface.

Collapsed and hovered states do not become key and the panel ignores mouse events, so its transparent expanded-size area cannot block the desktop or menu bar. A global mouse-moved monitor compares `NSEvent.mouseLocation` against the collapsed hardware/virtual region expanded by five points on each side and five points below. The comparison includes the maximum X and Y boundaries, allowing the absolute display-top edge to participate. Expanded mode accepts mouse events, activates the app, and makes the panel key. Focus loss, Escape, close/toggle, display relocation, and Space changes collapse it. Expanded mode ignores pointer exit.

Screen-parameter changes trigger an immediate placement pass followed by a generation-checked correction after 0.5 seconds, accommodating delayed AppKit geometry updates after display and menu-bar changes without allowing stale corrections to win.

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

The physical closed state draws no software surface or content. The virtual closed state is an unadorned pure-black shape with no branding, stroke, glass refraction, or shadow. Hovered and expanded content receive public macOS 26 `glassEffect` inside one `GlassEffectContainer`, with a stable `glassEffectID` and deep-black tint. The top corners remain square at the screen edge and the lower corners carry the adaptive radius. Interactive glass is limited to actual controls; the expanded container uses noninteractive glass.

Reduce Transparency substitutes an opaque semantic background. Increase Contrast adds a restrained boundary. Reduce Motion changes both SwiftUI and AppKit timing. System light/dark appearance is automatic in production. The shell exposes explicit accessibility identifiers, labels, state values, keyboard close behavior, and a minimum useful control geometry.

## Debug and test fixtures

DEBUG builds expose one `NotchShellDebugModel` through the feature-composed Developer Panel. It can select live, built-in mock, or external mock displays; automatic, physical, or virtual placement; presentation state; appearance; motion; and transparency overrides. “Show Notch Geometry” outlines the transparent host panel, collapsed surface, and hardware frame. Runtime readouts and console diagnostics report the screen and visible frames, safe-area inset, both auxiliary areas, calculated hardware notch, collapsed surface, panel frame, and whether hardware-notch mode is active. Reset returns every value to automatic.

The same model parses DEBUG-only launch arguments for deterministic UI tests. Production feature flags cannot be unlocked by these settings, and release builds contain no Developer Panel surface.

Named previews and XCUITest fixtures cover physical/virtual collapsed, hovered, expanded, light/dark, reduced motion/transparency, long content, and small/large display contexts. Mocks verify policy and geometry but do not replace physical MacBook qualification.

## Extension points and limitations

Ambient Edge and Snap Zones remain documentation-only future extension points. Each requires an independent AppKit window, lifecycle owner, geometry model, and feature gate. Neither may stretch or repurpose the notch panel.

Public APIs do not grant ownership of the physical notch or guarantee identical behavior across every hardware, menu-bar auto-hide configuration, Space, full-screen application, Stage Manager arrangement, display scaling mode, clamshell transition, or sleep/wake cycle. Geometry is recomputed from each selected display and never borrowed from another display. Notchium does not sample screen colors or use fullscreen as a substitute for correct base geometry. The menu-bar fallback remains available in every configuration. Stage 2 requests no protected permission and implements no Stage 3+ behavior.
