# Architecture — Stage 2 Notch Shell

**Status:** Stage 2 shell implemented on the Stage 1 production architecture

**Minimum OS:** macOS 26

**Language mode:** Swift 6 with complete strict-concurrency checking

**Canonical distribution:** notarized Developer ID direct distribution

This document explains the Stage 1 production architecture and the Stage 2 shell implementation built on it. It is subordinate to [PRODUCT_SPEC.md](PRODUCT_SPEC.md), [FEASIBILITY.md](FEASIBILITY.md), [ENGINEERING_RULES.md](ENGINEERING_RULES.md), and [PERMISSIONS.md](PERMISSIONS.md). The detailed shell contract is in [NOTCH_SHELL.md](NOTCH_SHELL.md).

Stage 2 hardens the executable shell only. It does not implement product features, request protected permissions, persist feature payloads, replace system UI, or use private APIs.

## Shape of the repository

The workspace separates the macOS executable from reusable application code:

```text
Notchium.xcworkspace
├── Notchium.xcodeproj
│   ├── Notchium/                 minimal app lifecycle and scenes
│   └── NotchiumUITests/          XCUITest target
└── NotchiumPackage/
    ├── Sources/
    │   ├── NotchiumCore/
    │   ├── NotchiumDiagnostics/
    │   ├── NotchiumServices/
    │   ├── NotchiumPersistence/
    │   ├── NotchiumDesignSystem/
    │   ├── NotchiumDynamicIsland/
    │   ├── Notchium*Feature/     one target per product feature
    │   ├── NotchiumDebug/
    │   ├── NotchiumFeature/      composition-facing library
    │   └── NotchiumTestFixtures/
    └── Tests/NotchiumFeatureTests/
```

The Xcode application target knows only the `NotchiumFeature` package product. Feature targets do not know about the app lifecycle, the developer panel, or each other. This keeps changes local and prevents a single application model from accumulating unrelated behavior.

## Module responsibilities

| Module | Responsibility | Must not own |
|---|---|---|
| `NotchiumCore` | Feature IDs, capability and permission states, distribution profile, feature flags, service errors, and clock contracts. | AppKit, feature I/O, persistence, or presentation. |
| `NotchiumDiagnostics` | Privacy-redacted event identifiers and unified/mock loggers. | User content or arbitrary diagnostic strings. |
| `NotchiumServices` | Platform-facing protocols, value models, Stage 1 real adapters, mocks, and the immutable service registry. | SwiftUI presentation or hidden dependency construction. |
| `NotchiumPersistence` | Retention contracts and real/mock persistence boundaries. | Feature-specific UI or cloud synchronization. |
| `NotchiumDesignSystem` | Shared system-native measurements and surface treatment. | Feature state or system services. |
| `NotchiumDynamicIsland` | Public display projection and selection, physical/virtual shell geometry, one-panel lifecycle, three-level interaction state, Liquid Glass shell views, and DEBUG fixtures. | Product-feature state, Ambient Edge/Snap overlays, or private display APIs. |
| `Notchium*Feature` | A separately compiled declaration of one product feature and its requirements. | Other features' state or direct platform API construction. |
| `NotchiumDebug` | Debug-only provider modes, simulated permissions, synthetic activities, capability inspection, and cleanup controls. | Production feature flags or sensitive logs. |
| `NotchiumFeature` | Root composition, lifecycle coordination, feature catalog, menu fallback, and architecture-only settings. | Feature business logic or an all-purpose app view model. |
| `NotchiumTestFixtures` | Deterministic dates, mock snapshots, registries, clocks, loggers, and stores. | Production code paths. |

## Dependency direction

Dependencies point inward toward contracts:

```text
macOS app target
    ↓
NotchiumFeature composition
    ├── NotchiumDynamicIsland ──→ NotchiumCore + NotchiumDesignSystem
    ├── feature modules ─────→ NotchiumCore + NotchiumServices
    ├── NotchiumDebug ──────────→ contracts and mocks only
    └── AppEnvironment ──────→ services + persistence + diagnostics + clock

platform adapters and mocks ─→ protocol/value contracts
```

There is no global mutable event bus. Views do not construct services. The `AppEnvironment` value is assembled once at the composition root and carries immutable protocol existentials for services, permission authorization, persistence, clock/scheduler, UUID generation, filesystem access, logging, feature flags, and distribution profile.

`NotchiumApplicationController` is a narrow lifecycle coordinator. It owns app-running state and delegates shell behavior to `NotchiumDisplayCoordinator`; it does not own media, calendar, shelf, clipboard, focus, or monitoring state.

## Stage 2 display and presentation ownership

`NotchiumDisplayCoordinator` now owns display selection and one active `NotchiumPanelController`. It receives pure `NotchiumDisplaySnapshot` values from the AppKit adapter, selects only a built-in display with a verified public auxiliary-area notch gap, and otherwise hides the shell while retaining the menu-bar fallback. Domain and feature code never retain `NSScreen` or select `NSScreen.main`.

The required flow is:

```text
feature/provider
    ↓ typed, redacted candidate event
ActivityCoordinator
    ↓ prioritized, coalesced, expiring presentation state
PresentationRouter
    ├── built-in physical-notch island
    ├── optional Ambient Edge per selected display
    ├── menu-bar fallback
    └── owned system notification when separately authorized
```

Ambient Edge receives presentation state only. It cannot import feature modules, call providers, infer priority, retain raw media/audio/notification payloads, or alter domain state. This keeps presentation optional: turning it off removes a consumer, not a source or coordinator decision.

The future ownership model is conceptually:

```text
NotchiumDisplayCoordinator
    └── NotchiumPanelController?     // one built-in physical-notch shell

FuturePresentationCoordinator
    ├── AmbientEdgeOverlay?          // separate later-stage window
    └── SnapFeedbackOverlay?         // separate later-stage window
```

`DisplayID` is a stable value projected at the AppKit/Core Graphics boundary. Domain and feature layers do not retain `NSScreen`. The coordinator owns shell screen lifecycle, geometry, sleep/wake behavior, window ordering, and cancellation. Future notch, edge, and Snap windows remain separate because their hit testing, geometry, activation, animation, suppression, and lifecycle rules differ.

Stage 2 preserves this seam with pure display identity, placement, and layout values plus deterministic fixtures. It adds no Ambient Edge window, Snap overlay, feature event routing, audio capture, or general-purpose window manager.

Hard-coding any of the following in Stage 2 is prohibited because it would obstruct later multi-surface work:

- treating `NSScreen.main` as the selected display;
- storing raw `NSScreen` or window objects in feature/domain state;
- assuming one connected display or conflating all future presentation surfaces into the shell window;
- stretching the physical-notch panel to screen edges;
- letting features call panel/overlay controllers;
- coupling shell correctness to full-screen or screen-sharing heuristics;
- putting renderer lifecycle, audio analysis, and activity policy into one coordinator.

## Service boundaries

Every requested service has a `Sendable` protocol, a real adapter type, a mock type, typed snapshots, and typed commands where applicable.

| Area | Protocol | Real adapter | Mock adapter |
|---|---|---|---|
| Media | `MediaService` / `MediaProvider` | `RealMediaService` | `MockMediaService` |
| Calendar | `CalendarService` / `CalendarProvider` | `RealCalendarService` | `MockCalendarService` |
| Shelf | `ShelfService` / `ShelfStore` | `RealShelfService` | `MockShelfService` |
| Screenshots | `ScreenshotService` | `RealScreenshotService` | `MockScreenshotService` |
| Clipboard | `ClipboardService` / `ClipboardProvider` | `RealClipboardService` | `MockClipboardService` |
| Camera | `CameraService` / `CameraProvider` | `RealCameraService` | `MockCameraService` |
| Audio devices | `AudioDevicesService` / `AudioDeviceProvider` | `RealAudioDevicesService` | `MockAudioDevicesService` |
| Battery | `BatteryService` | `RealBatteryService` | `MockBatteryService` |
| Caffeine | `CaffeineService` / `WakeLockProvider` | `RealCaffeineService` | `MockCaffeineService` |
| Keyboard lock | `KeyboardLockService` / `KeyboardGate` | `RealKeyboardLockService` | `MockKeyboardLockService` |
| System statistics | `SystemStatsService` / `SystemMetricsProvider` | `RealSystemStatsService` | `MockSystemStatsService` |
| Downloads | `DownloadsService` | `RealDownloadsService` | `MockDownloadsService` |
| Meetings | `MeetingsService` | `RealMeetingsService` | `MockMeetingsService` |
| Focus | `FocusService` / `FocusTracker` | `RealFocusService` | `MockFocusService` |

The Stage 0 cross-cutting contracts are also present: `AudioMeterProvider`, `ActivityEventSource`, `BrowserActivityProvider`, `PermissionAuthorizer`, and `AppClock`, each with real and mock provider types where applicable. Future approved seams include `ActivityCoordinator`, `AudioProcessProvider`, `PowerSourceProvider`, `WindowManagementProvider`, and `LyricsProvider`; this amendment records responsibilities only and adds no Stage 1 implementation.

“Real” in the architecture skeleton means the production injection point, not implemented feature behavior. Every real product adapter still reports the historical `FeatureAvailability.unavailable(.stageTwoRequired)` reason. Commands throw a typed `ServiceFailure`, streams terminate safely, and `RealPermissionAuthorizer.request` refuses to prompt. A later feature stage replaces one adapter at a time behind the existing protocol only after its permission and denial behavior is designed and tested.

Mock providers return deterministic snapshots without touching macOS services. The debug panel models real, mock, denied, unavailable, and failure provider modes so each presentation model can eventually be exercised in every mandatory state. Production behavior cannot be enabled from this panel.

## Concurrency contract

- Presentation and AppKit lifecycle types are explicitly `@MainActor`.
- Mutable test infrastructure uses actors, including the fake clock, mock logger, mock permission authorizer, and mock persistence store.
- Services and exchanged value types are `Sendable`.
- Provider updates use typed `AsyncStream` values; no untyped notification bus crosses feature boundaries.
- Each future long-lived stream consumer must own and cancel its task with the corresponding feature lifecycle.
- System callbacks must be translated into typed values at the platform-service boundary before reaching feature code.

The package and Xcode targets use Swift 6.0 language mode and complete strict-concurrency checking. Isolation is explicit rather than relying on a package-wide default actor.

## Determinism

`AppClock` provides the current date and sleeping behavior. `ContinuousAppClock` is the production implementation. `TestAppClock` is an actor whose sleep operation advances time immediately and records the request, allowing timer behavior to be tested without wall-clock waits. `DateProviding` and `AppScheduling` name the two roles when a feature needs only one side of that contract.

`UUIDGenerating` and `FileSystemAccessing` provide corresponding system and deterministic mock implementations. Stage 1 fixtures use fixed dates and UUIDs. Views and services must not call hidden time, ID, or filesystem factories when deterministic behavior is required.

## Feature flags and distribution

`FeatureFlags.stageTwoShell` enables only the Stage 2 notch shell and retains `stageOne` for historical fixtures. Every product feature and the Spotify audio-derived waveform flag is off. Runtime debug controls cannot override these production values.

`DistributionProfile.current` is selected at compile time:

- `NOTCH_DEVELOPER_ID` is the canonical direct-distribution profile.
- `NOTCH_APP_STORE` represents the reduced sandboxed profile.

`Config/Notchium.entitlements` is the direct-distribution entitlement file. `Config/Notchium-AppStore.entitlements` and `Config/AppStore.xcconfig` retain the sandbox profile for later release engineering. Adding an App Store build configuration to the Xcode project is deliberately deferred until that edition has an approved capability set.

## Native shell

The shell uses SwiftUI until macOS window behavior requires AppKit. `NotchiumPanelController` is that bridge and owns one borderless, nonactivating `NSPanel`.

`NotchiumDisplayCoordinator` requires a built-in display, nonzero public top safe-area inset, and valid `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` values with a positive gap. Without an eligible display it hides the panel and retains the menu-bar fallback. The controller keeps one transparent fixed-size host panel top-anchored to the full screen frame. SwiftUI animates one shape and permanently excludes the hardware footprint from drawing; collapsed physical mode has an empty drawable path. Public pointer monitors drive the narrow hardware-derived hover zone. The panel uses documented Spaces and fullscreen collection behavior, never animates its frame, and never becomes key.

`DynamicIslandPresentationModel` owns `collapsed`, temporarily `hovered`, and pinned `expanded` states plus transition phases. Injected clock tasks implement 120 ms hover entry and 200 ms exit grace, with cancellation and generation checks. Hover and click use the same 0.60/0.88/0.10 native spring, with a 0.18 s Reduce Motion fallback. Pinned state ignores hover exit; a second click, outside click, or Esc closes it. Space-change notifications cancel pending hover activation and close hovered or pinned states through the existing collapse path before reasserting the current panel. They never recreate or reposition it, and hover requires fresh entry to reopen. See [NOTCH_SHELL.md](NOTCH_SHELL.md) for notification timing and the pending hardware acceptance gate. No feature page is implemented.

Ambient Edge must not be added to `DynamicIslandPresentationModel` as decorative booleans. In its later stage it receives a separate immutable presentation model from the activity coordinator, and its AppKit overlay lifecycle remains independent of `NotchiumPanelController`.

The app also exposes a `MenuBarExtra` in every configuration. It provides architecture status, settings, the debug panel in debug builds, and Quit, and remains the only app surface when no display snapshot is available.

## Logging and privacy

`AppLogging` accepts only a closed `AppLogEvent` enum and severity. It intentionally has no arbitrary metadata or message parameter. `UnifiedAppLogger` records these public identifiers through unified logging, while `MockAppLogger` stores entries for tests.

The logger cannot accept clipboard payloads, event titles, meeting URLs, OAuth tokens, domains, filenames, or captured audio. Feature data remains local by contract, and Stage 1 creates no feature payload database or cloud path.

## Developer panel

`NotchiumDebug` compiles its model and view only under `#if DEBUG`. It provides architecture for:

- selecting a provider scenario per service;
- simulating every permission state;
- creating typed synthetic activity events;
- inspecting service capabilities;
- running retention cleanup through the injected store;
- observing only redacted state counts.

The current provider-mode selection is session-local architecture state. Stage 2 adds a feature-composed Shell tab backed by the live `NotchShellDebugModel`, so `NotchiumDebug` does not depend on the concrete shell module. Applying provider replacement to a feature presentation model belongs to that feature's implementation stage. Release builds contain no developer-panel scene or public wrapper.

## Tests

The `NotchiumFeatureTests` unit-test target covers:

- Stage 1 feature-flag defaults;
- fail-closed real providers;
- injectable available mocks;
- deterministic fake-clock behavior;
- disabled Stage 1 permission requests;
- unique feature-module registration;
- keyboard-lock failsafe policy;
- root dependency replacement;
- delayed/cancelled collapsed, hovered, expanded, and transitioning behavior;
- display selection, hot-plug fallback, and zero-display behavior;
- physical and virtual geometry, fixed host-panel placement, hover boundaries, and accessibility configuration;
- panel reconciliation, focus-loss, Escape, and deterministic UI fixtures.

`NotchiumUITests` launches the actual application target and verifies that the process remains running without showing permission alerts. `Notchium.xctestplan` includes both the package unit-test target and UI-test target.

Hardware and permission-revocation suites will be added beside each real provider in later stages. They cannot be substituted with mocks for release acceptance.

## Stage 2 completion and Stage 3 boundary

Stage 2 is complete as a shell-only stage. Stage 3 and every later provider must preserve these module boundaries. Before implementing a provider it must define:

1. capability probing;
2. every permission state and denial fallback;
3. cancellation and revocation behavior;
4. real, mock, denied, unavailable, and failure scenarios;
5. unit, integration, UI, and relevant hardware tests;
6. logging redaction and retention behavior;
7. direct-distribution and sandbox-profile impact.

Private APIs, shell-command metrics, silent capture, universal hardware claims, global media fallbacks, system HUD replacement, and cloud storage remain prohibited unless the Stage 0 contract is explicitly amended.

Ambient Edge is not a Stage 2 deliverable. Stage 2 must not create its overlay, animation renderer, media palette extractor, audio-reactive pipeline, Settings UI, or activity coordinator. It only avoids architectural decisions that would make those later components impossible to isolate.

## Stage 2 verification

Stage 2 is verified with the installed Xcode 26.6 toolchain using isolated DerivedData under `/private/tmp`. Package tests, app Debug/Release builds, XCUITests, launch/relaunch, screenshot fixtures, source/documentation audits, and an app-scoped Instruments run form the completion evidence. Hardware-specific behavior remains a release qualification item rather than something mocks can prove.

## Architectural risks

- `NSPanel` placement and activation still require hardware testing across supported MacBook models, Spaces, full-screen apps, display reconfiguration, sleep/wake, menu-bar settings, and accessibility modes.
- Stage 1 real adapters are deliberately inert. Their protocols may need additive model changes as documented APIs are exercised, but implementation must not leak platform types into feature presentation code.
- Long-lived `AsyncStream` providers will require explicit buffering and cancellation policies per event source; the one-shot Stage 1 streams do not validate sustained event pressure.
- The debug panel models provider modes but does not hot-swap a running feature graph, because no feature presentation graph exists yet.
- The reduced Mac App Store profile is documented but not yet a wired Xcode build configuration; its viability remains subject to capability and review testing.
- Ambient Edge multiplies display/window lifecycle, renderer scheduling, color-space, and energy risk; its failure must never affect feature or notch correctness.
- Best-effort suppression cannot guarantee full-screen video, presentation, game, or third-party screen-sharing detection and must retain manual controls.
- The unresolved API, policy, hardware, browser-extension, clipboard-attribution, download-inference, and review risks listed in the Stage 0 documents remain open.
