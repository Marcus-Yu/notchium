# Expanded page composition

The 524 × 266 shell, hardware exclusion, 32 pt navigation height, activity ownership, and major expand/collapse animation are unchanged. This pass refines the existing content, without adding product features or changing providers.

## Audit and shared language

The previous Music layout gave five transport buttons equal glass weight and confined transport and output controls to the metadata column. Page gutters varied (24, 27.6 and 30 pt); Calendar and Home used containers where proximity could communicate grouping. Audio's flexible system slider could consume excess height. Some small labels used low-contrast uppercase text.

`ExpandedPageStyle` lives in the existing DesignSystem module: 4/8/12/16/24 spacing, 30 horizontal inset, 8 top inset, 12 bottom inset, 32 header and playback footprint, 28 header buttons, 24 compact controls, 6/8/12 radius tiers, and system-font title/body/caption roles. Calendar now directly depends on that existing module; no external dependency was added. Page models, command pipelines and feature-renderer boundaries remain unchanged.

## Page compositions

- Music: compact native segmented picker at upper right; 76 pt artwork next to title/artist and progress; a reserved quiet waveform position; centered transport with Play/Pause emphasized; 12 pt separation before a full-width volume/output row. Long titles retain native help text. Shuffle/repeat retain their controls and gain a non-color active dot. Track and subpage changes crossfade without content scaling.
- Home: retains the 62/38 split and single screen. Removes the Music card, aligns content with common gutters, improves secondary text, and uses natural-case Calendar labels.
- Calendar: retains 54/46 columns with a 24 pt gutter. Removes the main glass card and idle row fills; separators and proximity group upcoming events. Expanded selection retains a subtle fill. Join remains a distinct sibling action.
- Audio: current output sits directly on the shell; the system slider has a fixed 20 pt row. Device selection retains its subtle fill; mixer rows use separators. Mixer rows are 52 pt with a 4 pt gap, preserving the prior minimum target density. App mute/menu targets are 24 pt. Lists remain scrollable.

## Design and animation review

Applied in the requested order: [Emil apple-design](https://github.com/emilkowalski/skills), installed emil-design-eng, [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) spacing principles, [Anthropic frontend-design](https://github.com/anthropics/claude-code/tree/main/plugins/frontend-design/skills/frontend-design) composition principles, and [Vercel guidelines](https://github.com/vercel-labs/web-interface-guidelines) accessibility audit. Native SwiftUI/AppKit conventions take precedence over web/mobile prescriptions. SwiftUI segmented Picker and keyboard focus APIs were checked against Apple documentation through Context7.

| Before | After | Why |
| --- | --- | --- |
| Equal glass transport circles | Only Play/Pause has a strong neutral surface | Establish playback hierarchy |
| Volume/output squeezed into metadata column | Separate full-width lower row | Give related audio controls room |
| Page offsets and track/subpage scale transitions | Opacity-only content changes | Remove incidental movement; preserve shell motion |
| 0.90 press scale including Reduce Motion | 0.97 normally, no scale with Reduce Motion | Restrained feedback |
| Audio slider stretches vertically | Explicit compact row height | Reserve room for device and mixer lists |
| Shared custom sliders lack direct keyboard focus | Focusable, arrow-key adjustments using existing commit callback | Keyboard parity without replacing drag/seek logic |
| AppKit mixer menu suppresses focus ring | Default focus ring and tooltip | Native discoverability |
| Calendar idle cards and glass main event | Black surface, separators, selected fill | Reduce competing containers |

Source/still-render verdict: approve. No new persistent animation or service was introduced. Existing waveform lifecycle and reduced-motion suppression remain. The black-shell state machine and Caffeine hold timing are untouched. Live frame pacing, interrupted real-device transitions, VoiceOver traversal, system Reduce Motion interaction, fullscreen/Spaces and hardware audio need manual validation; still images do not certify those behaviors.

## Validation

Native AppKit-hosted renders cover all four pages, expanded Calendar, a long Music title with active waveform, and the queue. Home's existing populated/long/empty/disconnected fixtures and no-scroll assertion remain. Mixer fixtures use identities of two currently running regular applications with mock audio services; they never capture or modify real audio. The existing density test now checks that two full rows fit the revised 108 pt viewport, while retaining the 52–58 pt minimum/maximum row requirement.

Validation commands and final results are recorded below.

## Files in this refinement

Paths below are relative to the repository. Earlier notification/header changes remain in the working tree and are documented separately.

- `NotchiumPackage/Package.swift`
- `NotchiumPackage/Sources/NotchiumDesignSystem/ExpandedPageStyle.swift` (new)
- `NotchiumPackage/Sources/NotchiumDesignSystem/NotchiumSlider.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchPanelLayout.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/Pages/NotchPagesView.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/Home/HomeDashboardView.swift`
- `NotchiumPackage/Sources/NotchiumMediaFeature/MediaViews.swift`
- `NotchiumPackage/Sources/NotchiumMediaFeature/HomeMediaView.swift`
- `NotchiumPackage/Sources/NotchiumCalendarFeature/CalendarActivityView.swift`
- `NotchiumPackage/Sources/NotchiumCalendarFeature/CalendarUpcomingEventRow.swift`
- `NotchiumPackage/Sources/NotchiumCalendarFeature/HomeCalendarView.swift`
- `NotchiumPackage/Sources/NotchiumAudioFeature/AudioPageView.swift`
- `NotchiumPackage/Tests/NotchiumFeatureTests/ExpandedPageCompositionTests.swift` (new)
- `NotchiumPackage/Tests/NotchiumFeatureTests/AudioMixerTests.swift`
- `docs/EXPANDED_PAGE_COMPOSITION.md` (new)
- `docs/NOTCH_SHELL.md`, `docs/HOME_DASHBOARD.md`, `docs/MEDIA_CENTER.md`, `docs/CALENDAR_ACTIVITY.md`, `docs/AUDIO.md`

Final verification:

- `swift test --package-path NotchiumPackage`: built package targets; 307 XCTest tests passed, zero failures. Log: `/tmp/notch-composition-tests.log`.
- `git diff --check`: passed.
- Native-hosted fixtures visually inspected: `/tmp/notch-composition-home.png`, `music.png`, `calendar.png`, `audio.png`, `calendar-expanded.png`, `music-long.png`, and `queue.png` (same prefix).
- The first complete run caught the mixer minimum row-height contract; restored 52 pt rows and tightened surrounding structure before rerunning successfully.
- Reduce Motion was reviewed in source. A fixture override was not possible because SwiftUI exposes that environment key as read-only; no system preference was changed and no runtime reduced-motion claim is made.
- XcodeBuildMCP tools were unavailable; used the repository's SwiftPM build/test fallback. No signed application archive, live hardware integration, or separate configured lint command was run.
