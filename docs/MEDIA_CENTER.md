# Media Center

Current architecture and setup: [local Spotify pipeline](SPOTIFY_PLAYBACK_PIPELINE.md).
Validation and remaining acceptance tests: [local Spotify validation](SPOTIFY_LOCAL_VALIDATION.md).
The local implementation replaces the former OAuth, Web API, Connect and rate-limit workflows;
older dated stage reports are historical evidence, not current setup instructions.

## Music layout

The fixed shell and 30-point page gutters are unchanged. Media presents a single player;
Currently Playing and Up Next section buttons are removed. Local Spotify control cannot read
the queue, so the page has no queue surface or queue visibility task.

The player uses enlarged square artwork in the left column, retaining its original top
position. It extends through the output row, with its bottom edge flush with the bottom of
the Spotify logo. The artwork preserves its square proportions without stretching.
The right column holds the one-line title, artist and seek bar, centered transport controls,
then the volume row with a persistent percentage and Spotify source logo. The three rows
use 12-point gaps, with 8-point top and 12-point bottom safe zones. The content stays centered
without reserving space for the removed section selector. Long metadata, missing artwork
and paused playback preserve the same control geometry. The source logo opens Spotify with
a download fallback.

## Playback and integration

`MediaSessionController` continues owning immediate control feedback, previous-as-restart above
three seconds, serialized seeks/volume requests, Home, and the stable Media activity. Authoritative
playback and reconciliation stay in `RealMediaProvider`. Pausing hides collapsed artwork and
media flanks immediately, leaving only the physical notch once the shell settles. Paused track
metadata remains available in Home and Music. Collapsed media requires playing state and real
local audio; the waveform additionally requires visibility and normal motion.
Spotify quit or denied Automation clears collapsed media rather
than letting a cached track fabricate an active session. The expanded cache cannot restore
stale queue rows or hide a local permission/unavailable state.

Pomodoro, activity priority/expiration, focus suppression, fullscreen, multi-display and the
general Audio page have no new ownership or policy paths.

## Waveform colour and artwork

Settings → Media retains Static and Adaptive waveform colour. Static presets, native colour
picker and 3-/6-digit RGB hex input persist locally. Display colours are lifted to preserve
contrast against the black shell without altering saved values. Adaptive colour shares the
existing bounded artwork requests/cache; decoded thumbnails are at most 320px to keep the
larger artwork sharp on Retina displays, with eight memory-cache entries and a 4MB cost limit.
The original audio meter and audio capture implementation are unchanged.

Spotify's bundled source logo remains unmodified. Artwork comes only from the URL returned by
the local dictionary and accepted by the existing `i.scdn.co` HTTPS loader. Missing, rejected or
failed artwork falls back to the native music-note placeholder.
