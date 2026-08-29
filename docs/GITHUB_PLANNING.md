# GitHub Planning — Stage 2 Reconciliation

**Status:** Stage 2 dependency satisfied; later issue briefs retained

**Last reviewed:** 2026-08-28

GitHub was not modified during this amendment because no authenticated GitHub CLI, token, or writable GitHub connector was available in the workspace. The following issue text is ready to create without granting this documentation task external authority. Labels and milestones are proposals and must be reconciled with repository metadata when GitHub access is available.

## Milestone proposal

| Milestone | Scope |
|---|---|
| Stage 2 — Shell Foundations | Complete: prioritized physical-notch/virtual-pill shell and menu fallback |
| Stage 8 — Audio | Audio devices and experimental per-application audio |
| Stage 9 — Window Management | Snap Zones direct-distribution experiment |
| Stage 10.5 — System Context | Battery information and enhanced HUD activity sources |
| Stage 11 — Activities | Dynamic Mac Island coordination and important owned banners |
| Stage 11.5 — Ambient Edge | Optional display-edge presentation layer |
| V1.x — Automation and Content | App Intents and any licensed lyrics provider work |

## Issue: Add optional Ambient Edge presentation layer

**Milestone:** Stage 11.5 — Ambient Edge

**Suggested labels:** `feature`, `macos`, `presentation`, `experimental`, `performance`, `privacy`

### Purpose

Add a GPU- and energy-conscious, optional display-edge layer that extends selected `ActivityCoordinator` presentation state. This is not an RGB utility, system HUD replacement, notification reader, or second feature-event pipeline.

### Dependencies

- Stage 2 shell/display lifecycle accepted.
- Stage 3 `ActivityCoordinator` and typed presentation state accepted.
- Stage 4 media/artwork identity and optional authorized meter seam accepted.
- Stage 9 typed Snap feedback accepted.
- Stage 11 Dynamic Mac Island priority, coalescing, expiry, privacy redaction, and important-banner policy accepted.

### Scope

- Separate click-through, nonactivating overlay per selected display.
- Off, Static, Slow, Ambient, and gated Beat Reactive modes.
- Album-art-derived local palettes and custom color/gradient, intensity, thickness, and response strength.
- Coordinator-owned important pulse and Snap feedback.
- Multi-display selection; the Stage 2 physical-notch/virtual-pill shell remains independent from every edge overlay.
- Manual Pause, per-app exclusions, and conservative best-effort suppression.
- Accessibility and low-power fallbacks.

### Out of scope

- Feature/provider access from the renderer.
- Stretching the notch panel.
- Arbitrary Notification Center reading.
- Exact full-screen-video/presentation/game/screenshare detection.
- Silent/automatic audio capture or persisted PCM.
- Spotify audio-derived effects without written policy clearance.
- Private display, WindowServer, MediaRemote, Bluetooth, SMC, or HUD APIs.

### Acceptance criteria

- [ ] Basic overlay requires no TCC permission and is Off by default.
- [ ] Normal mode is click-through, nonactivating, and cannot block app/system controls.
- [ ] Each selected display has independent create/update/teardown behavior under hot-plug, sleep/wake, clamshell, Spaces, Stage Manager, and session lock.
- [ ] Static mode has no persistent frame loop; all animation stops with no eligible state.
- [ ] Presentation consumes immutable, redacted state from `ActivityCoordinator` only.
- [ ] Album palette extraction occurs once per artwork identity and passes contrast/color-space tests.
- [ ] Reduce Motion, Reduce Transparency, Increase Contrast, and color-independent signaling pass.
- [ ] Low Power Mode disables Beat Reactive and downgrades continuous animation.
- [ ] Manual Pause and per-app exclusions work even when automatic suppression cannot classify context.
- [ ] Beat Reactive reuses one explicitly authorized `AudioMeterProvider`; denial/revocation tears down first and downgrades safely.
- [ ] Spotify audio reaction remains compile-time/policy disabled without written clearance.
- [ ] Unit, integration, UI, multi-display hardware, revocation, lifecycle, and accessibility tests pass.
- [ ] Instruments evidence records CPU, GPU/frame pacing, wakeups, and energy on representative single- and multi-display hardware.
- [ ] No private API, shell command, cloud payload, raw audio persistence, or sensitive logging is introduced.

### Open risks

- Window ordering and suppression across full-screen apps, Spaces, Stage Manager, and system alerts.
- No universal public signal for full-screen video, games, presentations, or third-party screen sharing.
- Mixed refresh rate/HDR/color-space frame pacing and palette behavior.
- Appearance-only System Audio Recording may not justify permission or Store review cost.
- Spotify policy clearance and process-targeting reliability.

## Other approved issue briefs

### Experimental per-application audio

Use public Core Audio process/device capabilities behind `AudioProcessProvider`; capability-probe, require System Audio Recording only for capture, support real/mock/denied/unavailable/failure, and never promise a universal mixer. **Milestone:** Stage 8. **Labels:** `audio`, `experimental`, `privacy`.

### Enhanced HUD context

Publish parallel, subordinate volume/brightness/battery activities through the coordinator while retaining Apple's HUD and privacy UI. Hardware-dependent values remain unavailable rather than fabricated. **Milestone:** Stage 10.5. **Labels:** `activities`, `system-context`.

### Battery information and management

Expose public battery, charging, condition, and adapter data through `PowerSourceProvider`. Keep charge limiting deferred; prohibit SMC/private IORegistry keys and privileged helpers. **Milestone:** Stage 10.5. **Labels:** `battery`, `public-api`.

### Snap Zones

Implement user-invoked window placement with public Accessibility APIs behind `WindowManagementProvider`, deterministic zone models, clear trust education, and fail-safe behavior. Emit typed presentation feedback; do not let renderers call Accessibility. **Milestone:** Stage 9. **Labels:** `window-management`, `accessibility`, `direct-distribution`, `experimental`.

### Important Notchium banners

Coordinate finite, coalesced banners from typed Notchium/provider events only. Do not inspect arbitrary Notification Center content. Apply privacy redaction before presentation. **Milestone:** Stage 11. **Labels:** `activities`, `notifications`, `privacy`.

### Synchronized lyrics provider seam

Define a provider contract only after verifying a licensed API, synchronization data, caching/attribution requirements, commercial terms, and privacy. Do not scrape or infer lyric text from MusicKit availability metadata. **Milestone:** V1.x. **Labels:** `media`, `deferred`, `legal-review`.

### App Intents and Shortcuts

Expose explicit actions for already-shipping capabilities. Every intent inherits the same permission and availability checks as the app; no hidden background access or debug unlock. **Milestone:** V1.x. **Labels:** `automation`, `app-intents`.
