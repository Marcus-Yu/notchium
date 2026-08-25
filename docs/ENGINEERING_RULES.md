# Engineering Rules — Stage 0

**Status:** Mandatory engineering contract

**Target:** macOS 26 and later

**Canonical distribution:** Developer ID, hardened runtime, notarized direct download

**Last reviewed:** 2026-08-24

## 1. Scope and normative language

This document governs Stage 1 and later work. It defines contracts only; Stage 0 contains no Swift implementation, target, package, Xcode project, view, or test bundle.

“Must” and “must not” are release requirements. “Should” requires a written code-review justification when not followed. An experiment does not bypass these rules.

## 2. Architecture

### 2.1 Mandatory layers

The application must use feature-based modular architecture with these top-level responsibilities:

| Layer | Responsibility | May depend on |
|---|---|---|
| App composition | Process lifecycle, composition root, distribution profile, scene/window assembly, root dependency injection | Features, services, persistence, diagnostics, design system, core models |
| Feature modules | Domain and presentation behavior for one product capability | Core models, service protocols, design system; never another feature's concrete implementation |
| Platform services | Public Apple/vendor API adapters and permission-aware event sources | Core models, diagnostics, narrowly required Apple/vendor frameworks |
| Persistence | Local stores, schema migration, retention, encryption, security-scoped bookmarks | Core models, Keychain abstraction, diagnostics |
| Diagnostics | Redacted logs, signposts, capability snapshots, local export | Core models; never feature payload access by default |
| Design system | Tokens, native control wrappers, glass/accessibility policies, animation primitives | SwiftUI/AppKit and core presentation types only |
| Core models | Stable value types, capability/availability/permission states, identifiers, errors, time abstractions | Foundation-level APIs only |

Dependencies point inward toward protocols and value types. A platform adapter must not import a feature presentation module. A feature must not reach around its protocol to access an adapter, global singleton, or framework object.

### 2.2 Mandatory feature modules

At minimum, future source organization must retain independent modules or equivalent hard target boundaries for:

- Shell
- Media
- Calendar
- Shelf
- Camera
- Audio
- Caffeine
- Keyboard Lock
- Clipboard
- Monitoring
- Activities
- Pages
- Focus

Browser-domain tracking may be a Focus submodule, but its extension/native-messaging targets and `BrowserActivityProvider` contract remain independently testable. Permission UI may be shared, but each feature owns its denial semantics.

### 2.3 Module contents

Each feature module should separate:

- Domain models and use cases.
- Presentation models isolated to `@MainActor`.
- Small views with one presentation responsibility.
- Protocols or protocol conformances needed by the feature.
- Fixtures and mock scenarios.
- Unit tests and, where relevant, integration/UI tests.
- A short capability and permission behavior note linked to [PERMISSIONS.md](PERMISSIONS.md).

A feature may expose typed intents and state. It must not expose framework-specific mutable objects, raw authorization status integers, unstructured dictionaries, or notification names as its public interface.

## 3. Composition and dependency injection

- The app has one explicit composition root. It selects `DistributionProfile`, storage locations, real/mock providers, feature flags, and shared policies before constructing presentation models.
- Views and presentation models receive dependencies through initializers or narrowly scoped SwiftUI environment values established by the composition root.
- A view must not construct a live system service, database, network client, clock, UUID source, file manager, notification center wrapper, or permission authorizer.
- Service locators, mutable global registries, and “shared” application containers are prohibited.
- Apple framework singletons that cannot be avoided, such as a workspace or notification center, must be hidden behind an injected adapter. Their use must not leak into feature logic.
- Dependency graphs must remain acyclic. Cross-feature coordination occurs through typed core models/use cases or the Activities module, never by importing another feature's concrete store.

Every system-facing protocol must have these provider modes where semantically applicable:

1. **Real:** documented production API.
2. **Mock:** deterministic fixtures and scripted events.
3. **Denied:** permission was refused or revoked.
4. **Unavailable:** OS, hardware, account, provider, or distribution profile cannot supply the capability.
5. **Failure:** a controllable provider that emits typed transient and permanent failures.

Denied, unavailable, and failure are distinct states. Tests and UI must not collapse them into one generic error.

## 4. Mandatory service boundaries

These names describe contracts, not Stage 0 implementations. Concrete method names may evolve in an architecture decision record, but their scope may not silently broaden.

| Contract | Owns | Must not own |
|---|---|---|
| `MediaProvider` | Provider authorization, current item, supported playback commands, queue capability, typed state/events | Generic cross-app scraping; audio capture; UI |
| `AudioMeterProvider` | Explicitly started/stopped in-memory amplitude/frequency windows and capture state | PCM persistence, hidden recording, provider policy decisions |
| `CalendarProvider` | Minimum upcoming-event projection and calendar changes | Meeting-client automation; view formatting |
| `ShelfStore` | Managed copies, metadata, selection-independent file operations, expiry, security-scoped destinations | Implicit original-file mutation; view state |
| `CameraProvider` | Device authorization/status, preview-session lifecycle, device changes | Recording or microphone input unless a future approved feature expands the contract |
| `AudioDeviceProvider` | Public route list, current/default output, capability-probed volume, typed changes | Bluetooth pairing truth, private AirPods properties |
| `WakeLockProvider` | Acquire, renew if required, expire, and release owned public power assertions | UI duration selection; undocumented power controls |
| `KeyboardGate` | Session event-tap trust, guarded activation, fail-open suppression state, emergency unlock events | Root/HID interception, password collection, arbitrary shortcut handling |
| `ClipboardProvider` | Privacy-gated pasteboard observations and explicit user-initiated saves | Policy decisions about retention, UI search, or plaintext logging |
| `SystemMetricsProvider` | Timestamped supported total/process snapshots with coverage/staleness metadata | Shell commands, GPU fabrication, per-process network fabrication |
| `ActivityEventSource` | Typed, redacted candidate events from one source | Global priority, presentation, persistence, or content expansion |
| `FocusTracker` | Timer/session state, app-duration aggregation, neutral statistics | Browser extension transport, judgmental scoring, cloud sync |
| `BrowserActivityProvider` | Verified non-private normalized-domain intervals from an installed extension | Full URL/title/path/query collection, incognito/private collection, general browsing history |
| `PermissionAuthorizer` | Current state, contextual request, settings deep-link when documented, revocation observation | Automatically prompting at launch; feature-specific marketing copy |
| `AppClock` | Injected monotonic instants/sleep plus an explicitly separate wall-date source | Direct calls to `Date.now`, `Task.sleep`, or timers inside testable domain logic |

Additional adapters such as `NotificationProvider`, `WorkspaceProvider`, `BrightnessProvider`, `PowerSourceProvider`, `KeychainProvider`, `FileSystem`, `UUIDGenerator`, and `Scheduler` are expected when their concerns enter implementation. They follow the same real/mock/denied/unavailable/failure rule.

## 5. State, concurrency, and event flow

### 5.1 Swift 6 contract

- Stage 1 must enable Swift 6 language mode and complete concurrency checking for every first-party target. The actual Xcode build-setting values must be recorded once full Xcode 26 is installed; this document does not guess generated-project defaults.
- Presentation models and UI mutation are `@MainActor`.
- Mutable I/O state belongs to an actor or to a framework-required executor isolated behind one actor-owned adapter.
- Values crossing isolation boundaries are explicitly `Sendable`. `@unchecked Sendable` requires an architecture decision record explaining the invariant and tests.
- Framework callbacks are converted once, at the adapter boundary, into typed async operations or `AsyncSequence` streams.
- Long-lived observations expose typed `AsyncSequence` events with explicit start, cancellation, completion, buffering, and backpressure policy.
- Unstructured `Task {}` creation is limited to lifecycle boundaries and must have an owner and cancellation path. Detached tasks are prohibited unless an ADR demonstrates executor independence.
- Cancellation is normal control flow. Permission revocation, feature disablement, provider disconnect, panel close, app termination, and test teardown cancel owned work promptly.
- Actors do not call blocking file, network, or framework APIs on the main actor. UI receives immutable snapshots.

### 5.2 Event rules

- Global mutable event buses and stringly typed notifications are prohibited for application-domain communication.
- Framework notifications may be consumed inside an adapter and translated to a typed event.
- Every event includes only fields the receiver needs. Sensitive payloads do not travel through the general activity router.
- Activity events have a stable type, source, priority class, creation instant, expiry, coalescing identity, and redacted presentation summary.
- High-frequency sources are sampled/coalesced before reaching SwiftUI. A waveform, metric source, or file watcher must not invalidate the entire shell on every raw callback.

## 6. SwiftUI and AppKit presentation rules

- SwiftUI views own one presentation responsibility. A view that coordinates unrelated features, permissions, providers, and panel mechanics must be split.
- Enormous single-view bodies, deeply nested conditional forests, and application logic inside `body` are prohibited.
- Extract a child view or presentation model when a section has independent state, focus behavior, permission behavior, animation identity, or test scenarios.
- `ForEach` and collection views use stable domain identity. Array offsets, transient hashes, and newly generated UUIDs are not acceptable identity for persistent elements.
- Presentation state has a single owner. Duplicate mirrored booleans for collapsed/hovered/open or feature availability are prohibited.
- System controls, standard focus behavior, menus, sharing pickers, file panels, Quick Look, and accessibility semantics are preferred over replicas.
- AppKit owns the panel, activation, Spaces, menu-bar, responder-chain, and other macOS window mechanics. SwiftUI does not emulate window levels or focus with web-style layering assumptions.
- Liquid Glass follows the public macOS 26 API and [PRODUCT_SPEC.md](PRODUCT_SPEC.md). Custom blur stacks that conflict with system glass are prohibited.
- Animation may never delay permission explanations, file safety, destructive confirmations, or emergency keyboard unlock.

A pull request that introduces a large view must show that it still has one coherent responsibility, one state owner, bounded invalidation, accessible focus order, and isolated test scenarios. “It is one screen” is not sufficient justification.

## 7. Capability, availability, permission, and distribution models

The core model must distinguish at least:

- `FeatureCapability`: what the OS, hardware, account, provider, and signed binary can theoretically do.
- `FeatureAvailability`: currently available, degraded, denied, restricted, revoked, unavailable, temporarily failed, or policy-disabled.
- `PermissionState`: not determined, authorized, denied, restricted, revoked, or unavailable, with the authorizing system identified.
- `DistributionProfile`: direct or Mac App Store, selected at build composition and visible in diagnostics.

Rules:

- A permission is not a capability. Camera authorization does not imply a camera exists; a writable display property does not imply TCC authorization.
- A feature is available only when profile, OS, hardware, provider/account, policy flag, and permission all allow it.
- Unsupported controls are omitted or disabled with a precise explanation. They never appear to succeed optimistically.
- Permission-dependent features document all states in [PERMISSIONS.md](PERMISSIONS.md): not determined, denied, restricted, revoked, and unavailable.
- Revocation is rechecked before protected operations and when the app becomes active. Active streams stop before presentation updates.

### 7.1 Distribution profiles and flags

- Direct and Store-compatible products use compile-time profile configuration so forbidden code and entitlements can be excluded from a binary, not merely hidden in UI.
- Runtime feature flags are local and typed. They may disable a compiled feature, stage a safe experiment, or choose an approved provider.
- Production behavior cannot be unlocked by debug defaults, UserDefaults editing, environment variables, hidden gestures, or developer-panel settings.
- Policy-disabled features, including Spotify waveform, require a signed release configuration or equivalent production-controlled gate to become available after written approval.
- The compiled profile, active flags, and reason for every unavailable capability appear in redacted diagnostics.

## 8. Time, identity, filesystem, and scheduling determinism

- Domain code never calls wall time, sleeps, random UUID generation, the process filesystem, or global schedulers directly.
- Inject `AppClock` for monotonic time and sleep. Inject a wall-date provider separately for calendar display and retention boundaries.
- Inject UUID generation, filesystem operations, security-scoped bookmark resolution, and scheduling.
- Timer tests advance a controllable clock; they never wait in real time.
- File-watcher tests replay ordered event fixtures including duplicates, coalescing, temporary names, size changes, failures, and cancellation.
- Time-zone, locale, daylight-saving, clock rollback/advance, sleep/wake, and process restart are explicit test cases where relevant.
- Stable persisted identifiers are created once at the owning boundary. Presentation recomputation never generates identity.

## 9. Persistence, retention, and privacy

- No cloud storage or synchronization of clipboard, focus, browser, shelf, or activity information is permitted.
- Clipboard, focus, browser-domain, shelf, and activity information must never be stored or synchronized in iCloud, CloudKit, third-party storage, analytics, crash payload attachments, or an app backend.
- Clipboard payloads are encrypted at the application layer using a random app-owned key stored in Keychain. Sensitive payloads and derived plaintext indexes must not appear in SQLite journals, temporary files, thumbnails, Spotlight, Quick Look caches created by the app, or logs.
- Clipboard retention is 30 days and 500 unpinned items. Pins/favorites are exempt until deletion.
- Focus statistics are retained for 90 days. Raw browser events are discarded after local normalized-domain aggregation.
- Shelf items are copies in app-managed storage and default to 24-hour retention. Cleanup never follows a symlink or bookmark into a source location.
- Waveform samples and amplitude windows are memory-only and are erased by releasing buffers on stop.
- Schema migrations are transactional, versioned, reversible where practical, and tested against redacted fixtures.
- Every store supports idempotent retention cleanup and a user-visible delete operation whose integration test verifies payload files, rows, indexes, thumbnails, and tokens as applicable.

## 10. Logging and diagnostics

Use privacy-redacted unified logging and signposts. Logs may include stable redacted error codes, provider kind, permission state, capability state, durations, counts, and coarse performance measurements.

Logs must never include:

- Clipboard payloads, hashes intended to fingerprint payloads, or OCR text.
- Calendar event titles, notes, attendee data, or meeting URLs.
- OAuth authorization codes, access tokens, refresh tokens, Keychain values, or request headers.
- Browsed domains, URLs, paths, queries, fragments, page titles, or extension payloads.
- Filenames, full paths, bookmark data, file contents, or thumbnail data.
- Captured audio, amplitude history tied to a track, or camera frames.
- Window titles, document names, process command lines, or user-entered search text.

Errors crossing a privacy boundary must be mapped to a redacted typed error before logging. Debug builds follow the same payload prohibition.

### 10.1 Developer/debug panel

A non-production developer panel must support:

- Real/mock/denied/unavailable/failure provider selection.
- Synthetic media, meeting, battery, download, screenshot, clipboard-action, OCR, and hardware activities.
- Permission-state and mid-session revocation simulation.
- Time advancement and deterministic timer scenarios.
- Retention cleanup and local-store reset using only app-owned test data.
- Distribution profile, entitlement expectation, OS, hardware, account/provider, and capability inspection.
- Event-rate, coalescing, dropped-event, task-lifetime, and energy diagnostics.
- Export of a privacy-redacted support bundle.

The panel is excluded from release builds or irreversibly disabled at compile time. It cannot alter production gates or expose protected payloads.

## 11. Testing contract

### 11.1 Unit tests

Every feature must unit-test state transitions, denial/unavailable/failure providers, cancellation, redaction, retention, capability gating, activity priority/coalescing, and deterministic time. Parsing tests cover meeting URLs, domain normalization, secret detection, file stabilization, and provider errors with adversarial fixtures.

### 11.2 Integration tests

Integration tests cover real adapter boundaries where automation is safe: local stores and migrations, Keychain wrapper behavior, security-scoped bookmark invalidation, managed-copy semantics, provider request encoding, async event teardown, and permission-state mapping. Network integrations use protocol-level fixtures by default and never require personal accounts in continuous integration.

### 11.3 UI tests

UI tests cover collapsed → hovered → deliberately opened transitions; menu-bar fallback; keyboard navigation; VoiceOver labels/actions; permission education/denial/retry; reduced motion/transparency; Dynamic Type/large text where supported; provider unavailable states; and emergency unlock UI state. Protected system prompts are not clicked by brittle coordinate automation; tests use controlled authorization states or an approved harness.

### 11.4 Hardware and manual test matrix

Before release, record results for:

- At least one supported built-in-notch MacBook and a no-notch/menu-bar fallback Mac.
- Built-in display plus external display, clamshell mode, display hot-plug, resolution changes, Spaces, full screen, Stage Manager, sleep/wake, and fast user switching where feasible.
- Built-in output, AirPods route, HDMI, AirPlay where available, and at least one device without writable volume.
- Camera absent, busy, disconnected, Continuity Camera, and permission revoked while previewing.
- Display brightness supported and unsupported cases.
- Event-tap creation, timeout, system disablement, Secure Input, trust revocation, app crash/termination, and emergency unlock.
- Clipboard alert/allow/deny behavior on macOS 26, sensitive exclusions, source ambiguity, and clear-history verification.
- Each browser adapter, multiple profiles, private/incognito rejection, extension disabled/revoked, and native-host mismatch.

### 11.5 Permission tests

Every ledger entry in [PERMISSIONS.md](PERMISSIONS.md) must test not determined, allowed, denied, restricted where the platform exposes it, revoked during use, unavailable hardware/account, retry after Settings, and process relaunch. Denial must leave the rest of the app operational.

No release is accepted with skipped tests justified only by unavailable developer hardware. Such coverage must be recorded as a known release risk or completed through an explicit hardware test pass.

## 12. Public API and dependency policy

- Private frameworks, private selectors, undocumented notifications, reverse-engineered IORegistry/SMC/Bluetooth keys, symbol lookup of private functions, and copied private headers are prohibited.
- No shelling out to system utilities to obtain metrics or control hardware. This includes `powermetrics`, `nettop`, `top`, `ps`, `ioreg`, private brightness tools, and scripting external apps.
- No Apple Events or Accessibility automation is used to scrape media state, browser URLs, meeting state, or unrelated application content.
- No Network Extension entitlement is requested for productivity tracking or per-process statistics.
- Third-party dependencies require a documented need, license/security review, update owner, data-flow review, and removal plan. Prefer Apple frameworks and small first-party adapters.

An exception for an undocumented/private API requires all of the following before code is merged:

1. Explicit written product-owner approval naming the exact API and behavior.
2. An architecture decision record with evidence that no public route exists.
3. Security, privacy, OS-update, signing, notarization, and Mac App Store impact analysis.
4. A compile-time-off default and a public-API or unavailable fallback.
5. Automated detection so the private path cannot enter an unapproved distribution profile.
6. Removal criteria and an assigned owner.

Approval of one symbol or feature does not authorize adjacent private APIs.

## 13. Accessibility and release gates

Release is blocked unless:

- All actions are reachable by keyboard without requiring hover.
- VoiceOver exposes correct roles, labels, values, state changes, and custom actions.
- Focus order is deterministic through collapse, expansion, page changes, permission states, and alerts.
- Reduce Motion removes nonessential spatial movement and continuous decorative waveform motion.
- Reduce Transparency produces legible opaque/system-material alternatives.
- Color is not the only status channel and contrast remains sufficient over glass and wallpaper changes.
- System text sizing, localization expansion, right-to-left layout where applicable, and truncation have documented behavior.
- Emergency keyboard unlock and privacy/capture indicators are immediate and independent of animation.
- Energy profiling shows idle features stop polling/capture and hidden panels do not drive continuous rendering.

## 14. Definition of done for a future feature

A feature is not done until it has:

- A documented capability and permission model aligned with [FEASIBILITY.md](FEASIBILITY.md) and [PERMISSIONS.md](PERMISSIONS.md).
- Real, mock, denied, unavailable, and failure providers as applicable.
- Root-composed dependencies and no hidden service construction.
- Unit, integration, UI, hardware, accessibility, revocation, retention, cancellation, and redaction coverage proportional to risk.
- Direct and Store-profile behavior documented, including compile-time exclusions.
- No private API, shell utility, silent capture, cloud sync, or universal unsupported claim.
- Updated documentation and an ADR for any contract change.

## 15. Unresolved technical risks

- Spotify policy clearance for audio-derived waveform visualization and commercial product use.
- Apple Music system-player queue visibility and behavior changes across MusicKit releases.
- Core Audio process-tap permission UX, power cost, provider targeting, and review acceptance.
- Reliability and distribution review risk of keyboard suppression despite using public APIs.
- Clipboard source attribution and secret detection cannot be guaranteed by public APIs.
- Hardware-dependent screen brightness and output-volume support.
- Browser-extension packaging, review, installation, and native-messaging maintenance across four browsers.
- Folder-watcher inference cannot provide universal screenshot/download completion semantics.
- Window placement and activation behavior across Spaces, full-screen applications, display changes, sleep/wake, and menu-bar configurations.
- Mac App Store viability of the reduced capability profile, particularly keyboard suppression and broad observation features.
- Stage 1 requires full Xcode 26; this machine currently exposes the macOS 26.5 SDK through Command Line Tools but no full Xcode installation.
