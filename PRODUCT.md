# Product

## Register

product

## Users

People using a MacBook with a camera notch: students and knowledge workers running music, calls and meetings, and a calendar all day. Using Notchium is a glance or a quick reach to the top of the screen in the middle of other work. They hover or click, check or change one thing (track, next meeting, output device, timer, a dropped file, a script line) and go back to what they were doing.

## Product Purpose

Notchium turns the MacBook notch into a live, native surface: media control, calendar and meeting reminders, a focus timer, audio routing, a file/clipboard shelf, and a teleprompter. It also shows live activity around the notch (volume, AirPods, transfers, timers). It succeeds when the notch feels like part of macOS: instant to read, effortless to operate, and clearly alive when something is happening.

## Brand Personality

Soft, fluid, premium. The motion reference is the iPhone Dynamic Island: a pure black shape that flows out of the hardware, with springy motion that makes content seem to grow out of the notch. Color is casual and muted: calm, desaturated tones mark selection and live state, and the content stays clean and white. It should feel alive rather than dead, but never loud, and always clearly a first-party-grade Mac utility.

## Anti-references

- The previous all-gray look: white-at-different-opacities on black, gray circle buttons, nothing colored except album art. It read as "dead".
- Gamer RGB, neon glows, rainbow gradients, color used as decoration.
- Saturated system colors on large fills or primary controls (the first pass's solid accent play button, red Calendar highlights and orange Focus digits read as unnatural).
- Glassmorphism everywhere, or heavy frosted panels inside the black shell.
- Web-dashboard card grids and SaaS hero-metric tiles squeezed into the notch.
- Bouncy, elastic or looping motion that does not convey state.

## Design Principles

1. **The island stays black; color stays quiet.** The shell merges with the hardware notch. Soft tones live in selection, active modes and live activity; text and primary controls stay white.
2. **Every color means something.** Some pages have a soft identity tone, and Music takes a softened version of the playing artwork's color. Green, orange and red keep their meanings for success, warning and error.
3. **Content grows out of the notch.** Reveals share the shell's own spring, so open, close and reversal stay continuous and interruptible. No independent choreography.
4. **Native before custom.** SF Pro, SF Symbols and symbol effects, Apple's semantic hues softened for black, and system controls wherever they fit.
5. **Never fake liveness.** Motion and color reflect real state (real playback, real levels, real deadlines). Nothing pulses or glows just to look busy.

## Accessibility & Inclusion

- Text and essential glyphs meet WCAG AA on black (4.5:1 for body text, 3:1 for large text and UI glyphs).
- Color is never the only signal. Selection, state and errors also use shape, fill, symbol variant or text.
- Reduce Motion removes the spatial and blur parts of every animation (crossfades or instant changes). Reduce Transparency and Increase Contrast are honored through the existing `NotchAccessibilityPreferences` overrides.
- VoiceOver labels, traits and identifiers are kept for every control.
