# Stage 6 Audio

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

The long-lived device stream detects keyboard volume and mute changes through HAL
property notifications. It also detects a new default output. The presentation
model updates one HUD value in place for key repeats, resets a 1.25-second expiry
task, and uses the existing top-anchored panel and shell mask. It does not create
another window. The HUD temporarily hides the collapsed Music and Calendar content;
their state remains intact and reappears when the HUD expires. System volume never
changes Spotify Connect playback volume.

## Qualification

The package build and deterministic tests cover navigation, HUD state, persisted
mix targets, direct-output restoration, atomic gain, sample mixing, and the 54 pt
row density. Hardware qualification still needs concurrent app playback, consent,
volume-key repeats, mute, device hot plug, built-in and Bluetooth outputs,
Spaces/fullscreen placement, and CPU observation on a notched Mac.
