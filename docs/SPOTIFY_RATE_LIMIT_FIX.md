# Spotify connection and rate-limit fix

## Findings before implementation

- Current working-tree polling was already 5 seconds playing / 15 seconds paused or inactive, with 30-second transient backoff. Git HEAD still used a 500 ms interval (up to 120 playback GETs/minute); that historical cadence is a plausible contributor to the existing server limit, not proven sole causation.
- One permanent polling task existed per `RealMediaProvider`, guarded by `pollTask == nil`. Zero duplicate permanent loops were found. `startPolling` was called by authenticated `updates()` subscriptions and `establishAuthenticatedSession` (startup `connect` and OAuth completion). Composition owns one provider; startup owns one connection task. Views own no polling timers.
- Extra playback GET paths were `poll`, `refresh`, and post-command confirmation in `perform`. A seek release additionally refreshed in `MediaSessionController.executeSeek` and `MediaProgressView`, producing one PUT plus three GETs. Drag movement itself did not send network requests.
- Queue GETs came from controller track-change observation, next/previous success, restart success, and every Media expansion. Enqueue sent POST then GET. No separate queue timer existed, but requests were not coalesced/cached.
- Neither `/me/player/currently-playing` nor `/me/player/devices` is requested by the repository. All player endpoints route through `SpotifyPlaybackAPI.request`. Waveform and local progress do not call the API.
- Integer `Retry-After` was already parsed in `URLSessionMediaTransport`. Provider guards applied a cooldown, but stale-poll error handling discarded 429 before recording it. Other endpoints could already be in flight, and the control guard reported an arbitrary 30 seconds. OAuth/reset cleared the cooldown. There was no general recursive 429 retry loop; the stale-poll branch could schedule another GET 500 ms later and the multiple seek refreshes increased traffic.
- Initial playback 429 became `.error`, even though OAuth had completed and Keychain credentials were valid. Settings always showed both Connect and Disconnect. This made successful authentication look broken.

## Changed files

- `SpotifyPlaybackAPI.swift`: shared actor-based request gate, complete Retry-After deadline, token-refresh backoff propagation, redacted endpoint counters.
- `RealMediaProvider.swift`: guarded restoration, one poller with cleanup, no catch-up cadence, coalesced ordinary playback fetches and queue requests, queue freshness, authenticated cooldown publication.
- `SpotifyAuthorization.swift`: DEBUG-only token request count/status diagnostics; PKCE and Keychain behavior retained.
- `MediaService.swift`: independent `rateLimitedUntil` snapshot field.
- `MediaConnectionView.swift`: mutually exclusive connection actions driven by provider state.
- `MediaFeatureModel.swift`, `MediaProgressView.swift`: remove duplicate successful-seek refreshes; share pending queue work.
- `MediaViews.swift`: fetch queue only when Up Next opens; display cooldown on inactive page.
- `SpotifyMediaTests.swift`, `MediaProgressTests.swift`: new regressions and corrected obsolete expectations that reconnect bypassed Retry-After.
- `MEDIA_CENTER.md`: synchronize the runtime contract and validation results.

These changes build on pre-existing uncommitted restoration, controls, and Core Audio work. Those earlier changes were preserved.

## Validation

159 tests passed, zero failed/skipped. Final XcodeBuildMCP Debug app build succeeded. Deterministic tests cover fresh OAuth and Keychain restoration, one loop over five minutes, paused/no-playback cadence, repeated 429 recovery, shared endpoint cooldown, stale-poll races, queue coalescing, token-refresh throttling, OAuth during cooldown, seek and controls, and existing waveform/geometry behavior.

Live validation on September 14 used the saved credentials, without reconnecting OAuth. The fixed app restored its authenticated session and identified the failing endpoint: GET `/me/player` returned HTTP 429 with `Retry-After: 29500` at 16:38:25 America/Toronto (retry around 00:50 on September 15). Settings displayed Connected to Spotify, Disconnect, and the cooldown time, with no Connect button. The Media page displayed the cooldown instead of Restoring Spotify Session. Expand/collapse/re-expand preserved the state. A 185-second diagnostic capture spanning launch recorded exactly one poller start and one HTTP request; there were zero further requests after the 429, including while Settings and Media were opened. The fixed build was left running.

The old debugger-attached app remained alive after the normal stop tool reported success; it was explicitly terminated. Only one old process existed before testing, so this does not establish pre-existing duplicate-app polling as the original cause.

A real fresh browser login, live playback/control/queue/audio checks, and real recovery after the eight-hour server cooldown remain unverified. Tests simulate those states without hammering Spotify. The server deadline is honored; this patch cannot make Spotify serve playback before it expires.
