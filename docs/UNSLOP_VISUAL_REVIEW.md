# Unslop visual review

November 1, 2026. Read-only review using **unslop by Damir Sokolovsky
([@heydamir](https://github.com/heydamir/unslop)), CC BY 4.0**. The skill is
installed at `.agents/skills/unslop`; its `SKILL.md`, `references/signs.md`
and `references/tokens.md` guided this pass.

## Direction

- **Product:** a native macOS utility for brief media and system actions.
- **Character:** quiet, precise, responsive.
- **World:** the display bezel and native system controls.
- **Moments:** album artwork and meaningful live activity carry the color.
- **Signature:** one continuous black shape growing from the display edge.

The screen is already deliberately designed. The appropriate scope is a few
polish refinements, retaining the black shell, SF typography and symbols, current
palette, content order, fixed geometry and feature ownership. Generic web tokens
are reference values, not grounds to replace the established native design.

## Findings

### 1. Page crossfades briefly double the player

**Priority: medium visual polish.** The Home-to-Music frame shows two artworks,
two metadata groups and overlapping progress/transport controls. Both retained
layouts fade simultaneously over the same black background. The effect occurs
in both normal and reduced-motion captures.

- Evidence: [normal transition](../dist/motion-rehearsal-final/standard/108-page-music.png),
  [reduced transition](../dist/motion-rehearsal-final/reduced/108-page-music.png).
- Source: `NotchiumDynamicIsland/Pages/NotchPagesView.swift:235`.
- Suggested refinement: a short, interruption-safe fade through black limited
  to the page-content slot, so the two player layouts never read as simultaneous.
  Keep the header, mounted page identities and immediate interaction ownership.

### 2. Short Home titles have a loose title-to-artist gap

**Priority: low visual polish.** Reserving two title lines keeps the artist
baseline stable, but a short title leaves an empty line inside the metadata
pair. The title and artist look less closely related than in the Music page.

- Evidence: [short title](../dist/motion-rehearsal-final/standard/082-home-settled.png)
  and [long title](../dist/motion-rehearsal-final/standard/094-home-metadata-long.png).
- Source: `NotchiumMediaFeature/HomeMediaView.swift:49–58`.
- Suggested refinement: preserve the existing 72 pt artwork/information lane,
  use the existing 5 pt noncompact title/artist gap, and reserve spare space
  below the pair. This keeps progress and transport steady while accepting that
  the artist follows a one- or two-line title.

### 3. Truncated Home metadata cannot be inspected with a tooltip

**Priority: low usability polish.** Long Home titles and artists truncate without
the native full-text help already provided for the Music title.

- Evidence: the long-title screenshot above; source inspection confirms the
  missing tooltip rather than claiming a tested hover interaction.
- Source: `NotchiumMediaFeature/HomeMediaView.swift:50` and `:54`;
  existing convention at `NotchiumMediaFeature/MediaViews.swift:192`.
- Suggested refinement: native `.help` text containing the full title and artist.
  No additional visible labels or larger layout are needed.

## What holds up

- Neutral chrome leaves album artwork as the main color-bearing content.
- System typography and SF Symbols suit a compact native utility.
- Selection, transport hierarchy and numeric time formatting remain restrained.
- Sampled normal/reduced track changes retain control positions and reset the
  progress value directly.
- The expanding black silhouette and separate full-size content preserve the
  product's identity. Clipping during the documented 75% opening reveal is an
  established behavior, not evidence of an accidental resize or scale.

The orange artwork and unavailable Calendar half are deliberate mock-fixture
content. They are not findings against production imagery or Calendar behavior.
The blank collapsed mock frame follows the hardware-notch exclusion contract.
No generic decorative gradients, glows, emoji navigation, excessive badges or
unnecessary looping decoration were found in the reviewed screens.

## Coverage and limits

Reviewed the existing normal/reduced shell and media contact sheets plus
individual settled, long/short metadata, navigation, reveal, reversal, skip and
seek frames from `dist/motion-rehearsal-final`. Cross-checked the relevant current
SwiftUI source. These are the native captures produced during the preceding
animation pass, not a new live-app recording. The same approximately 80 ms median
sampling limit applies; this review cannot certify refresh-by-refresh motion.

This review does not establish current live Spotify, pointer/trackpad, VoiceOver,
fullscreen/Space, all other feature-page, or real-notched-display acceptance.
No app code was changed and no new build/test pass was run for this visual review.
No image generation or story video was needed. The skill remains installed for
future turns.

## Approved implementation

The three refinements above have now been implemented following the user's
explicit request. The findings and original screenshots remain as before-state
evidence.

- `NotchPageVisibility` uses an 80 ms exit and a 120 ms entry delayed until the
  exit finishes. Reduce Motion uses 40 ms exit and 60 ms entry. The opacity-only
  modifier retains page identity and contains no timer, task or delayed model
  mutation; rapid selections retarget SwiftUI's current presentation.
- Home's metadata stays top-aligned in its existing 72/56 pt information lane.
  The title uses up to two lines without reserving an empty line before the
  artist; unused capacity falls below the pair. Progress and transport stay put.
- Both Home strings now expose their full text through native `.help` tooltips.

Focused native regressions cover ordinary and rapidly reversed page switches in
both motion modes, retaining all three test pages and never showing two layouts
above the visibility threshold. A Home raster regression verifies close metadata
grouping and identical playback pixels for short/long titles in both densities.
Validation of the implementation:

- All 139 focused tests, including the opt-in capture test, pass with no failures
  and no skips in the isolated package described in the motion rehearsal report.
- The production `NotchiumMediaFeature` target and its Design System/Dynamic
  Island dependencies build successfully.
- Fresh normal and reduced-motion rehearsals produced 198 snapshots each
  (396 total), including rapid Home/Music reversals. Reviewed contact sheets and
  individual metadata/navigation frames show tighter grouping, clean truncation
  and a single fading page layout. Capture intervals remain sparse: approximately
  77 ms median, with maximum in-beat gaps of 154/151 ms for normal/reduced.
- `git diff --check` passes. Native help modifiers compile; a physical-pointer
  tooltip hover was not manually exercised.
- The full package build was attempted and is still blocked by the unrelated
  non-exhaustive `AIWindowContextError.contextMessage` switch at
  `NotchiumAIFeature/AIWindowContextError+Message.swift:5`. Live hardware, real
  Spotify and full-app acceptance remain pending.

Updated local artifacts:

- [Normal media contact sheet](../dist/unslop-implementation/standard/summary-media.png)
- [Reduced media contact sheet](../dist/unslop-implementation/reduced/summary-media.png)
- [Normal animated rehearsal](../dist/unslop-implementation/standard/motion.gif)
- [Reduced animated rehearsal](../dist/unslop-implementation/reduced/motion.gif)
