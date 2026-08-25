# Stage 1 Architecture

**Status:** Stage 1 production architecture

**Minimum OS:** macOS 26

**Language mode:** Swift 6 with complete strict-concurrency checking

**Canonical distribution:** notarized Developer ID direct distribution

This document explains the architecture created in Stage 1. It is subordinate to [PRODUCT_SPEC.md](PRODUCT_SPEC.md), [FEASIBILITY.md](FEASIBILITY.md), [ENGINEERING_RULES.md](ENGINEERING_RULES.md), and [PERMISSIONS.md](PERMISSIONS.md). Those documents remain the product, platform, engineering, and privacy contract.

Stage 1 creates boundaries and executable shell infrastructure only. It does not implement product features, request protected permissions, persist feature payloads, replace system UI, or use private APIs.

## Shape of the repository

The workspace separates the macOS executable from reusable application code:

```text
Notch.xcworkspace
├── Notch.xcodeproj
│   ├── Notch/                 minimal app lifecycle and scenes
│   └── NotchUITests/          XCUITest target
└── NotchPackage/
    ├── Sources/
    │   ├── NotchCore/
    │   ├── NotchDiagnostics/
    │   ├── NotchServices/
    │   ├── NotchPersistence/
    │   ├── NotchDesignSystem/
    │   ├── NotchDynamicIsland/
    │   ├── Notch*Feature/     one target per product feature
    │   ├── NotchDebug/
    │   ├── NotchFeature/      composition-facing library
    │   └── NotchTestFixtures/
    └── Tests/NotchFeatureTests/
```

The Xcode application target knows only the `NotchFeature` package product. Feature targets do not know about the app lifecycle, the developer panel, or each other. This keeps changes local and prevents a single application model from accumulating unrelated behavior.

## Module responsibilities

| Module | Responsibility | Must not own |
|---|---|---|
| `NotchCore` | Feature IDs, capability and permission states, distribution profile, feature flags, service errors, and clock contracts. | AppKit, feature I/O, persistence, or presentation. |
| `NotchDiagnostics` | Privacy-redacted event identifiers and unified/mock loggers. | User content or arbitrary diagnostic strings. |
| `NotchServices` | Platform-facing protocols, value models, Stage 1 real adapters, mocks, and the immutable service registry. | SwiftUI presentation or hidden dependency construction. |
| `NotchPersistence` | Retention contracts and real/mock persistence boundaries. | Feature-specific UI or cloud synchronization. |
| `NotchDesignSystem` | Shared system-native measurements and surface treatment. | Feature state or system services. |
| `NotchDynamicIsland` | Built-in-notch detection, panel lifecycle, panel geometry, and the three-level interaction model. | Product-feature state or private display APIs. |
| `Notch*Feature` | A separately compiled declaration of one product feature and its requirements. | Other features' state or direct platform API construction. |
| `NotchDebug` | Debug-only provider modes, simulated permissions, synthetic activities, capability inspection, and cleanup controls. | Production feature flags or sensitive logs. |
| `NotchFeature` | Root composition, lifecycle coordination, feature catalog, menu fallback, and architecture-only settings. | Feature business logic or an all-purpose app view model. |
| `NotchTestFixtures` | Deterministic dates, mock snapshots, registries, clocks, loggers, and stores. | Production code paths. |

## Dependency direction

Dependencies point inward toward contracts:

```text
macOS app target
    ↓
NotchFeature composition
    ├── NotchDynamicIsland ──→ NotchCore + NotchDesignSystem
    ├── feature modules ─────→ NotchCore + NotchServices
    ├── NotchDebug ──────────→ contracts and mocks only
    └── AppEnvironment ──────→ services + persistence + diagnostics + clock

platform adapters and mocks ─→ protocol/value contracts
```

There is no global mutable event bus. Views do not construct services. The `AppEnvironment` value is assembled once at the composition root and carries immutable protocol existentials for services, permission authorization, persistence, clock/scheduler, UUID generation, filesystem access, logging, feature flags, and distribution profile.

`NotchApplicationController` is a narrow lifecycle coordinator. It owns app-running state and delegates notch-panel behavior to `NotchPanelCoordinator`; it does not own media, calendar, shelf, clipboard, focus, or monitoring state.

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

The Stage 0 cross-cutting contracts are also present: `AudioMeterProvider`, `ActivityEventSource`, `BrowserActivityProvider`, `PermissionAuthorizer`, and `AppClock`, each with real and mock provider types where applicable.

“Real” in Stage 1 means the production injection point, not implemented feature behavior. Every real adapter currently reports `FeatureAvailability.unavailable(.stageTwoRequired)`. Commands throw a typed `ServiceFailure`, streams terminate safely, and `RealPermissionAuthorizer.request` refuses to prompt. Stage 2 must replace one adapter at a time behind the existing protocol after its permission and denial behavior is designed and tested.

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

`FeatureFlags.stageOne` enables only the notch shell. Every product feature and the Spotify audio-derived waveform flag is off. Runtime debug controls cannot override these production values.

`DistributionProfile.current` is selected at compile time:

- `NOTCH_DEVELOPER_ID` is the canonical direct-distribution profile.
- `NOTCH_APP_STORE` represents the reduced sandboxed profile.

`Config/Notch.entitlements` is the direct-distribution entitlement file. `Config/Notch-AppStore.entitlements` and `Config/AppStore.xcconfig` retain the sandbox profile for later release engineering. Adding an App Store build configuration to the Xcode project is deliberately deferred until that edition has an approved capability set.

## Native shell

The shell uses SwiftUI until macOS window behavior requires AppKit. `NotchPanelController` is that bridge and owns one borderless, nonactivating `NSPanel`.

The panel is shown only when a screen passes both public capability checks:

1. Core Graphics identifies it as built in.
2. `NSScreen.safeAreaInsets.top` indicates a top obstruction.

`NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` refine the public notch-gap geometry when available. The window uses documented Spaces and full-screen collection behavior. It does not hide the system HUD, claim ownership of the hardware notch, run on external displays, or use private display metadata.

`DynamicIslandPresentationModel` contains only the collapsed, hovered, and deliberately opened interaction state. The Stage 1 shell visual exists solely to prove that window placement and state ownership are connected; no feature page is implemented.

The app also exposes a `MenuBarExtra`. It is the functional fallback when no eligible built-in notch is present and provides access to architecture status, settings, the debug panel in debug builds, and Quit.

## Logging and privacy

`AppLogging` accepts only a closed `AppLogEvent` enum and severity. It intentionally has no arbitrary metadata or message parameter. `UnifiedAppLogger` records these public identifiers through unified logging, while `MockAppLogger` stores entries for tests.

The logger cannot accept clipboard payloads, event titles, meeting URLs, OAuth tokens, domains, filenames, or captured audio. Feature data remains local by contract, and Stage 1 creates no feature payload database or cloud path.

## Developer panel

`NotchDebug` compiles its model and view only under `#if DEBUG`. It provides architecture for:

- selecting a provider scenario per service;
- simulating every permission state;
- creating typed synthetic activity events;
- inspecting service capabilities;
- running retention cleanup through the injected store;
- observing only redacted state counts.

The current mode selection is session-local architecture state. Applying provider replacement to a feature presentation model belongs to that feature's implementation stage. Release builds contain no developer-panel scene or public wrapper.

## Tests

The `NotchFeatureTests` unit-test target covers:

- Stage 1 feature-flag defaults;
- fail-closed real providers;
- injectable available mocks;
- deterministic fake-clock behavior;
- disabled Stage 1 permission requests;
- unique feature-module registration;
- keyboard-lock failsafe policy;
- root dependency replacement;
- collapsed, hovered, and opened interaction transitions.

`NotchUITests` launches the actual application target and verifies that the process remains running without showing permission alerts. `Notch.xctestplan` includes both the package unit-test target and UI-test target.

Hardware and permission-revocation suites will be added beside each real provider in later stages. They cannot be substituted with mocks for release acceptance.

## Stage 2 boundary

Stage 2 may implement individual providers and presentation models, but it must not collapse these module boundaries. For each provider it must first define:

1. capability probing;
2. every permission state and denial fallback;
3. cancellation and revocation behavior;
4. real, mock, denied, unavailable, and failure scenarios;
5. unit, integration, UI, and relevant hardware tests;
6. logging redaction and retention behavior;
7. direct-distribution and sandbox-profile impact.

Private APIs, shell-command metrics, silent capture, universal hardware claims, global media fallbacks, system HUD replacement, and cloud storage remain prohibited unless the Stage 0 contract is explicitly amended.

## Current verification constraint

The Swift package production target compiles through XcodeBuildMCP with the installed Command Line Tools. This host does not have `/Applications/Xcode.app`; therefore the native Xcode app target, XCTest framework, XCUITest runner, signing, and app launch cannot execute here. Full Xcode 26 remains a Stage 1 acceptance prerequisite, exactly as identified in Stage 0.

## Architectural risks

- `NSPanel` placement and activation still require hardware testing across supported MacBook models, Spaces, full-screen apps, display reconfiguration, sleep/wake, menu-bar settings, and accessibility modes.
- Stage 1 real adapters are deliberately inert. Their protocols may need additive model changes as documented APIs are exercised, but implementation must not leak platform types into feature presentation code.
- Long-lived `AsyncStream` providers will require explicit buffering and cancellation policies per event source; the one-shot Stage 1 streams do not validate sustained event pressure.
- The debug panel models provider modes but does not hot-swap a running feature graph, because no feature presentation graph exists yet.
- The reduced Mac App Store profile is documented but not yet a wired Xcode build configuration; its viability remains subject to capability and review testing.
- Full app build, complete unit/UI test execution, signing, launch, and hardware proof remain blocked until full Xcode 26 is installed and selected.
- The unresolved API, policy, hardware, browser-extension, clipboard-attribution, download-inference, and review risks listed in the Stage 0 documents remain open.
