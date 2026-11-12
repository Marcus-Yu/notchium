# Color and motion

November 8, 2026. The product direction is in [`PRODUCT.md`](../PRODUCT.md): **soft, fluid,
premium**. Motion follows the iPhone Dynamic Island. Color is calm: the shell stays black, text and
primary controls stay white, and a few soft tones mark selection, active modes and live state. The
first pass used saturated system colors. After review it was revised: the Music transport, Calendar
and Focus Timer were restored to their original look, and every remaining tone was softened.

## Palette

`NotchiumDesignSystem/NotchPalette.swift` holds fixed sRGB tones. They are fixed because the notch
is always black, while `Color.red` and its siblings follow the Mac's light/dark appearance. The
tones belong to the same family as the Focus Timer's original palette, whose focus blue is `sky`,
and each clears 7:1 against black.

| Identity | sRGB | Status | sRGB |
|---|---|---|---|
| `rose` | 236, 138, 156 | `green` (success) | 110, 206, 140 |
| `sky` | 130, 177, 245 | `red` (failure) | 250, 118, 108 |
| `teal` | 112, 196, 200 | `orange` (warning) | 255, 176, 92 |
| `lavender` | 178, 160, 232 | | |
| `sand` | 226, 196, 130 | | |

`NotchStatusColor` names the status roles. A selected tab or active toggle uses its tone at
`selectionFillOpacity` (0.18) behind a glyph in the full tone. A hover wash is white at
`hoverFillOpacity` (0.09).

## Where color appears

`NotchPage.hue` gives each page an identity. `NotchPagesView` applies it with SwiftUI's native `.tint`,
so feature views read `.tint` and never import page types.

| Page | Tone | Where it shows |
|---|---|---|
| Home | white (neutral) | Selected tab only |
| Calendar | `red` on its tab only | Selected tab. The page keeps its original white look (`NotchPage.contentHue` is white); event dots use each calendar's own color |
| Music | soft artwork accent, `rose` fallback | Tab, active shuffle/repeat, status glyphs. Play/Pause and progress stay white |
| Focus Timer | `sky` | Tab only; the page keeps its original palette (soft blue, mint, lavender) |
| Audio | `teal` | Current output glyph, selected device, sliders |
| Shelf (and Clipboard) | `lavender` | Selection fill and hairline, transfer progress, empty-state glyph, armed drop target |
| Teleprompter | `sand` | Reading marker, progress, play |

The selected tab shows its tone on a pill that slides between tabs. Selection is also carried by the
filled symbol variant and the VoiceOver selected trait, never by color alone. Unselected tabs and
utility glyphs stay white. Active utilities use their own color: Mirror is soft green and Caffeine
keeps its original orange.

Caffeine shows its keyboard focus ring only when macOS Keyboard Navigation is enabled. Pointer use with Keyboard Navigation off leaves no white ring.

### Music accent

`WaveformAppearanceModel` analyses each cover once with the existing dominant-color clustering and
exposes `accentColor`. `WaveformColor.mutedAccent` keeps the artwork's hue at a calm saturation
(0.3–0.5) and an even brightness (0.86–0.94), so every album reads as one soft family. Neutral covers
return nil and fall back to `rose`. The waveform keeps its original default (Static, white); Adaptive
remains an explicit choice in Settings.

### Activities and notifications

Compact activities keep white by default. Transfers are `sky` (`Tint.transfer`), charging and finished
transfers green (`charging`, `success`), and warnings red. The running Focus Timer keeps its original
white countdown. Feedback banners color their glyph green (done), red (failed) or orange (reminder
added), and the glyph lands with one bounce. Calendar reminders and Join keep their original white.

## Motion

| Moment | Motion |
|---|---|
| Shell opening | `interactiveSpring(response: 0.42, dampingFraction: 0.72)`, about 4% overshoot |
| Shell closing | `interactiveSpring(response: 0.36, dampingFraction: 0.94)`, no bounce past the notch |
| Expanded content | Bloom: blur-to-sharp, fade, 94% to 100% scale and 8 pt settle, driven by shell height |
| Header selection | Sliding tone pill, spring response 0.32 / damping 0.78, symbol bounce |
| Page switch | Outgoing fades in 80 ms; the incoming page fades and settles from 96.5% scale |
| Transport | Play/Pause and other glyph changes use `symbolEffect(.replace)` |

The bloom is specified in [the shell contract](NOTCH_SHELL.md). It is computed from the interpolated
geometry each frame. It has no timer, reverses with the spring, and never delays input past the 75%
threshold. Collapsed-row content keeps the black gate. Reduce Motion removes every spatial and blur
component: the shell uses its 0.12 s ease-out, the bloom keeps only its fade, page changes crossfade,
and symbol bounces are skipped.

## Validation

- `NotchTransitionSurfaceTests` cover bloom staging, the rendered open and close bloom, and the
  explicit black gate. `WaveformAppearanceTests` cover the soft accent: it keeps the artwork's hue,
  stays in the 0.2–0.52 saturation band, is readable on black and is absent for neutral covers. They
  also check mode-independent artwork analysis.
- Music, Calendar and Focus Timer render tests run unchanged against their original visuals.
- The rehearsal capture (`NotchMotionRehearsalTests`) and a per-tab header render were reviewed.

Not yet verified: on-hardware feel and 60 fps pacing on a notched display, accents from real Spotify
artwork (the fixture cover uses a fixed color), and the Audio, Shelf and Teleprompter pages with live data.
