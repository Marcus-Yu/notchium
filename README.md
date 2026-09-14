# Notchium

Notchium is a native macOS 26 application that will turn the MacBook notch into a compact productivity and system interface. The repository is at **Stage 4 of 12: Media Center**. Media state, controls, public Spotify integration, and deterministic fixtures are implemented; Apple Music app observation is unavailable under the approved macOS API. Other product features remain disabled.

## Open the project

Open `Notchium.xcworkspace` in Xcode 26 or newer. The workspace contains:

- `Notchium.xcodeproj`: the minimal macOS application and UI-test host.
- `NotchiumPackage`: the Swift package containing architecture, features, services, mocks, and unit tests.
- `Notchium/Notchium.xctestplan`: the shared unit- and UI-test plan.

The minimum deployment target is macOS 26 and Swift 6 strict concurrency is enabled.

## Stage 2 behavior

The app starts as an accessory application and owns one public-AppKit `NSPanel`. It targets only a built-in display with a verified physical notch. In collapsed physical mode it paints nothing over or below the hardware notch. A menu-bar extra remains available in every configuration and is the only surface when no supported built-in notch is present. The placeholder shell supports collapsed, hovered, and deliberately expanded states with native macOS 26 Liquid Glass and accessibility fallbacks.

With no media, the Stage 2 passive shell remains unchanged. Stage 4 adds an approved media-only 360-point rendering strip at hardware-notch height, plus media content inside the existing 450 × 190 expanded shell. Connect Spotify in Settings using a registered client ID and the displayed loopback redirect. Apple Music, unsupported generic sources, real lyrics, and audio capture remain unavailable. See [Media Center](docs/MEDIA_CENTER.md).

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for module boundaries and state ownership, and [docs/NOTCH_SHELL.md](docs/NOTCH_SHELL.md) for the implemented display, geometry, interaction, glass, and accessibility contract.

The governing product and engineering documents are:

- [Product specification](docs/PRODUCT_SPEC.md)
- [Technical feasibility](docs/FEASIBILITY.md)
- [Engineering rules](docs/ENGINEERING_RULES.md)
- [Permission ledger](docs/PERMISSIONS.md)

## Distribution profiles

Developer ID direct distribution is canonical and uses `Config/Notchium.entitlements`. `Config/Notchium-AppStore.entitlements` and `Config/AppStore.xcconfig` retain the reduced sandbox-capability profile for a possible Mac App Store edition. The profile is selected at compile time; the developer panel cannot alter production distribution behavior.

## Verification

Build, test, and launch the `Notchium` scheme through XcodeBuildMCP with the workspace. A full Xcode 26 installation is required for the app target, XCTest, XCUITest, signing, and launch. Swift package modules can also be compiled through XcodeBuildMCP's Swift-package workflow.

The debug build exposes a developer panel for provider-mode selection, permission-state simulation, synthetic activity events, capability inspection, retention cleanup, and redacted diagnostics. It is excluded from release builds with `#if DEBUG`.
