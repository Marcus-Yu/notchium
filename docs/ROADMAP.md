# Notchium Roadmap

**Status:** Stage 2 complete; Stage 3 gated

**Last reviewed:** 2026-08-28

This roadmap preserves the accepted Stage 1 architecture and prevents later presentation work from leaking into Stage 2. A stage begins only after the preceding stage's documented acceptance gates pass. Experimental items may be removed without blocking the core product.

## Completed

### Stage 0 — Feasibility and engineering contract

Defined the product, public-API limits, distribution profiles, permissions, privacy, testing, and engineering rules.

### Stage 1 — Production architecture skeleton

Created the native Swift/SwiftUI shell, feature-oriented targets, service protocols with real/mock seams, dependency injection, deterministic infrastructure, feature flags, diagnostics, unit/UI test targets, and the built-in-notch panel skeleton. Stage 1 is frozen except for separately approved defects.

### Stage 2 — Notch shell, display geometry, and Liquid Glass

Implemented one prioritized shell panel with built-in-notch selection, a virtual-pill fallback, menu-bar access in every configuration, deterministic geometry and interaction timing, documented Spaces/sleep/display lifecycle handling, native macOS 26 Liquid Glass, accessibility fallbacks, debug fixtures, previews, and focused unit/UI coverage. No product provider, permission, Ambient Edge, Snap Zone, or Stage 3+ feature behavior was introduced.

## Planned stages

### Stage 3 — Activity coordination, pages, onboarding, and shared interaction

Implement typed activity events, `ActivityCoordinator`, priority/coalescing/expiry/privacy policies, page customization foundations, permission-aware onboarding, and shared interaction rules. Present through the notch and menu fallback only.

### Stage 4 — Media Center

Implement MusicKit and Spotify provider adapters, capability-aware controls, metadata/artwork state, queue limits, and the authorized audio-meter seam. Spotify audio-derived waveform remains policy-disabled. Preserve a future `LyricsProvider` boundary without promising synchronized lyrics.

### Stage 5 — Calendar and meetings

Implement EventKit upcoming events, countdowns, recognized Zoom/Meet/Teams links, Join/open behavior, reminders, and app-owned meeting activities. Do not add generic call control.

### Stage 6 — Shelf, screenshots, downloads, and OCR

Implement app-managed temporary copies, drag/drop, sharing, explicit folder access, best-effort screenshot/download inference, and local Vision OCR. Preserve originals and confidence semantics.

### Stage 7 — Core utilities, clipboard, and focus

Implement Caffeine, fail-open Keyboard Cleaning Lock, privacy-gated Clipboard History, Pomodoro, app tracking, optional browser extensions, retention, and neutral statistics.

### Stage 8 — Audio devices and experimental per-application audio

Implement public audio-device enumeration, default-output changes, writable volume, route inference, and capability-probed per-application audio experiments. No private AirPods controls or universal mixer claim.

### Stage 9 — Snap Zones

Implement the direct-distribution window-management experiment through public Accessibility APIs, deterministic zone models, keyboard/mouse invocation, failure recovery, and typed presentation feedback. Keep Accessibility work outside presentation windows.

### Stage 10 — System monitoring

Implement truthful CPU/RAM/aggregate-network totals and accessible process CPU/RAM. Continue to omit global GPU and per-process network claims.

### Stage 10.5 — Battery and enhanced system context

Implement public battery/charging/condition/adapter information and parallel enhanced HUD activities. Charge limiting, keyboard brightness hacks, global microphone mute, and system HUD suppression remain deferred/prohibited.

### Stage 11 — Dynamic Mac Island integration

Integrate approved feature events through `ActivityCoordinator`, privacy redaction, important Notchium-owned banners, page policy, and app-owned Dynamic Mac Island presentations. Apple's HUDs and privacy indicators remain visible.

### Stage 11.5 — Ambient Edge

Purpose: add a restrained optional display-edge presentation after activity, media, and Snap semantics are stable and before final visual polish.

- Add a dedicated Ambient Edge presentation module and a separate click-through AppKit overlay per selected display.
- Route immutable presentation state only from `ActivityCoordinator`; prohibit feature/provider access.
- Implement Off and Static first, then bounded Slow/Ambient modes.
- Add local artwork-palette extraction, custom color/gradient, intensity, thickness, and response-strength settings.
- Reuse Dynamic Mac Island priority, coalescing, expiry, privacy, and important-banner decisions.
- Integrate Snap feedback from typed presentation state without Accessibility access in the renderer.
- Add manual Pause, per-application exclusions, and conservative best-effort suppression for full-screen/presentation/screenshare contexts.
- Implement multi-display selection and lifecycle; keep the Stage 2 shell and external edge policies independent.
- Respect Reduce Motion, Reduce Transparency, Increase Contrast, display sleep, session lock, and Low Power Mode.
- Profile CPU, GPU/frame pacing, wakeups, and energy before enabling any persistent animation. Metal requires evidence and an ADR.
- Evaluate Beat Reactive last as a direct-distribution experiment using the shared authorized meter. Keep it unavailable for Spotify without written clearance.

### Stage 12 — Final polish, accessibility, performance, and release engineering

Complete Apple-quality interaction polish, localization, VoiceOver/keyboard testing, reduced-motion/transparency behavior, performance and energy budgets, hardware matrices, direct notarization, reduced Store-profile evaluation, privacy disclosures, and release evidence.

### Stage 13 — V1.x Shortcuts and App Intents

Expose deliberate public App Intents for safe existing actions. Each intent inherits the in-app capability, permission, privacy, failure, and distribution contract; no intent silently broadens access.

## Cross-stage gates

- No private/undocumented API, shell utility, silent recording, arbitrary Notification Center reader, cloud activity storage, or unsupported universal claim.
- No feature moves forward without real/mock/denied/unavailable/failure scenarios and deterministic tests appropriate to its boundary.
- No persistent animation or sampler ships without measured CPU/GPU/energy evidence and lifecycle cancellation tests.
- Spotify audio-derived visualization requires written policy clearance.
- The Stage 2 virtual pill is approved only as the shell fallback. Ambient Edge does not imply additional pill surfaces, and neither surface authorizes the other.
