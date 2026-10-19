# Notchium

Notchium brings media, everyday tools, and live activities to your Mac's notch.

## Download

Get packaged builds from the official [GitHub Releases](https://github.com/Marcus-Yu/notchium/releases).
The first public release is being prepared; local preview artifacts are for validation only.

## Features

- Local Spotify controls and an audio waveform.
- Calendar events, meeting links, and quick reminders.
- Download and screenshot activities, Shelf, AirDrop, and sharing.
- Clipboard history, Pomodoro, Mirror, and Caffeine.
- Audio controls, system HUDs, Home shortcuts, and macOS Shortcuts.
- Built-in display by default, with independent notches on all displays or a selected monitor. Configure display placement and optional notch shapes in Settings → General → Displays.

## Requirements

- macOS 26.0 or later.
- Apple Silicon (arm64). Intel Macs are not supported by the v1 release script.
- Install Spotify on this Mac, open it, and choose Enable Local Control in Music or Settings → Media. Allow the macOS Automation prompt. No Spotify developer account, client ID, or login in Notchium is required. Queue access and remote Spotify Connect device selection are unavailable.

## Installation

1. Download `Notchium-1.0.0.dmg` from the official release.
2. Open the disk image and drag **Notchium** to **Applications**.
3. Eject the disk image and open Notchium from Applications.

If a release provides a ZIP instead, unzip it and move Notchium to Applications.
Install only the app; there is no package installer or installation script.

## macOS security warning

Notchium is distributed without Apple Developer ID signing or notarization because
this release uses a zero-cost distribution model. Its local ad-hoc signature
provides no Apple-trusted developer identity, and Apple has not verified this binary.

If macOS blocks the first launch:

1. Try opening Notchium from Applications once.
2. Open **System Settings → Privacy & Security**.
3. Scroll to **Security**, find the Notchium message, and click **Open Anyway**.
4. Confirm **Open**, authenticating if macOS asks.

macOS saves an exception for that app, so future launches normally work.
The button is available for a limited time after the launch attempt. Managed
Macs may restrict exceptions. This follows
[Apple's documented approval flow](https://support.apple.com/102445).
If macOS reports damage or malware, stop and report the exact message rather
than changing your Mac's security policy.

Each release includes a SHA-256 checksum of its download. It detects changed
bytes when compared with the official release's value; it does not identify the
developer or substitute for Apple verification. Download both from the official repository.

## Permissions

New profiles complete a one-time setup before normal use. Setup introduces every
implemented requirement and requests supported authorizations one at a time.
Completed setup persists across relaunches and updates. Returning installations keep
their existing configuration; access can be reviewed in Settings → Permissions.

Notchium uses these permissions for the corresponding features:

| Permission | Purpose |
|---|---|
| Calendars | Show selected calendar events and meeting links. Full access is requested during setup. |
| Reminders | Add a reminder when you use Quick Reminder. |
| Camera | Show the live Mirror preview when you open it. |
| Automation (Spotify) | Show the current song and control Spotify on this Mac. Setup verifies the running Spotify target before requesting consent. |
| System Audio Recording | Capture app audio in memory for volume control and the Spotify waveform. Core Audio asks when capture first starts; setup explains this exception without recording. No microphone or Screen Recording request is used. |
| Accessibility | Optional volume-HUD replacement uses Accessibility trust and event-post access. Granting access does not enable replacement. |
| Selected files and folders | Setup selects a screenshot folder. Shelf and Quick Actions use native selections and bookmarks for specific items; there is no universal file grant. |

Clipboard History defaults off. Setup requires an explicit Enable or Keep Off choice;
monitoring starts only after setup and only with opt-in. macOS pasteboard privacy remains
separate and may require a system decision on future reads. Setup never reads the Clipboard.
Available required permissions must be granted to finish setup; denied choices have a
System Settings recovery path and a safe quit/resume path. Genuine unavailable and
non-pregrantable requirements need explicit review. No Full Disk Access or administrator
approval is requested in the free build. See [the permission contract](docs/PERMISSIONS.md).

## Privacy

- Clipboard history is processed locally. Persisted payloads use AES-GCM encryption;
  the free build stores its encryption key in the local login Keychain.
- Shelf references and saved screenshot files stay on your Mac unless you explicitly
  export or share them. Screenshot activities observe files saved by macOS.
- Mirror uses a live camera preview while open; it does not record or save frames.
- Audio processing uses in-memory buffers and does not save recordings.
- Spotify playback is read and controlled locally through macOS Apple Events. Only
  album artwork is downloaded from Spotify’s artwork CDN. No OAuth tokens are used.
- The production source contains no telemetry or analytics service. Local macOS
  diagnostic logging records app/service status; it is not uploaded by Notchium.
- Home actions, meeting links, and Share/AirDrop may open other apps or websites
  at your request; those services have their own privacy policies.

## Known limitations

- **Focus:** Unavailable in this free build because the required Apple entitlement
  cannot be provisioned through the current development team. The implementation
  remains in place, and Pomodoro works independently.
- **Closed-lid keep-awake:** Unavailable in the free build. Its privileged helper
  requires an Apple-trusted signing identity and is omitted from the download.
  Ordinary Caffeine still prevents idle sleep with the lid open.
- **Keychain upgrades:** Ad-hoc releases may require Keychain approval again after
  an update. Clipboard history from a provisioned development build uses a different
  Keychain backend and is not migrated automatically; unreadable history is preserved.
- The current v1 artifact supports Apple Silicon only. First-run permission and
  Gatekeeper acceptance on a fresh user/Mac must be completed before publication.

## Issues and feedback

Report reproducible problems in [GitHub Issues](https://github.com/Marcus-Yu/notchium/issues).
Include your macOS version and Notchium version. Do not attach clipboard history,
calendar contents, credentials, or private screenshots.

## Building a release

The [release guide](docs/RELEASING.md) describes the local command, clean Git tag,
artifact checks, and manual first-run acceptance. Updates are downloaded manually
from GitHub Releases.

## License

Notchium source and binaries are available under the [MIT license](LICENSE).
Third-party branding and content retain their owners' terms; see
[third-party notices](THIRD_PARTY_NOTICES.md).
