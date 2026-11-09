# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Notchium is a native macOS 26+ notch utility (Swift 6, SwiftUI + AppKit, EventKit, Core Audio, IOKit, plus a small C real-time audio target). The app is a menu-bar agent (`LSUIElement`). The current direct distribution uses the Stage 24 free, ad-hoc signing policy in `docs/RELEASING.md`. A reduced, sandboxed App Store profile exists but has not been fully tested.

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

# Mock UI tests, or a single UI test (package unit tests use swift test above)
./scripts/run-ui-tests.sh
./scripts/run-ui-tests.sh -only-testing:NotchiumUITests/NotchiumUITests/<testName>

git diff --check   # used as the whitespace gate; no linter is configured

# Free-distribution profile tests (plain `swift test` compiles the developerID profile)
swift test --package-path NotchiumPackage --disable-sandbox \
  -Xswiftc -D -Xswiftc NOTCH_FREE_DISTRIBUTION --filter FreeDistributionTests

# Release (docs/RELEASING.md). Requires a clean tree and tag v<version> on HEAD;
# --preview packages local work, --candidate builds the optimized artifact from committed source
./scripts/release.sh 1.0.0 --preview
python3 scripts/verify-release.py --source .     # fail-closed check for unexpected files, signing, secrets, Mach-O links
python3 -m unittest discover -s scripts/tests    # release-safety and onboarding-crash script tests
```

Notes:
- `CODE_SIGNING_ALLOWED=NO` only checks that the app compiles. Signed builds can fail locally when the development provisioning profile is missing. Do not change the project's signing settings to work around this.
- Some native integration tests need host access (for example Finder resolution and real screencapture detection). They fail or skip under a sandboxed `swift test`, so earlier runs used `--disable-sandbox`. Mixer tests in `AudioMixerTests` have failed intermittently in the past.
- In sandboxed agent shells the default compiler module cache can be unwritable. Earlier sessions used `--disable-sandbox --cache-path /private/tmp/notchium-ai-package-cache` with `CLANG_MODULE_CACHE_PATH` and `SWIFT_MODULECACHE_PATH` pointed under `/private/tmp`.
- UI tests launch the real app with fixture arguments (`--ui-testing`, `--notchium-stage11-fixture`, `--notchium-display builtInMock`, …; see `NotchiumUITests.swift`). Display-only fixtures must still use mock services, or the run hits Keychain/SecurityAgent prompts.
- Run UI fixtures through `scripts/run-ui-tests.sh`: it uses `com.marcusyu.notchium.uitesting` for the target app and a matching runner identity, with local ad-hoc signing overrides. Mixing ad-hoc test launches with the normal app's bundle ID can invalidate its macOS permission grants. The script accepts UI-test selectors, `--derived-data`, `--result-bundle`, and `--log`; it keeps build outputs and rejects arbitrary build-setting overrides. Normal builds retain `com.marcusyu.notchium` and their configured signing policy.
- `Helpers/LidAwake` is a privileged closed-lid daemon. `scripts/build-lid-awake-helper.sh` compiles it in an Xcode build phase, and the build leaves it out only for `NOTCH_APP_STORE`. The free build ships it ad-hoc signed, with an identifier-plus-containing-bundle peer check instead of the Developer ID team requirement (`LidAwakeIdentity`). `release.sh` seals it and `verify-release.py` accepts exactly this helper and launchd job; see `docs/LID_AWAKE.md`. Its tests (`Helpers/LidAwakeTests/main.swift`) are standalone and are not part of `swift test` (see `docs/LID_AWAKE.md`).

## Architecture

The package layers are declared in `NotchiumPackage/Package.swift`. Dependencies point inward:

- `NotchiumCore`: value types and contracts (feature IDs, `FeatureFlags`, capability/availability/permission states, `DistributionProfile`, `AppClock`, UUID/filesystem abstractions). Foundation only.
- `NotchiumServices`: every platform-facing `Sendable` protocol, with `Real*` adapters and `Mock*` providers. Framework callbacks are converted to typed snapshots/`AsyncStream` here, once. It links the C target `NotchiumRealtimeAudio` (lock-free, allocation-free mixer callback; keep it that way).
- `NotchiumPersistence`, `NotchiumDiagnostics`, `NotchiumDesignSystem`: storage/retention, redacted logging, and shared tokens.
- `NotchiumDynamicIsland`: the shell. It owns `NotchiumDisplayCoordinator` (display selection, one `NotchDisplaySession` and panel per selected display), `DynamicIslandPresentationModel` (collapsed/hovered/expanded), `ActivityCoordinator` (sole source of activity priority, coalescing and expiry, projected per display), `NotificationCoordinator`, geometry and page navigation. It does **not** import feature modules. Features plug in through renderer protocols (`NotchMediaRendering`, `NotchCalendarRendering`, `NotchAudioRendering`, `NotchQuickActionsRendering`, `NotchShelfRendering`, …) that feature models conform to.
- `Notchium*Feature`: one target per product capability. A feature never imports another feature's concrete types. Cross-feature coordination goes through core models or the activity coordinator. `NotchiumTeleprompterFeature` follows the same pattern (`NotchTeleprompterRendering`; Core owns script/alignment models, Services own document import and `SpeechAnalyzer` capture, Persistence owns the script library; see `docs/TELEPROMPTER.md`).
- `NotchiumFeature`: the composition root. `AppEnvironment` builds all dependencies once, and `NotchiumApplicationController` creates the long-lived feature models and handles lifecycle (it is not a catch-all view model). It also holds Settings, the menu-bar fallback, `FeatureCatalog`, and DEBUG fixtures/dev panels.
- `NotchiumProactiveFeature`: pure suggestion policy (scoring, interruption, feedback) depending only on Core. It is not yet wired into `NotchiumFeature` and has its own `NotchiumProactiveFeatureTests` target (see `docs/STAGE25A_PROACTIVE_FOUNDATION.md`).
- `NotchiumTestFixtures`: shared test fixtures. Most tests live in `NotchiumFeatureTests`, including `ArchitectureTests`.
- `NotchiumDebug`: DEBUG-only provider-mode, permission and activity simulation. Excluded from release builds.
- `Notchium/NotchiumApp.swift`: thin app entry.

Data flow: provider truth → feature presentation state → typed, redacted activity events → `ActivityCoordinator` policy → shell rendering. Do not move provider I/O into views, add a global event bus or `NotificationCenter` names for domain events, or create a second playback/state manager.

Key contracts (enforced by tests such as `ArchitectureTests` and the rules in `docs/ENGINEERING_RULES.md`):
- Swift 6 language mode with complete strict concurrency. Presentation and AppKit types are `@MainActor`, mutable I/O lives in actors, and every unstructured `Task` has an owner and a cancellation path. `@unchecked Sendable` needs a written justification.
- Determinism: domain code takes time, sleep, UUIDs and the filesystem from injected `AppClock`/`UUIDGenerating`/`FileSystemAccessing`. Timer tests advance `TestAppClock` instead of sleeping.
- Views never construct services. Dependencies come through initializers or narrowly scoped environment values set at the root. Feature/domain code never retains `NSScreen` or uses `NSScreen.main`.
- Every system-facing protocol supports real/mock/denied/unavailable/failure modes. Denied, unavailable and failure are separate states. Unsupported controls are hidden or disabled; they never pretend to succeed.
- A target existing does not mean the feature ships. Features are gated by `FeatureFlags` and `DistributionProfile`, which is set at compile time in `Config/*.xcconfig`: Debug → `developerID` (also the default with no flag, as in `swift test`), Release → `freeDirect` (`NOTCH_FREE_DISTRIBUTION`, the shipped build), AppStore → `appStoreSandboxed` (`NOTCH_APP_STORE`). In `freeDirect`, provisioning-dependent features such as Focus and closed-lid keep-awake are unavailable. Some `Real*` adapters still fail closed, so check composition and flags before assuming one works.
- Privacy: `AppLogging` accepts only the closed `AppLogEvent` enum. Never log clipboard payloads, event titles, URLs, filenames, tokens or similar content. Clipboard data is encrypted with a Keychain-held key and is local only. Clipboard capture is off by default.

Product constraints to keep (from `NOTCHIUM_HANDOFF.md`):
- Seven current top-level pages: Home, Music, Calendar, Focus Timer, Audio, Shelf and Teleprompter; Clipboard is a Shelf section.
- Standard pages use a 524×266 pt expanded shell; Teleprompter uses 655×333 pt. One stable 740×390 pt hosting panel contains both sizes. Selecting Teleprompter smoothly resizes the visible shell and updates its native hit region.
- All pages stay mounted; hidden pages are disabled, not hit-testable, and hidden from accessibility.
- Music is Spotify-only.
- Spotify uses local Apple Events through `LocalSpotifyController`; paused seeking stays paused. OAuth, Web API playback and Connect discovery are removed. Queue capability is unavailable and queue navigation is absent.
- Prefer native macOS controls, following the `ExpandedPageStyle` tokens. Color follows `docs/COLOR_AND_MOTION.md`: a black shell; page hues from `NotchPage.hue`, delivered through SwiftUI `.tint` (Music uses the artwork accent); the soft `NotchPalette`; color only on selection, active modes and live state (text, primary transport and the Music progress bar stay white).
- Expanded content blooms with the shell through `.notchBloom(stage:)`, derived from the interpolated geometry. Collapsed-row content keeps the black gate (`NotchSurfaceGate`). Never add a separate timer-driven reveal.
- Design context for UI work lives in `PRODUCT.md` (register, users, personality, principles).

## Docs

`docs/` holds the specs (`PRODUCT_SPEC.md`, `ENGINEERING_RULES.md`, `PERMISSIONS.md`, `ARCHITECTURE.md`) and per-stage/per-feature notes. Each feature change usually updates its matching doc, including validation evidence. `NOTCHIUM_HANDOFF.md` is the most complete current overview. **The current source code wins over stage docs.** Several documents (for example `ROADMAP.md` and older parts of `ARCHITECTURE.md` and `MEDIA_CENTER.md`) describe geometry, timers or ownership that have since been replaced. Permission-dependent behavior must be documented in `docs/PERMISSIONS.md`.

`.agents/skills/` contains repo-local agent skills (swift-concurrency, swiftui-expert-skill, macos-patterns, liquid-glass, xcodebuildmcp, instruments-profiling, and others) for reference.

Current engineering audit evidence and remaining qualification gates: `docs/STAGE27A_AUDIT.md`. Release qualification status (currently NO-GO on missing installed-app evidence, not a known defect): `docs/STAGE27C_PRODUCTION_RELEASE_VALIDATION.md`. Historical test counts and manual passes in other documents are not current acceptance receipts.
