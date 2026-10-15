# Local Spotify control validation — 2026-10-15

The live checks below predate the idle-shell correction: paused music now hides collapsed
artwork and media flanks while retaining the track in Home and Music. The earlier live inspection
of paused collapsed artwork records the former behavior, not the current acceptance requirement.

## Changed and why

Spotify OAuth/PKCE, token refresh, loopback callbacks, HTTP playback, API cooldowns and
Connect discovery/transfer are removed from production. The new stateless local adapter uses
Spotify's installed scripting dictionary. Existing `MediaProviding`, `RealMediaProvider`,
`PlaybackReconciliation`, `MediaSessionController`, activity coordination, waveform and audio
meter remain the owners of their existing responsibilities. There are no new dependencies or
background helper processes. Version 1.0.0/build 2 is unchanged; nothing was published.

AppleScript execution is serialized on a utility queue. Swift 6 checks pass. Nonprompting
permission checks target the running Spotify PID. First use activates Notchium and sends a
normal protected Apple Event to request macOS Automation consent. The prompting form of
`AEDeterminePermissionToAutomateTarget` stalled during distributable testing and was removed.
Every read has a generation/revision barrier; paused seeking never sends Play. Volume writes
cannot clear an unfinished seek's reconciliation gate and intermediate drag writes avoid
metadata reads. Workspace events cover launch/quit and sleep/wake; playback notifications
request coalesced refreshes. The single fallback uses 15 seconds playing / 30 seconds paused,
and stops while Spotify is closed, absent, denied or awaiting consent.

The Media UI was subsequently simplified to a single player: **Currently Playing and Up Next
buttons are removed**. Artwork is 84 points, transport remains centered, and the bottom row
uses the available width for volume, its percentage and the Spotify source link. Shell dimensions
and page gutters are unchanged. The Media page no longer starts a queue visibility task.
The live checks below predate this layout; current spacing is verified by native-rendered
Media page tests. The follow-up package build and 67 focused Media, playback and display-visibility
tests pass; native renders cover both 196- and 202-point page heights, long metadata, missing
artwork and paused playback. Queue capability remains unavailable.

Legacy `SpotifyClientID` is removed on explicit enable/disable. Old `Notchium.Spotify` / `oauth`
Keychain items are left unused; no Keychain access, broad deletion, or unrelated preference
migration was introduced.

## Feature coverage

| Feature | Result |
| --- | --- |
| Running/installed detection, local title/artist/album/artwork, duration/position | Supported; local adapter tests and live metadata/artwork verified |
| Playing/paused, Play/Pause | Supported; signed app tested live |
| Previous/Next, previous-as-restart | Supported; deterministic adapter, reconciliation and session tests pass |
| Seeking while paused | Supported; live Home seek stayed paused and original position was restored |
| Spotify volume | Supported; live change and restoration verified; mocked acknowledgement/serialization tests pass |
| Shuffle | Supported when Spotify reports enabled; live toggle and restoration verified |
| Repeat | Off/all supported and verified live; repeat-one is unavailable in the dictionary |
| Queue and enqueue | Unavailable; the Media queue navigation is removed; no fabricated or restored queue |
| Remote Connect device discovery/transfer | Removed; desktop dictionary cannot enumerate or select a remote device |
| Home, collapsed paused artwork, waveform, Pomodoro, activities, focus/display policy | Existing owners retained; package regressions pass; Home/collapsed paused artwork also inspected live |

The queue investigation and official source links are in [the pipeline document](SPOTIFY_PLAYBACK_PIPELINE.md).

## Automated validation

- Final focused run: **71 XCTest tests passed**, covering local Spotify, playback reconciliation,
  command serialization/optimism, paused seeking, artwork downloads/cache/failures, Media render
  geometry/navigation, Home/collapsed behavior and source links. Local Spotify has 19 dedicated
  deterministic tests with injected execution/application/preferences/events/clock dependencies.
- Full package run after the consent change: **682 main XCTest cases**, 4 hardware opt-in skips,
  1 existing failure; separate proactive target **38/38 passed** and Swift Testing **5/5 passed**.
  The subsequent bottom-right UI adjustment and volume/seek reconciliation guard passed the
  focused 71-test run above.
- Existing failure: `Stage15StabilizationTests.testRemoteConnectPlaybackOpensHomeAndLocalOpensMusic`
  expects `.music` after opening a local baseline, but the current coordinator opens `.home`.
  The exact same test fails on untouched `HEAD` in an isolated temporary source copy. Its
  underlying page-selection policy was not changed by this task.
- Four skipped `VolumeReplacementHardwareTests` require `NOTCHIUM_VERIFY_SYSTEM_FEEDBACK=1`;
  they belong to the existing hardware qualification path.
- Debug workspace app build: succeeded. Release workspace app build: succeeded using the existing
  free-distribution coverage-disable and source-path-redaction settings.
- Native XCUITest `testExpandedGearReopensExistingSettingsScene`: passed, including the local
  Spotify enable entry point, with no developer client-ID field.
- Native XCUITest `testStabilitySliderPointerInputAndPageOwnership`: could not complete. Initial
  run found no expanded Home button; isolated retry failed in `app.launch()` because macOS did
  not load the app's accessibility session. This is recorded as an unresolved UI automation
  limitation. Native rendered layout/navigation and direct live paused-seek checks passed.
- Final snapshot script compiled against the installed Spotify dictionary with `osacompile`.
- Production source search found no OAuth transport, Web API player endpoint or callback listener.
  `git diff --check` passed. No separate linter is configured.

## Distributable and live checks

The app was built with the repository's free distribution flags, stripped, ad-hoc signed,
and checked with `scripts/verify-release.py`. Its audit reports arm64, minimum macOS 26.0,
version 1.0.0/build 2, an ad-hoc signature and no entitlements, matching the existing free
release process. The temporary DMG checksum was verified and the initial first-use app launched from a mounted
DMG. Live control checks used the ad-hoc-signed staged Release bundle. The final DMG was rebuilt
and verified after the bottom-right adjustment; its final Computer Use inspection timed out
loading accessibility. No release or tag was created.

The signed app read a real paused Spotify track, artwork, artist, duration, position, shuffle,
repeat and volume. Home and the retained collapsed artwork were inspected. Live Play/Pause,
paused seeking, volume, shuffle, repeat off/all, Currently Playing / Up Next navigation and
the unavailable queue state were exercised. Original playback position, paused state, volume,
shuffle and repeat were restored. Live Play was tested with Spotify temporarily muted.
No Spotify login, developer client ID or Web API authorization was used.

Fresh first-grant/denial behavior still needs qualification in a clean user profile. The user
reported no visible dialog from the initial prompting-preflight attempt. After replacing that
path, the real app had authorized local access and returned live snapshots; this does not prove
the exact appearance of the first consent dialog for every fresh install or changed ad-hoc
binary. No TCC resets, database edits, hidden grants or privacy bypasses were used.

## Resources and remaining acceptance work

A ten-second app-scoped Time Profiler sample of the signed app with Spotify paused collected
374 ms of sampled CPU weight. A separate idle process snapshot showed 0.0% instantaneous CPU
and 60,560 KiB resident memory (about 59.1 MiB). These are whole-app observations before the final
navigation relocation, not a controlled before/after comparison or proof of active-playback
energy impact. No CPU/memory improvement claim is made. Trace exports can contain environment
metadata and are not included as shareable artifacts.

Remaining manual acceptance:

1. Fresh downloaded/quarantined DMG on macOS 26: first Allow and first Deny, Settings recovery,
   revocation during playback, disable/re-enable, and consent across a changed ad-hoc update.
2. Live rapid Next/Previous and repeated seeking across track changes and Spotify quit/relaunch;
   unit tests cover these races, while live history-changing skips were left for acceptance.
3. Physical sleep/wake, fullscreen, secondary displays and focus suppression with live Spotify.
4. Authorized real waveform/audio activity and a longer active-playback CPU/memory/energy run.
5. Complete the native pointer UI suite and final mounted-DMG UI inspection once the host's
   accessibility launch is reliable. Avoid concurrent copies of the same bundle; an installed
   Notchium process was observed alongside the temporary validation builds and was left intact.
6. The reduced sandbox/App Store profile is configured with Spotify's scripting groups but has
   not been qualified or submitted.

## Files

### Added

- `NotchiumPackage/Sources/NotchiumServices/LocalSpotifyController.swift`
- `NotchiumPackage/Sources/NotchiumServices/SpotifyAutomationSettings.swift`
- `NotchiumPackage/Sources/NotchiumServices/SpotifyScriptExecutor.swift`
- `NotchiumPackage/Sources/NotchiumServices/SpotifyWorkspaceEvents.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/MediaArtworkTests.swift`
- `docs/SPOTIFY_LOCAL_VALIDATION.md`

### Modified

- `Config/Notchium-AppStore.entitlements`
- `Config/Notchium.entitlements`
- `Notchium/Info.plist`
- `NotchiumPackage/Sources/NotchiumFeature/Stage11Fixtures.swift`
- `NotchiumPackage/Sources/NotchiumMediaFeature/HomeMediaView.swift`
- `NotchiumPackage/Sources/NotchiumMediaFeature/MediaArtwork.swift`
- `NotchiumPackage/Sources/NotchiumMediaFeature/MediaConnectionView.swift`
- `NotchiumPackage/Sources/NotchiumMediaFeature/MediaFeatureModel.swift`
- `NotchiumPackage/Sources/NotchiumMediaFeature/MediaSourceButton.swift` (source link retained after removing the former `MediaPageHeader.swift` selector)
- `NotchiumPackage/Sources/NotchiumMediaFeature/MediaViews.swift`
- `NotchiumPackage/Sources/NotchiumMediaFeature/UpNextView.swift`
- `NotchiumPackage/Sources/NotchiumServices/MediaService.swift`
- `NotchiumPackage/Sources/NotchiumServices/MockMediaProvider.swift`
- `NotchiumPackage/Sources/NotchiumServices/PlaybackReconciliation.swift`
- `NotchiumPackage/Sources/NotchiumServices/RealMediaProvider.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/MediaControlTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/MediaPageLifecycleTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/MediaSourceLinkTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/SpotifyMediaTests.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/TargetedPolishTests.swift`
- `NotchiumUITests/NotchiumUITests.swift`
- `README.md`
- `docs/ENGINEERING_RULES.md`
- `docs/MEDIA_CENTER.md`
- `docs/PERMISSIONS.md`
- `docs/SPOTIFY_PLAYBACK_PIPELINE.md`

### Removed

- `NotchiumPackage/Sources/NotchiumServices/SpotifyAuthorization.swift`
- `NotchiumPackage/Sources/NotchiumServices/SpotifyLoopbackCallback.swift`
- `NotchiumPackage/Sources/NotchiumServices/SpotifyPlaybackAPI.swift`
