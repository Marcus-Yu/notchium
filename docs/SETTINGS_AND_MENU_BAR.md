# Settings access and menu-bar visibility

## Architecture

- `NotchiumApp` owns the single `MenuBarExtra` insertion binding and existing `Settings` scene.
- `NotchiumAppDelegate` starts the application controller as an accessory application and owns its activation policy.
- `SettingsWindowLifecycle` observes the native Settings window without replacing SwiftUI's delegate. Opening Settings temporarily selects the regular activation policy, showing the app icon in the Dock and app switcher. Closing Settings restores accessory mode; minimizing it or switching focus leaves the icon present. The same observer handles reopening SwiftUI's cached window.
- `NotchiumDisplayCoordinator` owns `NotchiumPanelController`, which manually hosts `NotchiumShellView` in `NotchPanel` using `NSHostingView`.
- `NotchShellOuterSurface` composes collapsed media and expanded content. `ExpandedTopSurface` defines the shape, not header controls.
- `NotchSettingsButton` occupies the expanded header's right wing, above the content and outside the hardware-notch click region. It does not change shell dimensions or the playback-control layout.

The gear and menu Settings button both activate the app and invoke SwiftUI's `openSettings`. This was exercised successfully from the manual hosting hierarchy on macOS 26.6.2. SwiftUI owns the existing Settings window and orders it forward when already open; no second hosting window, selector, or Settings view is introduced.

Stage 23 adds **Open Notchium** to the existing menu. This deliberately expands and focuses the panel for keyboard use; passive presentation does not take focus. Expanded controls follow native keyboard navigation behavior. Technical shell-stage and distribution labels were removed from the menu/Settings, while debug controls remain available in DEBUG builds. Clipboard capture has its own default-off production toggle and storage failures are visible in Settings.

The external Settings window uses a native two-column sidebar. General contains app-wide settings; Home Page, Media, Audio, Calendar, Clipboard, Focus and Caffeine contain their existing feature controls. Categories follow the injected models, feature flags and distribution profile. Home layout and shortcut controls are shared with the standalone Home editor, and a shortcut edit request selects Home Page. Navigation state belongs to the Settings view; feature preferences remain owned by their existing models.

The Dock lifecycle was validated on macOS 27.0.1 with Xcode 27: Debug and Release
builds passed, and the focused Settings UI test passed. It checks accessory mode
at launch, regular mode while Settings is open or minimized, restoring the
existing minimized window, closing back to accessory mode, and reopening it.

Media contains Spotify connection and waveform colour controls. Audio contains system-audio
recording permission controls. Waveform colours are automatically brightened when needed
to remain visible against the black notch in both Static and Adaptive modes.

## Recovery

Open the expanded notch's gear, then use **Show menu-bar icon** in Settings. This controls the same insertion binding as the menu scene. If macOS blocks the app, check **System Settings → Menu Bar → Allow in the Menu Bar → Notchium**. A true insertion value does not guarantee available menu-bar space.

The app respects removal callbacks. It does not repeatedly force insertion, reset macOS preferences at launch, or create a second status item to bypass visibility choices. DEBUG builds log launch configuration, label creation, insertion changes, and saved status visibility values. Release builds omit these diagnostics.

## Investigation on this Mac

- Built `Info.plist`: `LSUIElement = true`; running activation policy: accessory (`1`), macOS 26.6.2 (25G83).
- SwiftUI label instantiated with insertion `true`; macOS subsequently set the binding to `false`.
- Saved preference `NSStatusItem VisibleCC Item-0` was `0`, while the app-wide System Settings allowance was on.
- Three Notchium processes were running (two older instances plus the current Xcode launch). The two older instances were stopped for isolation.
- A temporary, strongly retained native `NSStatusItem` titled `N` reported `isVisible = true`, frame `(1448, 934, 22, 22)`, and visible window occlusion state. The user reported that **N was not visually visible**. This is not evidence of a SwiftUI-only failure.
- An off/on cycle of the app-wide allowance, an explicit insertion request, and a one-time removal of the saved hidden-item key did not establish durable visibility. No such preference mutation is included in the app.

## Confirmed cause and local recovery

Control Center's `appStatusItems` log explicitly reported `Moving host to blocked list` and `Requesting updated blocked host to not be visible` for `com.marcusyu.notchium-Item-0`. Restarting Control Center did not remove the block.

The decisive controlled test was changing **ChatGPT** in **Allow in the Menu Bar** from off to on, without changing Notchium. Control Center immediately logged `Unblocking host`, `Requesting visibility for unblocked host`, and `Adding displayable items` for Notchium. Restoring ChatGPT to off reintroduced the block. This establishes a cross-app allowance dependency, consistent with Tahoe's orphaned `trackedApplications.menuItemLocations` issue reported in [CodexBar issue 1440](https://github.com/steipete/CodexBar/issues/1440). The protected preference mapping itself was not readable in this session.

The user authorized leaving ChatGPT's allowance enabled, which restores Notchium. This is a local system-state workaround; the underlying macOS mapping remains. Notchium retains its bundle identifier and one SwiftUI `MenuBarExtra`. Replacing it with AppKit would encounter the same bundle-level block. The temporary native diagnostic item was removed from the final source.

If this recurs despite Notchium being allowed, investigate Control Center's blocked-host log and cross-app allowance state. Do not automatically enable unrelated apps, alter protected system preferences, or continually recreate status items.

## Validation

- Xcode `Notchium` scheme, `My Mac`: builds successfully. No new compiler warnings/errors; the pre-existing App Intents metadata-extraction warning remains.
- All 159 package unit tests passed, including media command, previous-track restart/threshold, Spotify, and waveform tests.
- Existing shell UI tests passed. The new Settings UI test passed after using a stable accessibility identifier for the Spotify field. It checks collapsed absence, opening, focusing an existing Settings window, closing, and reopening.
- Manual testing confirmed `openSettings` works from the manually hosted notch and displays the existing Spotify connection UI.
- Final Cmd+R relaunch retained insertion `true` and saved item visibility `1`; the user visually confirmed the capsule icon appears. The underlying Control Center mapping workaround survives relaunch.
- Live Spotify pause/resume succeeded and the collapsed playing indicator returned. Playback restart/previous, next, shuffle/repeat, and waveform behavior are covered by the passing unit tests; not all live commands were independently exercised.

## Clipboard and sidebar follow-up validation — 2026-10-07

- The Debug `Notchium` scheme built successfully on My Mac. Signed entitlements include the private Keychain group and app identifier.
- All 25 clipboard tests passed, including entitlement failure, blocked writes, encrypted history preservation and recovery after simulated unlock.
- The Settings reopen UI test passed after selecting the sidebar’s identified Media button; it covers opening, focusing the existing window, closing and reopening.
- Native inspection confirmed saved clipboard text, links and images load without the false locked warning, and Home Page, Media and Audio display their controls. The rendered Audio/Settings layout was inspected.
- A physical lock/unlock cycle and App Store signing were not exercised.
