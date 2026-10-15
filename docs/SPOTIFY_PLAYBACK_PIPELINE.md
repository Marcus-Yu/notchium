# Local Spotify playback pipeline

## Ownership and execution

`RealMediaProvider` remains the sole source of `MediaState`. `MediaProviding`, the app-owned
`MediaSessionController`, `PlaybackReconciliation`, audio meter and activity coordinator remain
in place. `LocalSpotifyController` is a stateless, injected adapter. `SpotifyScriptExecuting`,
`SpotifyApplicationLaunching`, `SpotifyLocalPreferencesStoring`, playback/lifecycle events and
`AppClock` are replaceable in tests.

`SystemSpotifyScriptExecutor` confines script compilation, execution, result descriptors and
nonprompting Automation checks to one utility serial DispatchQueue. No AppleScript or HTTP playback request
runs on MainActor. Script results are converted to Sendable strings before crossing executors.
Each snapshot reads title, artist, album, artwork URL, duration, position, volume, shuffle,
repeat and playback state together, checks track identity and playback state again, and retries
at most once if the track changes during the read. Execution has a five-second Apple Events
timeout. A pending macOS permission dialog is outside that script timeout. Permission checks target the running Spotify PID; explicit enable activates Notchium and sends the normal protected Apple Event to trigger consent, avoiding the observed stall in the prompting form of the preflight API.

Commands are serialized by the same executor. The provider invalidates pre-command reads and
superseded results with observation revisions and lifecycle generations. Per-control guards
reject duplicate in-flight commands. The existing reconciliation gate retains coherent metadata
through skips and seeks, with three bounded confirmation retries (250 ms, 500 ms, 1 s).
Seeking sets player position only: paused stays paused. Repeat is off/all; repeat-one is rejected.
A synchronous Apple Event already executing cannot be interrupted, but its late result cannot
repopulate a shut-down provider.

## Refresh and resources

`com.spotify.client.PlaybackStateChanged` is a refresh hint, never a source of UI metadata.
In-flight refreshes coalesce into one trailing read. Workspace launch/quit and sleep/wake
notifications refresh availability and cancel stale work. Sleep suspends reads. Opening Music
refreshes immediately. One fallback timer corrects position drift and changes such as volume:
15 seconds while playing, 30 while paused/stopped. No metadata scripts or fallback timers run
when Spotify is absent, closed, awaiting consent, or denied. Workspace observers remain so a
later Spotify launch is detected. No helper process is introduced.

Artwork retains the existing HTTPS `i.scdn.co` loader, bounded thumbnail memory cache, shared
in-flight requests and fallback artwork. Artwork is the only media network traffic. The waveform
continues using the existing Core Audio meter and separate audio-recording consent.

## First use and recovery

Open Spotify, then choose **Enable Local Control** in Music or Settings → Media. The adapter
checks installation/running state without launching Spotify. Only that user action requests the
normal macOS Automation dialog. After Allow, the first script result populates Music immediately.
`SpotifyLocalControlEnabled` records the user's intent; later launches check consent without
prompting. Denial offers **Open System Settings** and the path Privacy & Security → Automation →
Notchium → Spotify. Settings **Check Access** and reopening Music recheck without prompting.
**Disable Local Control** stops protected work; it does not revoke the system's TCC grant.
**Open Spotify** is an explicit user action. Reads never intentionally open Spotify.

`NSAppleEventsUsageDescription` explains metadata and playback control. Development entitlements
include Automation; the sandbox profile also declares Spotify's published playback/library
scripting groups. The existing free Release stays ad-hoc signed without entitlements or hardened
runtime. Verify the actual DMG: development TCC approval is not proof of release approval. Ad-hoc
updates have no stable Developer ID identity, so consent persistence across changed binaries
requires manual qualification. The App Store profile has not been qualified.

The old `SpotifyClientID` preference is removed when local control is explicitly enabled or
disabled. Legacy Keychain items with service `Notchium.Spotify`, account `oauth` are intentionally
left unused. No Keychain reads, deletes or migration prompts occur; unrelated Clipboard keys
and preferences are untouched. Cached queue rows are never restored as a live queue.

## Supported functionality and limits

Supported: local running detection; title/artist/album/artwork; playing/paused state; duration
and interpolated position; play/pause, previous/next, paused seeking, volume, shuffle and repeat
all/off where Spotify reports those modes enabled. Home transport, previous-as-restart, paused
collapsed artwork, waveform behavior, Pomodoro coordination, activity ranking/expiration,
focus suppression, fullscreen and display behavior retain their existing owners.

Spotify's installed `Spotify.sdef` exposes no queue, enqueue, device enumeration, device transfer,
or repeat-one operation. Media presents only the current player, with no Up Next section,
even if a legacy cache contains upcoming tracks. No queue polling, predicted tracks, private API or
UI scraping is used. Remote Spotify Connect device discovery/transfer and queue addition are
removed. Spotify's desktop app may itself reflect an active Connect session; the local dictionary
does not identify or select a remote output device.

Queue investigation: [Spotify Web API queue](https://developer.spotify.com/documentation/web-api/reference/get-queue)
requires OAuth. [Soloist's local integration](https://developer.spotify.com/documentation/soloist/howtos/basic-integration)
requires a separate daemon/API key and controls Soloist, not the installed desktop app. It is not
a supported way to retrieve this user's Spotify Desktop queue. No supported desktop queue route
was found in the installed dictionary or the examined official documentation.

## Verification

See [local Spotify validation](SPOTIFY_LOCAL_VALIDATION.md) for exact builds, test evidence,
distribution checks and outstanding manual acceptance work.
