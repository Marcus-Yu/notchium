# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Notchium is a native macOS 26+ notch utility (Swift 6, SwiftUI + AppKit, EventKit, Core Audio, IOKit, plus a small C real-time audio target). The app is a menu-bar agent (`LSUIElement`). The main distribution is a signed, notarized Developer ID app. A reduced, sandboxed App Store profile exists but has not been fully tested.

## Commands

The repo root is `notch/`. The Xcode app target lives in `Notchium/`, and nearly all code lives in the local Swift package `NotchiumPackage/`.

```sh
# Build / test the package (the main dev loop)
swift build --package-path NotchiumPackage
swift test  --package-path NotchiumPackage
swift test  --package-path NotchiumPackage --filter NotificationLifetimeTests            # one test class
swift test  --package-path NotchiumPackage --filter NotificationLifetimeTests/testName   # one test

# Build the app (package products resolve through the workspace, not the .xcodeproj alone)
xcodebuild -workspace Notchium.xcworkspace -scheme Notchium -destination 'platform=macOS' \
  -configuration Debug -derivedDataPath /tmp/notchium-dd CODE_SIGNING_ALLOWED=NO build

# Full test plan (package unit tests + NotchiumUITests), or a single UI test
xcodebuild -workspace Notchium.xcworkspace -scheme Notchium -destination 'platform=macOS' test
xcodebuild ... test -only-testing:NotchiumUITests/NotchiumUITests/<testName>

git diff --check   # used as the whitespace gate; no linter is configured
```

Notes:
- `CODE_SIGNING_ALLOWED=NO` only checks that the app compiles. Signed builds can fail locally when the development provisioning profile is missing. Do not change the project's signing settings to work around this.
- Some native integration tests need host access (for example Finder resolution and real screencapture detection). They fail or skip under a sandboxed `swift test`, so earlier runs used `--disable-sandbox`. Mixer tests in `AudioMixerTests` have failed intermittently in the past.
- UI tests launch the real app with fixture arguments (`--ui-testing`, `--notchium-stage11-fixture`, `--notchium-display builtInMock`, …; see `NotchiumUITests.swift`). Display-only fixtures must still use mock services, or the run hits Keychain/SecurityAgent prompts.
- `Helpers/LidAwake` is a privileged closed-lid daemon. `scripts/build-lid-awake-helper.sh` compiles it in an Xcode build phase, and the build leaves it out for `NOTCH_APP_STORE`. Its tests (`Helpers/LidAwakeTests/main.swift`) are standalone and are not part of `swift test` (see `docs/LID_AWAKE.md`).

## Architecture

The package layers are declared in `NotchiumPackage/Package.swift`. Dependencies point inward:

- `NotchiumCore`: value types and contracts (feature IDs, `FeatureFlags`, capability/availability/permission states, `DistributionProfile`, `AppClock`, UUID/filesystem abstractions). Foundation only.
- `NotchiumServices`: every platform-facing `Sendable` protocol, with `Real*` adapters and `Mock*` providers. Framework callbacks are converted to typed snapshots/`AsyncStream` here, once.
- `NotchiumPersistence`, `NotchiumDiagnostics`, `NotchiumDesignSystem`: storage/retention, redacted logging, and shared tokens.
- `NotchiumDynamicIsland`: the shell. It owns `NotchiumDisplayCoordinator` (display selection, one `NotchiumPanelController`/`NSPanel`), `DynamicIslandPresentationModel` (collapsed/hovered/expanded), `ActivityCoordinator` (sole owner of activity priority, coalescing, expiry and redaction), `NotificationCoordinator`, geometry and page navigation. It does **not** import feature modules. Features plug in through renderer protocols (`NotchMediaRendering`, `NotchCalendarRendering`, `NotchAudioRendering`, `NotchQuickActionsRendering`, `NotchShelfRendering`, …) that feature models conform to.
- `Notchium*Feature`: one target per product capability. A feature never imports another feature's concrete types. Cross-feature coordination goes through core models or the activity coordinator.
- `NotchiumFeature`: the composition root. `AppEnvironment` builds all dependencies once, and `NotchiumApplicationController` creates the long-lived feature models and handles lifecycle (it is not a catch-all view model). It also holds Settings, the menu-bar fallback, `FeatureCatalog`, and DEBUG fixtures/dev panels.
- `NotchiumDebug`: DEBUG-only provider-mode, permission and activity simulation. Excluded from release builds.
- `Notchium/NotchiumApp.swift`: thin app entry.

Data flow: provider truth → feature presentation state → typed, redacted activity events → `ActivityCoordinator` policy → shell rendering. Do not move provider I/O into views, add a global event bus or `NotificationCenter` names for domain events, or create a second playback/state manager.

Key contracts (enforced by tests such as `ArchitectureTests` and the rules in `docs/ENGINEERING_RULES.md`):
- Swift 6 language mode with complete strict concurrency. Presentation and AppKit types are `@MainActor`, mutable I/O lives in actors, and every unstructured `Task` has an owner and a cancellation path. `@unchecked Sendable` needs a written justification.
- Determinism: domain code takes time, sleep, UUIDs and the filesystem from injected `AppClock`/`UUIDGenerating`/`FileSystemAccessing`. Timer tests advance `TestAppClock` instead of sleeping.
- Views never construct services. Dependencies come through initializers or narrowly scoped environment values set at the root. Feature/domain code never retains `NSScreen` or uses `NSScreen.main`.
- Every system-facing protocol supports real/mock/denied/unavailable/failure modes. Denied, unavailable and failure are separate states. Unsupported controls are hidden or disabled; they never pretend to succeed.
- A target existing does not mean the feature ships. Features are gated by `FeatureFlags` and `DistributionProfile`, which is set at compile time via `NOTCH_DEVELOPER_ID`/`NOTCH_APP_STORE` in `Config/*.xcconfig`. Some `Real*` adapters still fail closed, so check composition and flags before assuming one works.
- Privacy: `AppLogging` accepts only the closed `AppLogEvent` enum. Never log clipboard payloads, event titles, URLs, filenames, tokens or similar content. Clipboard data is encrypted with a Keychain-held key and is local only. Clipboard capture is off by default.

Product constraints to keep (from `NOTCHIUM_HANDOFF.md`):
- Four top-level pages: Home, Music, Calendar and Audio.
- One fixed 524×266 pt expanded shell inside a stable 740×322 pt hosting panel. Page switches never resize the shell.
- All pages stay mounted; hidden pages are disabled, not hit-testable, and hidden from accessibility.
- Music is Spotify-only.
- Prefer native macOS controls and minimal glass, following the `ExpandedPageStyle` tokens.

## Docs

`docs/` holds the specs (`PRODUCT_SPEC.md`, `ENGINEERING_RULES.md`, `PERMISSIONS.md`, `ARCHITECTURE.md`) and per-stage/per-feature notes. Each feature change usually updates its matching doc, including validation evidence. `NOTCHIUM_HANDOFF.md` is the most complete current overview. **The current source code wins over stage docs.** Several documents (for example `ROADMAP.md` and older parts of `ARCHITECTURE.md` and `MEDIA_CENTER.md`) describe geometry, timers or ownership that have since been replaced. Permission-dependent behavior must be documented in `docs/PERMISSIONS.md`.

`.agents/skills/` contains repo-local agent skills (swift-concurrency, swiftui-expert-skill, macos-patterns, liquid-glass, xcodebuildmcp, instruments-profiling, and others) for reference.
