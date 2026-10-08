# Third-party notices

The app's Swift package has no external package dependencies. Its C audio
bridge and privileged-helper sources are maintained in this repository. Apple
system frameworks and Swift runtime libraries are supplied by macOS; they are
not separately downloaded or copied by the release script.

## Spotify

The bundled Spotify logo is used to identify Spotify content. Spotify and its
logo are trademarks of Spotify AB. Spotify branding, artwork, and metadata are
not licensed under Notchium's MIT license. Notchium is not endorsed by Spotify.

Use of Spotify services remains subject to Spotify's
[Developer Terms](https://developer.spotify.com/terms),
[Developer Policy](https://developer.spotify.com/policy), and
[Design and Branding Guidelines](https://developer.spotify.com/documentation/design).
The existing player displays Spotify attribution and links to Spotify content.
No Spotify credentials, music, or fetched album artwork are included in the
release bundle.

This notice is copied into `Notchium.app/Contents/Resources` together with the
project's MIT license. Recheck notices whenever a dependency or asset is added.
