# Notchium

Notchium brings media, everyday tools, and live activities to your Mac's notch.

## Download

Get packaged builds from the official [GitHub Releases](https://github.com/Marcus-Yu/notchium/releases).
The first public release is being prepared; local preview artifacts are for validation only.

## Features

- Media controls, Spotify Connect, and an audio waveform.
- Calendar events, meeting links, and quick reminders.
- Download and screenshot activities, Shelf, AirDrop, and sharing.
- Clipboard history, Pomodoro, Mirror, and Caffeine.
- Audio controls, system HUDs, Home shortcuts, and macOS Shortcuts.

## Requirements

- macOS 26.0 or later.
- Apple Silicon (arm64). Intel Macs are not supported by the v1 release script.
- Spotify features require Spotify authorization and an eligible account; playback control depends on Spotify's account and API restrictions. Configure your own Spotify client ID in Settings.

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

Notchium uses these permissions for the corresponding features:

| Permission | Purpose |
|---|---|
| Calendars | Show selected calendar events and meeting links. Calendar access may be requested when its service starts. |
| Reminders | Add a reminder when you use Quick Reminder. |
| Camera | Show the live Mirror preview when you open it. |
| Screen & System Audio Recording | Capture app audio in memory for app volume control and the Spotify waveform. No microphone input is used. |
| Files & Folders | Show download progress and completed files in Downloads, observe saved screenshots in your configured folder, and access files you choose. |

Clipboard History is opt-in in Settings and reads the macOS pasteboard while
enabled; macOS does not provide a separate Clipboard permission switch.
Shelf uses files you drop or select. The app does not require Accessibility,
Automation, Full Disk Access, or administrator approval in this free build.
Denied permissions leave the corresponding feature unavailable; other tools remain usable.

## Privacy

- Clipboard history is processed locally. Persisted payloads use AES-GCM encryption;
  the free build stores its encryption key in the local login Keychain.
- Shelf copies and saved screenshot files stay on your Mac unless you explicitly
  export or share them. Screenshot activities observe files saved by macOS.
- Mirror uses a live camera preview while open; it does not record or save frames.
- Audio processing uses in-memory buffers and does not save recordings.
- Spotify authorization and playback requests go to Spotify APIs. Artwork is fetched
  from the URLs supplied by Spotify; access tokens are stored in Keychain.
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
