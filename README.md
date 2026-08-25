# Notch

Notch is a native macOS 26 application that will turn the built-in MacBook notch into a compact productivity and system interface. The repository is currently at **Stage 1: production architecture**. Feature behavior is deliberately disabled until later stages.

## Open the project

Open `Notch.xcworkspace` in Xcode 26 or newer. The workspace contains:

- `Notch.xcodeproj`: the minimal macOS application and UI-test host.
- `NotchPackage`: the Swift package containing architecture, features, services, mocks, and unit tests.
- `Notch/Notch.xctestplan`: the shared unit- and UI-test plan.

The minimum deployment target is macOS 26 and Swift 6 strict concurrency is enabled.

## Stage 1 behavior

The app starts as an accessory application. On a built-in display with a physical notch, it creates a public-AppKit `NSPanel` around that area. A menu-bar extra is always available and is the fallback when an eligible display is absent. The shell exposes only its collapsed, hovered, and deliberately opened state transitions.

No media, calendar, clipboard, camera, capture, monitoring, keyboard suppression, or other feature implementation runs in Stage 1. Real provider adapters report typed `stageTwoRequired` unavailability and never trigger permission prompts.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for module boundaries, dependency injection, provider contracts, concurrency rules, test strategy, and Stage 2 constraints.

The governing product and engineering documents are:

- [Product specification](docs/PRODUCT_SPEC.md)
- [Technical feasibility](docs/FEASIBILITY.md)
- [Engineering rules](docs/ENGINEERING_RULES.md)
- [Permission ledger](docs/PERMISSIONS.md)

## Distribution profiles

Developer ID direct distribution is canonical and uses `Config/Notch.entitlements`. `Config/Notch-AppStore.entitlements` and `Config/AppStore.xcconfig` retain the reduced sandbox-capability profile for a possible Mac App Store edition. The profile is selected at compile time; the developer panel cannot alter production distribution behavior.

## Verification

Build, test, and launch the `Notch` scheme through XcodeBuildMCP with the workspace. A full Xcode 26 installation is required for the app target, XCTest, XCUITest, signing, and launch. Swift package modules can also be compiled through XcodeBuildMCP's Swift-package workflow.

The debug build exposes a developer panel for provider-mode selection, permission-state simulation, synthetic activity events, capability inspection, retention cleanup, and redacted diagnostics. It is excluded from release builds with `#if DEBUG`.
