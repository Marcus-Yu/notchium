# Stage 4 Media Center

Media uses the existing Stage 1 service boundary. `MediaProviding` is the canonical protocol; `MediaService`, `MediaSnapshot`, `RealMediaService`, and `MockMediaService` remain compatibility aliases. `MediaProvider` remains its previous alias. No parallel manager is introduced.

`RealMediaProvider` / `MockMediaProvider` → `MediaState` → `MediaFeatureModel` → `ActivityCoordinator` (priority 20) → shell content.

One stable media activity identity survives track changes, pauses, progress updates, and higher-priority interruptions. Stopping media dismisses that identity, including when queued. Decoded artwork and queue payloads never enter the activity queue. Provider errors and unsupported commands do not fabricate successful playback or seeking.

## Frozen boundaries

The user approved a media-only rendering exception to the frozen shell. `DynamicIslandPresentationModel` keeps an active media surface collapsed until the existing hover/click interaction opens it. Content is injected through `NotchMediaRendering`; the shell never imports media services. The existing media placeholder is filled without changing page navigation or swipe infrastructure.

Panel positioning, panel geometry, notch shape, 450 × 190 expanded size, motion constants, hover/click handlers, and Space handling are unchanged. `ActivityCoordinator` is unchanged. The strip is opaque black, 360 points wide, and exactly the reported hardware-notch height. The physical camera blocks center pixels, so artwork occupies the left wing and the truncated title and waveform occupy the right wing. Existing hover hit regions are preserved: hover the hardware notch to open it. A Space change retains the existing Stage 3 clear-all behavior; a subsequent real-provider observation can present media again.

## Spotify setup and capabilities

1. In a Spotify developer app, register `http://127.0.0.1:8888/callback` exactly.
2. Enter its public client ID in Notchium Settings and choose Connect Spotify.
3. Authorize playback state/control access in Spotify. The listener binds only to IPv4 loopback and closes on completion, cancellation, failure, or a five-minute timeout.
4. Start playback on an active Spotify device. Premium, development-mode allowlisting, scopes, restricted devices/sessions, endpoint availability, and Spotify policy still apply.

Authorization uses random state, S256 PKCE, single-use validated callbacks, and Keychain persistence. No client secret is embedded. The public client ID is a preference; access and refresh tokens are never stored in preferences or logs. Expiring tokens refresh through one shared task. The sandbox-compatible profile includes network client/server entitlements for HTTPS and loopback OAuth.

The adapter observes playback every 5 seconds while playing and every 15 seconds while paused/empty. No connection means no polling. Disconnect and the last subscriber's cancellation tear down polling. Errors back off, HTTP 429 respects Retry-After, and overlapping commands are rejected. A command triggers a fresh observation; seek never changes the UI optimistically. The UI reflects device/action capabilities and reports server rejections.

Up Next is fetched only when opened, capped at 20 items, and disabled when unavailable. Repeat/shuffle appear only when permitted. Unsupported source types produce no empty player. The state preserves provider track identity for a future licensed lyrics provider; no real lyrics or scraping are implemented.

## Apple Music limitation

The installed macOS SDK marks `MusicKit.SystemMusicPlayer` unavailable on macOS. The earlier feasibility approval was incorrect; see the superseding correction in [FEASIBILITY.md](FEASIBILITY.md). Apple Music fixtures work, but real Music app observation and controls do not. No alternate integration has been substituted. Arbitrary apps remain unsupported.

## Lifecycle and performance

The waveform is six deterministic bars at a maximum of 15 updates/second while visible and playing. Paused, absent, reduced-motion, reduced-luminance, and Low Power Mode branches contain no timeline. This is not an audio level meter; no recording permission is requested.

Artwork uses an eight-entry/1MB decoded-thumbnail cache, downsampled to at most 160 pixels. Remote artwork accepts HTTPS Spotify CDN URLs only, is bounded to 2MB input, and cancels with view/track lifetime. Fixture artwork is local and deterministic. Queue size, mock command history, and stream buffers are bounded (20 rows, 32 commands, and one latest snapshot respectively).

Long-duration Instruments CPU/energy/memory qualification and physical three-finger Space swipe verification have not been performed. Those remain manual qualification gates; bounded ownership and sampling are implementation safeguards, not measured hours-long results.

## Validation

SwiftPM tests cover passive/playing/paused/stopped state, command routing, skips, seek/progress validation, missing artwork, long titles, both source fixtures, queue fixtures, higher-priority interruption/restoration, SDK-independent Spotify response mapping, restricted devices, PKCE/state/replay, loopback callback receipt, rate-limit backoff, queue bounds, and no-device responses. No real-time sleeps are used in tests. Existing Stage 2/3 tests remain in the suite.

Full workspace build: Xcode, Notchium scheme, My Mac. On 2026-09-08, live Spotify authorization with the user's registered client ID succeeded. Verified against the running desktop app: metadata/artwork, paused and playing strip, expanded controls, pause/resume, previous/next, seeking to 60 seconds, and a real 20-item Up Next list. Playback was restored to the original track, paused at 25 seconds. The 360 × 32 paused strip and 450 × 190 expanded surface were visually inspected through the app. Live Apple Music is blocked by the approved API. Physical hover and three-finger Space-swipe qualification remain unverified. The final SwiftPM suite contains 97 passing tests.
