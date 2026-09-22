# Stage 6 Audio

The Audio page uses `AudioFeatureModel` as its feature state. `RealAudioDevicesService`
owns Core Audio output discovery and commands; `RealAudioProcessesService` owns local
audio-process discovery. The shell receives an `NotchAudioRendering` interface and a
small `NotchAudioHUD` value, so Music, Calendar, and audio state remain independent.

## Output devices and system volume

The device service registers Core Audio property listeners for the device list and
default output. It tracks volume and mute properties on the selected output. It
publishes a bounded `AsyncStream` snapshot when a value changes and removes all
listeners when its final subscriber ends. Output names and write capabilities are
cached until the device list changes. Volume and mute controls are enabled only
when the HAL property is writable across the output's channels. Some digital,
Bluetooth, and virtual outputs expose no software volume or mute control.

Switching output writes the default-output property. The UI waits for the HAL's
default-output notification before showing the newly selected device. A successful
set call is not treated as confirmation because Core Audio may apply it later.

## Local audio processes

The process service reads Core Audio process objects, watches the process list and
each process's running-output property, and publishes only processes with active
output I/O. It starts when the expanded Audio page is visible and removes its
listeners when the page closes. The page filters to foreground-capable apps and
allows an app to be activated or pinned for ordering. A pinned app appears again
when it next produces local audio. Spotify playback on another device does not
create a local process row.

Core Audio's public process properties provide output activity but no general
per-application gain or mute setter for another app. A process tap can capture or
mute original output, but implementing independent gain with that route requires
rerouting and mixing captured audio. Stage 6 deliberately does not create an audio
driver or virtual device. Accordingly the page does not show per-app sliders or
mute/reset actions that would not work. Active output I/O does not prove that
samples are non-silent, so an app with a running silent stream may appear.

## Notch HUD

The long-lived device stream detects keyboard volume and mute changes through HAL
property notifications. It also detects a new default output. The presentation
model updates one HUD value in place for key repeats, resets a 1.25-second expiry
task, and uses the existing top-anchored panel and shell mask. It does not create
another window. The HUD temporarily hides the collapsed Music and Calendar content;
their state remains intact and reappears when the HUD expires. System volume never
changes Spotify Connect playback volume.

## Qualification

The package build and deterministic tests cover navigation and HUD state. Hardware
qualification still needs volume-key repeats, mute, device hot plug, built-in and
Bluetooth outputs, Spaces/fullscreen placement, and CPU observation on a notched Mac.
