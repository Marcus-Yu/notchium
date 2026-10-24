# Stage 6 Audio

Current expanded-page layout: [shared composition and visual review](EXPANDED_PAGE_COMPOSITION.md).

The Audio page uses `AudioFeatureModel` as its feature state. `RealAudioDevicesService`
owns Core Audio output discovery and commands; `RealAudioProcessesService` owns local
audio-process discovery; `RealAppAudioMixerService` owns the driverless process-tap
graph. The shell receives an `NotchAudioRendering` interface and a small
`NotchAudioHUD` value, so Music, Calendar, and audio state remain independent.

## Output devices and system volume

The device service registers Core Audio property listeners for the device list and
default output. It tracks volume and mute properties on the selected output. It
publishes a bounded `AsyncStream` snapshot when a value changes and removes all
listeners when its final subscriber ends. Output names and write capabilities are
cached until the device list changes. Volume and mute controls are enabled only
when the HAL property is writable across the output's channels. Some digital,
Bluetooth, and virtual outputs expose no software volume or mute control.
Private aggregate devices created by Notchium are removed from the published list
by their owned UID namespace, so they cannot be selected as user destinations.

Switching output writes the default-output property. The UI waits for the HAL's
default-output notification before showing the newly selected device. A successful
set call is not treated as confirmation because Core Audio may apply it later.

## Local audio processes and per-app gain

The process service reads Core Audio process objects and watches the process list,
running-output state, and output-device routes. Before publishing a process, it
creates a private nonmuting probe tap for each active physical output and verifies
the same stereo Float32 input format required by the mixer. Successful routes are
cached for the process lifetime. Processes without a verified route, Notchium's
own process, and internal output devices never reach the page. This event-driven
listener remains available while Audio is enabled so a saved gain can be applied
when an app becomes audible. The page also requires a foreground-capable owning
application and a verified route to the current output. Spotify playback on
another device does not create a local process row.

Recently audible local apps remain in the mixer for three minutes after their output
becomes inactive, including when pausing releases their HAL audio client. Their volume,
mute and reset controls remain available during that grace period. Changes persist by
the owning app's bundle identifier and apply when local playback resumes. Resuming audio
cancels the old expiry; another pause starts a fresh three-minute grace. Repeated inactive
snapshots do not extend it. Closing the owning app removes its rows immediately, including
rows attributed to its audio helper processes. Feature shutdown cancels all expiry work.

The HAL reports active output rather than media Pause/Stop commands, so a generic explicit
Stop and a pause use the same inactivity grace while the app stays open. Retained rows use
their last verified output route; switching to an unverified output hides them until local
playback revalidates that route. The activity dot is gray while output is inactive. Retained
rows are excluded from the live tap graph, so pausing does not keep an audio capture graph
running solely to preserve a slider.

October 22, 2026 validation: all 58 targeted mixer, retention, audio, lifecycle and
architecture tests pass with normal macOS host access, including a simulated 90-second
pause with saved volume changes, exact 180-second expiry and immediate owning-app removal.
The unsigned Debug workspace app build and whitespace checks pass. Live Spotify playback
and pause/resume were not manually exercised.

Per-app gain uses public Core Audio process taps and installs no system audio
driver. Apps at 100% and unmuted continue directly to the selected output. For each
audible app that needs attenuation or mute, the mixer creates one stereo tap scoped
to the current output. The taps and physical output form one private aggregate
device. Each tap uses `mutedWhenTapped`, so direct output is suppressed only while
Notchium's IOProc is actively reading it. The IOProc mixes the captured streams
through per-app gain slots and writes the result to the physical output. Removing
the IOProc, a setup failure, normal termination, or process death releases
suppression and restores normal direct audio.

Volume and mute values persist by bundle identifier. Process appearance, exit, PID
replacement, and output-device changes rebuild the immutable tap topology off the
real-time thread. Plain gain changes update preallocated atomic slots without
rebuilding. The render callback is implemented in `NotchiumRealtimeAudio`: it has
no allocation, locks, logging, UI publication, or I/O and uses compile-time-checked
lock-free 32-bit atomics. It performs only bounded Float32 stereo mixing and final
clipping.

Creating the first process tap, including an eligibility probe, can trigger macOS
System Audio Recording consent using `NSAudioCaptureUsageDescription`. A denied
probe is not published as controllable. If an active mixer loses access, the Audio
page shows a compact permission menu with retry and Privacy & Security actions
while direct app output remains active.

Active output I/O does not prove that samples are non-silent, so an app with a
running silent stream may appear.

## Notch HUD

The long-lived device stream still detects keyboard volume/mute and default-output
changes through HAL property notifications. For Volume Down at 0 and Volume Up at 1,
`RealAudioDevicesService.volumeCommands()` observes key-down/repeat intent through one
session event tap restricted to system-defined events. The default mode is passive:
it reads the current output's HAL controls without changing native input handling.
The optional **Replace macOS Volume HUD** setting switches that same monitor to an active
HID tap after contextual Accessibility education and capability checks. A serial worker
performs route-validated volume/mute operations and returns actual HAL readback. Unsupported
keys and outputs pass through. Failure disables interception and restores passive observation
where available; no permission is requested on launch. `AudioFeatureModel` presents replaced
commands and passive boundary intent through the existing `onHUD` callback. Ordinary passive
interior changes continue to rely on HAL notifications. See [System feedback](SYSTEM_FEEDBACK.md)
for ownership, replay limits, hardware evidence, and the acceptance checks still required.
`showAudioHUD` submits typed notifications
to the shared `NotificationCoordinator`. Volume and mute share one coalescing key and a
1.75-second timeout; output changes use medium priority and a 2.5-second timeout. Repeats
retain identity, update content immediately, and extend expiry without restarting geometry.
Explicit HUD events refresh expiry even at an unchanged value; repeated state snapshots
still do not. The same activity projects into the expanded minor-system shell extension,
leaving the selected page mounted and selected.
The Audio page's own output slider and mute control keep their HAL confirmation feedback
inside that page, including a delayed confirmation after the slider is released. Hardware
volume and mute commands override this inline suppression, so the transient slider still
appears for keyboard buttons while Audio is open. This is tied to command intent rather
than global page visibility, preserving feedback when another display shows a different page.
Lower-priority feedback is discarded while Calendar is visible. The 56 pt Audio content
area uses the same black shell and rounded shoulders as Calendar. Stage 10 keeps the
Music flanks visible throughout Audio entry and exit. Absolute expiry continues while
expanded; collapse only reveals unexpired feedback. No Music notification kinds
or producers exist. See [Unified notifications](STAGE9_NOTIFICATIONS.md) and
[Stage 10 coordination](STAGE10_COORDINATION.md).

Wearable appearance and selection can arrive as separate HAL snapshots. A stable-UID
transition tracker suppresses the second announcement within the existing 2.5-second
connection activity lifetime. Removal clears that suppression so rapid reconnection still
announces. Available output endpoints and the selected route are separate facts; neither
claims universal physical Bluetooth connection truth. Existing device animations remain.

Momentary device/system HUD feedback is discarded on screen or system sleep, and arrivals
while asleep are ignored at the activity source. Wake explicitly settles the retained shell
geometry before the panel returns, so an interrupted AirPods disconnect retraction cannot
keep its expired glyph/status visible. Persistent media/provider state is preserved. See
[shell sleep/wake validation](NOTCH_SHELL.md) for the regression evidence and hardware limit.

## Qualification

The package build and deterministic tests cover navigation, HUD state, persisted
mix targets, direct-output restoration, atomic gain, sample mixing, and the 54 pt
row density. Hardware qualification still needs concurrent app playback, consent,
volume-key repeats, mute, device hot plug, built-in and Bluetooth outputs,
Spaces/fullscreen placement, and CPU observation on a notched Mac.
