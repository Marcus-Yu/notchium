# Stage 4 Media Center

The current playback architecture is documented in [Spotify playback pipeline](SPOTIFY_PLAYBACK_PIPELINE.md).
It supersedes the historical command-specific reconciliation notes below.

Media uses the existing Stage 1 service boundary. `MediaProviding` is the canonical protocol; `MediaService`, `MediaSnapshot`, `RealMediaService`, and `MockMediaService` remain compatibility aliases. `MediaProvider` remains its previous alias. No parallel manager is introduced.

`RealMediaProvider` / `MockMediaProvider` → `MediaState` → `MediaSessionController` (`MediaFeatureModel` compatibility alias) → `ActivityCoordinator` (priority 20) → shell content.

One stable media activity identity survives track changes, pauses, stops, temporary inactive responses, and higher-priority interruptions once a valid track has been observed. Only a true first-use state without a cached track has no media activity. Decoded artwork and queue payloads never enter the activity queue. Provider errors and unsupported commands do not fabricate successful playback or seeking.

## Frozen boundaries

The user approved a media-only rendering exception to the frozen shell. `DynamicIslandPresentationModel` keeps an active media surface collapsed until the existing hover/click interaction opens it. Content is injected through `NotchMediaRendering`; the shell never imports media services. The existing media placeholder is filled without changing page navigation or swipe infrastructure.

Panel positioning and hover/click handlers are unchanged. The expanded surface is 520 × 250 inside a fixed 700 × 270 host panel; the shell shape continues to animate within that fixed panel. Space changes only collapse/unpin interaction state, preserving all activities. `ActivityCoordinator` is unchanged. The playing strip contains only artwork on the left and a system-audio waveform on the right. Each flank is 40 pt on this Mac: 24 pt artwork/visualizer allocation plus 8 pt padding on either side. The exact 179 pt hardware center and 32 pt height remain unchanged, yielding 259 × 32 overall. Collapsed metadata is absent. Expanded title/artist, progress, transport controls, and the same shared waveform remain, with system fonts at 17/13/11 pt for title/artist/times.

`MediaFeatureModel.collapsedMediaVisible` is independent of the retained session. The collapsed media extension is visible only when Spotify metadata reports a playing track and the Spotify-scoped Core Audio meter reports current local audio energy. Paused, stopped, inactive, and remote-device playback retain the Spotify session for the expanded player but remove the collapsed extension immediately when their state is known. A short Core Audio activity expiry also clears stale local activity if sample delivery stops, and a Spotify Connect device change invalidates samples attributed to the previous target. Expanded paused and remote playback remain available. Artwork changes crossfade over 180 ms while the new request loads; its frame is reserved immediately. Existing hover hit regions are preserved: hover the hardware notch to open it. A Space change preserves the media session, activity, audio stream, panel, and host. It only collapses expanded/pinned mode and reasserts the existing panel. The panel retains canJoinAllSpaces, stationary, fullScreenAuxiliary, and ignoresCycle.

## Spotify setup and capabilities

1. In a Spotify developer app, register `http://127.0.0.1:8888/callback` exactly.
2. Enter its public client ID in Notchium Settings and choose Connect Spotify.
3. Authorize playback state/control access in Spotify. The listener binds only to IPv4 loopback and closes on completion, cancellation, failure, or a five-minute timeout.
4. Start playback on an active Spotify device, or use a retained track’s Play control to resume on this Mac. Premium, development-mode allowlisting, scopes, restricted devices/sessions, endpoint availability, and Spotify policy still apply.

Authorization uses random state, S256 PKCE, single-use validated callbacks, and Keychain persistence. No client secret is embedded. The public client ID is a preference; access and refresh tokens are never stored in preferences or logs. Expiring tokens refresh through one shared task. The sandbox-compatible profile includes network client/server entitlements for HTTPS and loopback OAuth.

The adapter owns one event listener and one adaptive fallback poller while authenticated.
Commands, Spotify Desktop playback events, Connect changes, and polling all use the same
playback read and snapshot-ingestion path. The controller applies only immediate feedback and
cached presentation; it no longer owns track-transition or seek-confirmation state machines.
See the [current architecture](SPOTIFY_PLAYBACK_PIPELINE.md) for ordering, monotonic progress,
bounded retries, event limitations, and validation.

The existing transport row now contains shuffle, previous, play/pause, next, and repeat, with per-control pending protection and 32 pt hit targets. Unsupported modes are consistently disabled. Mode highlights and transport icons come only from provider snapshots. Repeat cycles off → context → track → off. Explicit play/pause intent is captured at the tap. Previous uses the interpolated provider position: above three seconds it sends Spotify's seek-to-zero command, while at or below three seconds it sends Spotify's previous-track command. All actions use the existing MediaProviding.perform command path via typed convenience methods; there is no second manager or authentication flow. Unsupported source types produce no empty player. The state preserves provider track identity for a future licensed lyrics provider; no real lyrics or scraping are implemented.

## Spotify-only scope

Spotify is the sole media source and real provider in Stage 4. All transport operations use the existing MediaProviding path and authenticated Web API session.

## Spotify Connect devices and playback volume

The expanded player includes one compact secondary row for Spotify volume and the active Spotify Connect device. Opening the device picker performs a single `GET /me/player/devices` refresh; the list has no timer or second polling loop. The picker is an overlay inside the expanded notch rather than a separate popover window, so the panel's hover and outside-click logic cannot mistake device interaction for leaving the notch. Active devices are marked, restricted devices remain visible but disabled, and selecting another available device transfers playback through `PUT /me/player` while preserving the current play/pause state. The picker closes after the authoritative active-device state changes; clicking its backdrop dismisses only the picker, while clicking outside the notch uses the shell's existing collapse path.

The active device name, type, volume, and `supports_volume` capability come from Spotify's playback snapshot. The slider is disabled with explanatory help when the active device is restricted or does not support remote volume. Dragging is local and immediate, shows a temporary percentage, and commits one `PUT /me/player/volume` request when the drag ends. The existing playback confirmation and shared Retry-After gate reconcile the optimistic value.

Spotify may omit devices it does not support, return a nullable device ID or volume, and reject Connect transfer or volume endpoints for non-Premium accounts. Device IDs are treated as refresh-scoped values because Spotify does not guarantee that they remain stable. The expanded surface is 520 × 250 points and its fixed host panel is 700 × 270 points. Collapsed geometry is unchanged.

## Lifecycle and performance

`NotchiumApplicationController` is the composition root and owns one persistent `MediaSessionController`. The app delegate starts its subscription at launch, independent of any view. The session owns `SystemAudioMeter`; an authenticated Spotify session keeps the Spotify-only activity monitor warm so local playback can wake stale metadata. Pause, stop, a Connect target change, or expired local activity immediately removes the waveform and collapsed media presentation without discarding the expanded Spotify session. Disconnect and shutdown stop capture. Expansion and Space changes never restart it.

`MediaSessionController` stores the durable subset of each last valid track through the injected persistence boundary. Empty or stopped provider snapshots are kept authoritative for activity decisions, while the expanded presentation is rebuilt from that cache as paused. Artwork identity, metadata, progress/duration, transport capabilities, queue, volume, and last device context survive normal app and playback interruptions. The cache never makes collapsed media visible and is replaced only by a newer valid Spotify track.

Play from a cached inactive track is optimistic. `RealMediaProvider` uses `NSWorkspace.openApplication` to launch Spotify Desktop without activating it when no playback device exists, then performs a bounded Spotify Connect device-readiness check. It selects the newly available or locally named Computer device, transfers with playback enabled, and confirms through the normal playback endpoint. The existing per-control pending guard prevents duplicate launches and commands; launch, readiness, transfer, or API failure reconciles the cached presentation back to paused.

`SystemAudioMeter` uses a public Core Audio process tap scoped to Spotify. `SpotifyProcessFinder` observes `NSWorkspace` launch and termination notifications without polling. `SpotifyAudioTap` resolves Spotify's current Core Audio process objects, also configures bundle-ID restoration for Spotify audio processes that appear later, and owns a private, tap-auto-start aggregate device plus IOProc. The callback copies only transient PCM buffers; a serial audio queue handles PCM conversion and the existing 2,048-sample Hann-windowed vDSP FFT. Stereo powers combine after transformation, preserving opposite-phase signals. Seven bands (60–120, 120–250, 250–500, 500–1,000, 1,000–2,000, 2,000–5,000, 5,000–12,000 Hz) map log energy to 0.12–1.0 with fast attack and slower release. Publications remain limited to 30 Hz using uptime. The meter derives `isAudioActive` from those levels and expires it after 250 ms without another active sample, preventing stopped callbacks from leaving frozen waveform state behind. DEBUG diagnostics report process discovery, tap creation/start, first sample delivery, first non-silent delivery, and throttled publication without logging PCM or level values. The view has no timer or synthetic oscillator and retains seven fixed bar identities only while local audio is active. No microphone, display pixels, other-app audio, PCM persistence, or ScreenCaptureKit audio path is involved.

Spotify playback polling runs every 5 seconds while playing and every 15 seconds while inactive, with a 30-second delay after transient failures and exact `Retry-After` backoff for HTTP 429. This avoids the former 500 ms loop exhausting Spotify's rolling rate limit and preventing the playable snapshot that starts the audio meter.

Missing recording permission yields one clear permission-required state and no waveform. The app does not prompt automatically; Settings provides an explicit permission action using the public macOS recording permission flow. Denied/unavailable capture never falls back to decorative or static bars. Reduce Motion also removes the waveform rather than freezing it.

Artwork uses an eight-entry/1MB decoded-thumbnail cache, downsampled to at most 160 pixels. Remote artwork accepts HTTPS Spotify CDN URLs only, is bounded to 2MB input, and cancels with view/track lifetime. Fixture artwork is local and deterministic. Queue size, mock command history, and stream buffers are bounded (20 rows, 32 commands, and one latest snapshot respectively).

Long-duration Instruments CPU/energy/memory qualification and physical three-finger Space swipe verification have not been performed. Those remain manual qualification gates; bounded ownership and sampling are implementation safeguards, not measured hours-long results.

## Validation

SwiftPM tests cover passive/playing/paused/stopped state, command routing, skips, seek/progress validation, missing artwork, long titles, Spotify fixtures, queue fixtures, higher-priority interruption/restoration, SDK-independent Spotify response mapping, restricted devices, PKCE/state/replay, loopback callback receipt, rate-limit backoff, queue bounds, and no-device responses. No real-time sleeps are used in tests. Existing Stage 2/3 tests remain in the suite.

Full workspace build: Xcode, Notchium scheme, My Mac. On 2026-09-08, live Spotify authorization with the user's registered client ID succeeded. Verified against the running desktop app: metadata/artwork, paused and playing strip, expanded controls, pause/resume, previous/next, seeking to 60 seconds, and a real 20-item Up Next list. Playback was restored to the original track, paused at 25 seconds. The 360 × 32 paused strip and 450 × 190 expanded surface were visually inspected through the app. Physical hover and three-finger Space-swipe qualification remain unverified. The final SwiftPM suite contains 97 passing tests.

## Stage 4 debug progress model

`MediaState.timestamp` pairs with the observed elapsed position, and `playbackRate` is zero when paused and one for Spotify music playback. Providers with a position sample timestamp preserve it. Spotify's [documented timestamp](https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback) instead identifies the last transport change; using it with current `progress_ms` double-counts playback, so the adapter timestamps observation receipt. `estimatedPlaybackPosition(at:state:)` is a pure, bounded calculation. The expanded `TimelineView` redraws at most every 0.1 seconds while playing and pauses when collapsed, paused, or dragging. It does not mutate provider state or increase network polling. The slider and elapsed label use the same displayed position. Native slider input/accessibility is retained with a visible SwiftUI rail and thumb over the black surface.

Regression cases cover playing/paused/double-rate interpolation, upper/lower/invalid bounds, seek retention through stale samples, confirmation and rejection, metadata changes with reused IDs, and collapsed shape bounds. Stage 4 debug validation on 2026-09-13: 105 tests passed. The unchanged loopback integration test could not bind its fixed port because an unrelated Python process occupies 8888; it is excluded from that successful run and remains an environment-blocked check.

## Media polish validation

The 2026-09-13 polish build succeeded in Xcode (Notchium / My Mac). 106 runnable SwiftPM tests passed, including the exact 999/1,000 ms visibility boundary, resume cancellation, repeated paused updates, retained paused session, and geometry. Fixture renders verified artwork-only left flank, waveform-only right flank, and expanded system typography. The unchanged fixed-port OAuth callback test remains excluded because a separate Python process occupies port 8888. The running app had no connected Spotify session during this pass, so real play/pause, previous, next, seeking, CDN artwork timing, and end-to-end appearance latency could not be requalified. Provider-driven visibility changes are synchronous; external playback detection still depends on the existing 5/15-second Web API polling cadence. This does not establish sub-250 ms latency from an external Spotify action.

## Five-issue media bug fix validation

2026-09-13: Xcode built and launched Notchium / My Mac. A fresh SwiftPM build ran all 117 tests successfully, including the fixed-port OAuth callback. Regression coverage includes view-independent observation, 500 ms polling with no subscribers and duplicate-connect protection, Retry-After and retained state, 449/450 ms visibility, resume cancellation, Space changes preserving media/pin collapse, permission-denied/unavailable static fallback, FFT band selection, stereo phase preservation, silence, and attack/release. Frozen geometry, panel flags, and Stage 2/3 tests remain in the suite. The earlier validation sections describe prior passes and superseded timing values.

Live checks in this pass: real Spotify playback was detected on app launch before opening the notch; external pause removed the flanks and external resume restored them without opening it. A keyboard Space change closed pinned media while preserving the collapsed playing flanks. Spotify was already in fullscreen (its View menu offered Exit Full Screen). These observations do not measure every frame of a slow three-finger swipe. The recording permission-required state and static seven-bar fallback were inspected in the running app. Recording permission has not been granted for this pass, so real captured-audio rhythm response remains unverified. Sub-second end-to-end Spotify timing is also unverified; Web API propagation, response time, and 429 backoff can exceed the polling target.


## Stage 4 controls validation

The controls-only pass builds and runs in Xcode using Notchium.xcworkspace, scheme Notchium, destination My Mac. The full SwiftPM suite passes 123 tests, including explicit play/pause intent, all command endpoints and immediate GET refreshes, concurrent controls, duplicate rejection, failure recovery, no-device capability fallback, shuffle/repeat modes, and existing 450 ms visibility/audio/Space regressions.

Live Spotify verification through Notchium confirmed pause/resume, Next (Heartless → BIRDS OF A FEATHER with updated artwork/artist/duration/progress), provider-native Previous back to Heartless, and seeking to 120 seconds with subsequent confirmed progression. In the Country playlist, Shuffle toggled with provider-confirmed highlighting and Repeat cycled through track mode and back off. DJ mode correctly disabled unavailable modes. The older duplicate app instance was stopped before testing the updated build.

Collapsed artwork/waveform rendering, audio capture/FFT, geometry, animation values, panel positioning, ActivityCoordinator, and Space/fullscreen code are unchanged in this pass. Their existing regression tests pass; physical swipe/fullscreen and live audio capture were not requalified. Stage 5 is untouched.


## Pointer input and waveform recovery bug fix

The page-wide AppKit swipe overlay previously captured mouse hits, and the panel monitor toggled expansion for content clicks. The swipe view now returns nil from hitTest and observes only in-bounds horizontal scroll events. Its monitor is removed when detached. Content clicks pass through to native buttons; header clicks retain pin/unpin behavior. Local input uses event coordinates. Decorative shell/artwork layers do not intercept input, and accessibility exposes separate controls.

Live pointer verification produced PLAY, PAUSE, NEXT, PREVIOUS, SEEK, SHUFFLE, and REPEAT DEBUG tap logs. Expanded runtime logs show ignoresMouseEvents=false; collapsed logs show true. Spotify confirmed play/pause, track changes, seek progression, and shuffle highlighting. These pointer checks supersede the earlier accessibility-action-only qualification. Repeat's pointer log was confirmed, but its final mode screenshot was interrupted by the computer-control capture service.

The waveform capture source was migrated from ScreenCaptureKit to a Spotify-only Core Audio process tap. The existing FFT, smoothing, seven-bar rendering, and playback-owned lifecycle remain intact. Core Audio's first tap attempt owns the System Audio Recording prompt; an explicit Settings action retries after denial. DEBUG level output is throttled to five seconds. A signed Xcode run with Spotify playing resolved the Spotify Core Audio process object, created the process tap and private aggregate device, started the IOProc at 48 kHz stereo, and published changing seven-band levels. Pausing Spotify restored static levels and logged tap teardown; resuming recreated the tap and restored reactive levels. Spotify quit/relaunch recovery, unrelated-app isolation, and expand/collapse capture continuity still require manual verification.

The workspace build succeeded. The latest focused audio run passes all nine permission, lifecycle, FFT, stereo-phase, silence, and smoothing tests. The full SwiftPM run executed 125 tests; 123 passed, while the headless AppKit screen-frame test and fixed-port Spotify loopback test failed for environment-dependent reasons unrelated to this migration. No Stage 5 work was started.

## Spotify cold-launch restoration

The Media page is permanently registered and renders a Spotify state for initialization, unauthenticated, inactive, playing, paused, and error conditions. It is never replaced with an empty view merely because Spotify has no current track. Disconnected and restoration-error states link to the existing Settings connection flow; an authenticated session with no active playback remains visible and continues polling so playback appears when Spotify starts later.

At application launch, the composition-root-owned provider publishes `initializing`, loads the existing access and refresh credentials from the `Notchium.Spotify` Keychain item, refreshes an expired access token through the existing single-flight refresh task, and then fetches playback state. Missing credentials publish `unauthenticated`; a successful 204 playback response publishes authenticated `inactive`; paused and playing responses retain the existing player UI and controls. Static OSLog events describe this sequence without recording credentials, authorization codes, client secrets, or user content.

The 2026-09-14 SwiftPM run executed 150 tests with no failures. New deterministic coverage creates a fresh authorization instance over persisted credentials, exercises expired-token refresh and a second fresh instance, verifies disconnected cold launch, verifies authenticated launch without active playback, advances the provider clock to prove later playback is detected without recreating the service, and renders each non-playing Media state. A physical Mac restart and live Spotify-account pass remain manual release checks; they were not simulated by these tests.

## Spotify restoration completion

Cold-launch restoration and interactive OAuth are separate provider states. Startup uses `initializing`; pressing Connect supersedes any startup attempt and publishes `authorizing`, which renders “Connecting Spotify…” rather than “Restoring your Spotify session…”. A validated callback stores the token response, explicitly publishes an authenticated snapshot, and then starts playback polling. Spotify's 204/no-active-playback response remains authenticated and renders the inactive state.

Starting interactive authorization cancels and generation-invalidates an in-flight token refresh and cancels the old playback poller. This prevents an obsolete refresh from replacing newly stored OAuth credentials. The API client's `Retry-After` deadline survives authorization, disconnect, and provider shutdown within the process: a successful OAuth callback publishes authenticated state even when playback must wait. Callback cancellation returns to unauthenticated; token and Keychain failures publish an error, while a throttled stored-token refresh retains the session and retries only after its deadline. The loopback receiver and ephemeral URL session retain their existing bounded timeouts, so every production startup or authorization attempt has a terminal observable state.


## Spotify request coordination and rate-limit correction (2026-09-14)

`RealMediaProvider` owns one idempotently started polling task. It waits 5 seconds after playing responses, 15 seconds after paused/inactive responses, and 30 seconds after transient failures. Slow responses cannot create catch-up bursts. Subscribers and view expansion never own a poller. `SpotifyPlaybackAPI` is an actor that checks a shared cooldown before token acquisition and again before sending; every actual 429 records its deadline before provider stale-response checks can discard the observation. All playback, queue, and command endpoints share that gate. Existing in-flight requests can finish, but new requests cannot pass the cooldown. Spotify's supplied integer `Retry-After` is honored in full; 30 seconds is only the fallback for a missing/unparseable header. Suppressed requests report remaining seconds and never extend the deadline.

`MediaState.rateLimitedUntil` represents playback throttling independently of `connectionState`. A throttled session remains authenticated, retains credentials and any existing track, and renders a retry time in Settings and the inactive Media page. Settings offers Connected to Spotify / Disconnect during cooldown. OAuth does not clear the playback cooldown. A new process still has to learn the server's current limit from its first response; cooldown persistence across process exits is not implemented.

Queue reads have no timer: track changes, skips, explicit queue opening, and enqueue completion request them. The provider coalesces overlapping calls and caches successful results for 15 seconds for the same track. Track changes invalidate that cache; enqueue success explicitly invalidates it. A track change or enqueue during a pending read permits one follow-up for the latest queue. Opening the player alone performs no queue fetch. Shared queue tasks are awaited rather than cancelled when opening Up Next.

Seek dragging changes local state; releasing sends one seek command and the provider performs one confirming playback GET. Redundant controller/view confirmation GETs were removed. Error recovery still permits one controller refresh, gated during cooldown. Local progress remains `elapsed + elapsed wall time × playbackRate`, bounded to track duration, using observation receipt as the Spotify sample timestamp. Core Audio tap, FFT, waveform, geometry, and animations were not changed by this correction.

DEBUG-only `[SpotifyAPI]` diagnostics record client ID, request sequence, static reason, method/path, status, and Retry-After. `[SpotifyPoll]` records provider ID, generation, start/end, and cycles. Token exchange logs contain only a sequence and grant category. No tokens, headers, callback URLs, query values, or response payloads are logged.

Final verification: 159 SwiftPM tests passed with no failures or skips, including the loopback callback. XcodeBuildMCP built Notchium.xcworkspace / Notchium / Debug / My Mac. Five simulated minutes produced 61 playing GETs (including startup) and 21 inactive GETs, with exactly one sleeping poller despite repeated connect/subscription calls. Tests cover initial/repeated/queue/stale-poll/token-refresh 429s, 59/60-second boundaries, preserved credentials, OAuth during cooldown, queue coalescing across track changes, and one seek command without redundant refreshes. See [request audit and live validation](SPOTIFY_RATE_LIMIT_FIX.md).

## Local playback reconciliation (2026-09-20)

`MediaSessionController` now separates the last authoritative Spotify snapshot from the state presented to SwiftUI. The progress display advances from the latest accepted sample using local elapsed time. Seek, play/pause, shuffle, repeat, restart, and track-transition intents update presentation state immediately, then reconcile with Spotify. Each intent carries a revision and request time so an older playback response cannot overwrite a newer local action. A skip retains the last valid track until Spotify returns a valid replacement; `RealMediaProvider` performs only a bounded set of action-triggered transition refreshes, leaving the normal 5/15-second poll cadence unchanged.

The Spotify-only Core Audio tap remains active while an authenticated session is inactive or paused. Non-silent Spotify activity is only a wake-up signal for an immediate Web API refresh; Spotify remains the sole metadata source. These refreshes are coalesced with a two-second cooldown. The waveform is present only while Spotify reports playback and the tap reports current local audio energy; it is removed, rather than frozen at baseline levels, for paused, remote, silent, unavailable, or expired activity.

Opening Up Next now bypasses the passive 15-second queue cache and starts a five-second visible-only refresh cadence. Track changes, Next/Previous, and enqueue operations also request an immediate queue refresh. Closing Up Next cancels the visible cadence, while passive queue reads retain the existing cache and request coordination.

Verification for this change: 166 SwiftPM tests passed with no failures or skips, and the Notchium Debug macOS workspace build succeeded. Deterministic tests cover optimistic controls, stale snapshot rejection, advancing pending seeks, immediate restart, retained transition metadata, Core Audio-triggered playback discovery cooldown, visible queue cadence, explicit cache bypass, and bounded post-skip discovery. Live Spotify propagation timing and long-running Core Audio energy impact remain manual qualification items.

## Liquid Glass interaction polish and restart rebase (2026-09-20)

The expanded media controls and Player/Up Next selector now use grouped native `GlassEffectContainer` sampling with selective interactive `glassEffect` surfaces. Settings uses the same restrained glass language, status actions use the native glass button style, and the custom seek presentation retains native slider input while adding smooth hover/drag emphasis. Play/Pause uses a symbol replacement transition, active shuffle/repeat states receive a subtle semantic tint, queue and track metadata changes crossfade, and every authored interaction animation provides a Reduce Motion substitute. The shell remains opaque black and collapsed media geometry is unchanged.

Expansion and collapse now use short, critically damped `smooth` animations (340 ms open, 300 ms close), with content entering after 70 ms instead of 170 ms. Transition phase timing matches the visible motion, preventing the model from remaining in a transitioning state after the shell has settled.

Optimistic seek preparation now rebases the presented `MediaState.elapsed` and `timestamp` atomically before dispatching Spotify's seek request. Therefore Previous-as-restart changes every local progress consumer to a zero-based clock immediately; the pending seek revision continues rejecting pre-restart Spotify samples until a valid confirmation arrives. The three-second Previous threshold and previous-track path are unchanged.

## Inactive cache and layout polish (2026-09-21)

The last valid Spotify track is now persisted and restored as a paused expanded presentation whenever live Spotify state is temporarily empty, stopped, or unavailable. Live provider state remains authoritative for Core Audio and collapsed visibility, so the cache cannot fabricate local playback, a waveform, or collapsed media. Play is optimistic; with no active Spotify device, the provider launches Spotify Desktop through `NSWorkspace`, waits for this Mac's Connect device, transfers with playback enabled, and reconciles the result. Failures return the presentation to paused.

The expanded surface is now 520 × 250 points inside a 700 × 270 fixed host panel. Artwork/metadata separation, transport spacing, and vertical separation between progress, transport, and the volume/device row increased without enlarging the control hit targets. Waveform insertion/removal uses a short opacity/scale transition and occupies no expanded-player layout space while inactive.

Final verification: all 175 SwiftPM tests passed, including cache restoration, optimistic resume rollback, native-launch/local-device transfer, Core Audio visibility, Spotify Connect, and geometry regressions. The Notchium Debug workspace build for My Mac also succeeded.

## Spotify responsiveness and resource pass (2026-09-21)

Spotify playback still has one provider-owned fallback poller. It uses 5 seconds while playing and 15 seconds otherwise when the notch is collapsed; while expanded it uses 2.5 seconds for playing, 5 seconds for paused, and 10 seconds for an empty session. Opening the expanded page also requests an immediate, coalesced refresh. Core Audio activity continues to wake inactive local playback without treating audio as track metadata. An event arriving during an in-flight playback fetch now queues one trailing refresh instead of being discarded; queued event work is cancelled on authorization changes, disconnect, and shutdown. Paused/inactive provider samples still reach the controller so stale optimistic intents can expire, but unchanged paused presentation samples do not republish SwiftUI state solely because their receipt timestamp differs.

Queue refreshes on track changes and skips now occur only while Up Next is visible; opening Up Next still refreshes immediately and keeps its visible five-second cadence. Enqueue completion still refreshes its explicit queue request. Volume drag requests remain throttled and serialized; successful volume PUTs no longer add a redundant playback GET. The next fallback poll reconciles volume with Spotify. Rate-limit cooldown and stale-response revision checks remain shared across requests.

The Core Audio meter now keeps one inactivity watchdog during continuous local audio rather than cancelling and creating a task for every sample. Silent/unchanged waveform samples avoid needless observable publications; Up Next suppresses hidden waveform publications while local activity detection continues. PCM analysis trims its sample window only when emitting a frame. Activity decays after the capture stops. Expanded content begins its existing subtle transition without a fixed 70 ms blank interval, with the existing Reduce Motion substitute applied on entry and exit. DEBUG request logs include elapsed request time, and control logs include input-to-local-state and input-to-command-completion time; no token, track, or query payload is recorded.

The final Debug workspace build and all 184 SwiftPM tests pass. A 10.9-second app-scoped idle Time Profiler sample recorded 28 ms of sampled CPU before and 13 ms after; both are already low, and this short observation is not a controlled active-playback or energy measurement. Deterministic tests show 20 local-audio samples now share one inactivity timer rather than creating 20 timers, a volume change sends one PUT instead of a PUT plus confirmation GET, and a hidden queue sends no request on skip/track change. Live expanded Player and Up Next accessibility/rendering were inspected; keyboard/media-key propagation, active-audio energy, and frame-hitch timings remain unmeasured.


## Playback command reconciliation

Next/Previous mark a pending provider transition before sending the command and retain the
complete current track until a different track is observed. Restart rebases progress and its
clock together, then seeks to zero. Each command triggers an immediate playback read; an
unconfirmed skip or seek retries after 250 ms, 500 ms, and 1 s, then falls back to normal
polling. All reads share the pending-intent gate, so an event refresh cannot cancel the retry
budget or publish an old position. The reconciliation window is bounded at ten seconds to
allow subsequent external Spotify/device changes to win. Shared API cooldowns still apply.

Action revisions own retry tasks; observation revisions reject reads that predate a command
or a newer read. Publication rechecks the observation revision after its asynchronous cooldown
lookup. A failed confirmation read retains a successful command's intent instead of rolling
back the local clock. Metadata, artwork URL, duration, position, and timestamp publish as one
MediaState. Global polling intervals are unchanged.


### Previous intent cleanup

Previous has mutually exclusive restart and previous-track reconciliation. A restart cancels
an older Previous track-transition intent; Previous near the beginning cancels an unconfirmed
seek intent. The seek request guard ends when the request finishes, independently of the
snapshot guard. Same-track progress near zero confirms restart even when Spotify executes it
later than the click; Previous track confirmation requires a different available track ID.
Inactive observations can expire the seek guard after the existing reconciliation window.
Next's confirmation and refresh behavior are unchanged.

Regression coverage reproduces the retained seek guard and conflicting Previous/restart
intents, checks delayed restart confirmation and pre-action rejection, verifies the sequence
Previous → Previous → Next → Pause → Play, and verifies normal provider polling of external
changes after either Previous operation without opening the notch or issuing an extra refresh.

## Stage 5 top-level navigation

Music and Calendar now share a dedicated icon-and-label page strip. Player and Up Next remain Music-only sub-navigation. The media view stays mounted while Calendar is selected, so its sub-selection and local UI state survive switching pages; visibility-driven queue and expanded-state work pauses while Music is hidden. The expanded surface is 560 × 302 points inside a 740 × 322 host panel. Settings and Close remain separate header utilities, and collapsed media geometry is unchanged.
