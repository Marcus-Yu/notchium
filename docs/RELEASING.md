# Free GitHub distribution

Stage 24 supersedes the historical Developer ID/notarization requirement for
v1 public releases. Distribution uses local Xcode tools and GitHub Releases,
without paid CI, certificates, provisioning, notarization, hosting, or an updater.

## Identity audit before Stage 24

| Item | Observed state |
|---|---|
| App / bundle / executable | Notchium / `com.marcusyu.notchium` / `Contents/MacOS/Notchium` |
| Version / build | 0.1.0 / 1 |
| Minimum macOS | 26.0 in Xcode settings and Swift package |
| Architecture | Release settings request arm64 and x86_64; existing Stage 23 Release binary is arm64, verified with `lipo -info`. Universal was not established. |
| Signing | Automatic Apple Development; development team configured |
| Hardened Runtime / Sandbox | Both NO in effective Release settings |
| Entitlements | Keychain access group using a provisioned prefix, calendar, camera |
| Capabilities | Focus communication entitlement absent; public Focus adapter reports unavailable |
| Usage descriptions | Camera, Calendar full access, Reminders full access, system audio, Focus |
| Embedded code | Team-authenticated closed-lid launch daemon; no app extensions or external package dependencies |
| Resources | App icon assets and SwiftPM media asset bundle |
| Release/debug information | Release config; DWARF; developer UI and launch fixtures guarded by DEBUG |

The current configuration is version **1.0.0**, build **2**, macOS **26.0+**.
The release command explicitly builds **arm64** and verifies every executable.
Intel/universal support requires a separate validated release change; do not infer
it from Xcode's default architecture list. Validate on macOS 26 before claiming
runtime coverage at the deployment minimum.

## Export and entitlement decisions

The script builds Release with Xcode certificate signing disabled, copies the
app, then applies a local **ad-hoc** signature without entitlements or a timestamp.
This provides Mach-O execution validity/resource sealing on Apple Silicon; it is
not trusted distribution signing. No certificate, Personal Team, Apple Development
identity, Developer ID, or notarization service is used.
This is the command-line build/copy equivalent of
[Xcode's Copy App distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases),
with the minimum local signature needed for the chosen executable platform.
Release enables dead-code stripping, and the copied executable's debugging
symbols are stripped before ad-hoc sealing. Its generated dSYM remains separate
for crash diagnosis; mock factories/provider and fixture artwork are compiled
only in Debug. Clang coverage mapping is disabled explicitly to keep the profiling
runtime out of Release. Developer fixtures and local paths must pass the byte scan.

| Entitlement/capability | Classification and free-build decision |
|---|---|
| `keychain-access-groups` with `AppIdentifierPrefix` | Provisioning-dependent; omit. Spotify already uses login Keychain. Clipboard Data Protection Keychain fails with OSStatus -34018 without provisioned entitlement; free builds use login Keychain and retain AES-GCM encryption. |
| `com.apple.security.personal-information.calendars` | Sandbox entitlement unnecessary in this non-sandboxed, non-hardened build; Calendar TCC and usage string still required. |
| `com.apple.security.device.camera` | Unnecessary with this runtime policy; Camera TCC and usage string still required. |
| Communication Notifications / Focus | Provisioning-dependent, absent; preserve existing “Unavailable in this build” behavior. |
| Apple-anchored closed-lid XPC identity | Release blocker if bundled: app/helper require a matching Apple-trusted team signature. Free build omits daemon and disables only its controls. Requirements are never weakened. Ordinary Caffeine is preserved. |
| App Store entitlement file | Not used. Sandbox, network, file/bookmark entitlements describe a separate future edition. |

The free Swift condition must reach **all SwiftPM modules**, not just the app
target. `release.sh` supplies `OTHER_SWIFT_FLAGS=-D NOTCH_FREE_DISTRIBUTION` to
Xcode and runs a separate SwiftPM free-profile regression test.
Debug retains its original profile. Provisioned clipboard histories are not
automatically re-keyed; existing unreadable files must remain preserved.

## Repeatable command

Before a publishable build:

1. Review and commit all intended production changes, including the outstanding
   Stage 21–23 edits, new Home settings source, and Stage 24 configuration,
   scripts, tests, README, MIT license, notices, and release documentation.
   Decide whether the untracked CLAUDE/workspace files belong in the commit.
   Local `.DS_Store` and profiling output are ignored and never packaged.
2. Set `MARKETING_VERSION` to the requested version and increment
   `CURRENT_PROJECT_VERSION` above every prior semantic release tag's build.
3. Create an annotated `v1.0.0` tag on that reviewed commit using your normal
   Git workflow. The script never commits, tags, pushes, or publishes.
4. Run:

```sh
./scripts/release.sh 1.0.0
```

The script rejects a dirty tree, wrong version, missing license, wrong tag,
existing output directory, unexpected code/dependencies/permissions, secret
patterns, developer paths, debug markers, or failed tests/builds. It builds from
an isolated `git archive` of the tagged commit, so changes made in the checkout
during compilation cannot enter the artifact.
Use Xcode 27 (the validated toolchain) and its Swift compiler, plus Python 3.9
or later. Keep at least 1.5 GiB free for the sequential build stages. The script
removes only its own temporary build directories between stages. Build numbers
use the single-integer CFBundleVersion form, 1–9999; increment it for every release.

For local validation of unfinished work:

```sh
./scripts/release.sh 1.0.0 --preview
```

Preview takes an isolated snapshot of tracked and non-ignored untracked files,
including working-tree changes/deletions. It records file hashes and the base
commit. Its artifact has a **-preview** suffix and its release notes explicitly
prohibit publication. Rebuild from the clean tag for the final public filename.
Preview still runs the full package suite, but records a failure and continues
independent build/packaging checks so an existing product failure can be reviewed.
A normal release stops immediately on a failed test. Neither path skips tests.
Xcode builds use `Notchium.xcworkspace`, which supplies the local package;
building the standalone project cannot resolve its package product.

The default is a minimal compressed, read-only DMG with `Notchium.app` and an
`Applications` symlink. No custom background, Finder scripting, installation
scripts, helpers, or privileged installer is added. If disk-image creation is
unavailable, inspect the failure and rerun with `--zip` in a new output location
after preserving the failed logs. Both formats are extracted/mounted and their
bundled app is re-audited. No tooling is downloaded.

## Outputs and integrity

`dist/1.0.0/` contains:

- `Notchium-1.0.0.dmg` (or ZIP) and its exact-filename `.sha256`.
- `Notchium.app`, copied back from the packaged artifact.
- `release-notes.md` with measured size, SHA-256, and commit filled in.
- `release-manifest.json` with source file hashes, toolchain, version/build,
  architecture, and pending manual acceptance.
- `logs/` and `symbols/` for local review/crash diagnosis only.

Upload **only the DMG/ZIP and checksum**. Logs can contain build paths and
diagnostic details; never upload logs, symbols, source snapshots, credentials,
or the whole `dist` directory. A checksum downloaded from the same compromised
account cannot protect against account takeover; review the tag, use HTTPS,
protect GitHub access, and keep a local copy of the hash.

The artifact scan checks known token/private-key patterns, bundle inventory,
permissions, symlinks, executable dependencies, architectures, usage strings,
ad-hoc signing, resource seals, and local-path/debug leakage. It is a heuristic
review, not a proof that every possible secret or personal datum is absent.
Only compiled source/resources enter the app; user Application Support, Keychain,
clipboard/calendar contents, screenshot files, and bookmarks are never copied.
No GitHub signing secrets or workflow are required. Review account secrets in
GitHub separately; the local script has no account access.

## Manual acceptance — required before publishing

Use a fresh macOS user account or a second Mac that has never run this bundle.
Use an actual browser download of the candidate (or local HTTPS test download
that receives normal browser quarantine). A plain local copy may not be
quarantined and cannot establish Gatekeeper behavior. Do not alter quarantine
or security policy to manufacture a pass.

Record candidate SHA-256, macOS version, CPU, account freshness, and outcomes:

1. Open the DMG/ZIP, drag/copy Notchium to Applications, eject the image.
2. Double-click Notchium. Record the exact first-launch warning.
3. Follow **System Settings → Privacy & Security → Security → Open Anyway**;
   confirm Open. Record whether macOS offered and accepted the exception.
4. Verify the menu-bar/notch UI, then quit and launch again normally.
5. Exercise Calendar allow/deny, Quick Reminder, Mirror allow/deny and close,
   system audio capture allow/deny, and screenshot-folder access. Existing TCC
   approvals on the development Mac do not establish fresh-user correctness.
6. Check Home shortcuts, Spotify Connect/media, Shelf import/export/share/AirDrop,
   opt-in Clipboard save/relaunch, Pomodoro, ordinary Caffeine, volume HUD,
   a screenshot activity, and one real download including Done/Stopped.
7. Confirm Focus and closed-lid mode are unavailable without administrator prompts.
8. Check saved settings after relaunch, fullscreen/display switching, accessibility,
   Reduce Motion, and the representative Stage 22/23 lifecycle regressions.
9. Verify macOS 26 on available hardware. macOS 27-only testing is insufficient
   to claim runtime acceptance at the minimum deployment version.

`spctl --assess --type execute` is expected to reject an ad-hoc/unnotarized
app as an identified-developer distribution. Record this separately from a
successful local launch; it does not itself test the user exception flow.
Managed Macs may disallow user overrides. See
[Apple's supported flow](https://support.apple.com/102445).

## Publishing (manual, after acceptance)

1. Push the reviewed commit and `v1.0.0` tag when authorized.
2. Open [New GitHub Release](https://github.com/Marcus-Yu/notchium/releases/new),
   choose `v1.0.0`, title **Notchium 1.0.0**, and paste `release-notes.md`.
3. Attach the final artifact and its `.sha256`; compare names, size, and checksum
   against the local manifest. Publish only after the acceptance above passes.
4. Download the published asset once and confirm its SHA-256 matches.

Source availability/licensing is separate from a Release attachment. GitHub
automatically offers source archives for a tag; review the committed repository
for secrets before pushing. MIT was selected by the owner for this public repo.
No automatic updater is added. Users check GitHub Releases manually.
