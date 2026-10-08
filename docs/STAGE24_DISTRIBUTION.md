# Stage 24 distribution verification

This is a local release-engineering receipt, not permission to publish. Nothing
has been committed, tagged, pushed, uploaded, notarized, or published by this stage.

## Candidate and changes

- Base commit: `a665158f48bcb3812063f08c35061d4da5a0f99f`.
- The checkout includes uncommitted Stage 21–23 work. Preview snapshots preserve
  it; a final release must come from a reviewed clean commit and `v1.0.0` tag.
- Version 1.0.0, build 2, deployment target macOS 26.0, selected release CPU arm64.
- Local build/copy export with ad-hoc sealing; no certificate or provisioned
  entitlement, no Hardened Runtime, no App Sandbox, no privileged helper in the
  free artifact. Focus architecture and its unavailable state remain intact.
- Ordinary Caffeine remains available. Closed-lid controls report unavailable
  because their existing mutual XPC authentication requires trusted team signing.
- Free clipboard builds retain AES-GCM encryption and use login Keychain rather
  than the provisioned Data Protection Keychain backend. Existing unreadable
  development histories are preserved, not silently replaced or re-keyed.
- Folder usage descriptions now cover the implemented Downloads observer and
  screenshot observation in protected Desktop/Documents locations.
- MIT was selected by the repository owner. No external package dependency
  licenses are needed; Spotify branding remains under Spotify's terms.

## Validation observed so far

Host: Apple Silicon, macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6 language
mode. The workspace, not the standalone project, resolves the local package.

| Check | Observed result |
|---|---|
| Release-tool safety regression suite | 5 tests passed |
| Production source scan | 223 files; no secret-pattern findings |
| Production Git history scan | 920 blobs; no secret-pattern findings |
| Full Swift package suite | Latest checkout run: 692 XCTest cases plus 5 Swift Testing cases passed |
| Transfer terminal-state stress | Latest runs: 5,040 permutations / 15,120 transfers, zero failures |
| Free-profile regression tests | 2 passed: compiled profile and unavailable helper controls |
| Login Keychain compatibility probe | Create/read/delete succeeded; Data Protection variant returned -34018 |
| Actual free clipboard encryption probe | Key create/read, AES-GCM seal/open, and isolated-service cleanup passed |
| Clean Debug build | Passed |
| Clean Release build | Passed; extracted DMG app passes the complete artifact audit |
| macOS UI suite | 17 existing Debug fixture tests passed; earlier disk-blocked attempt superseded |
| `git diff --check` | Passed on the reviewed changes |
| Packaged launch / relaunch | Passed from `/Applications/Notchium.app`; shell/Settings rendered, normal quit and new process observed |
| Free capability state in actual packaged UI | Closed-lid controls disabled with explanation; Focus reports unavailable |
| Gatekeeper command-line assessment | `spctl --assess --type execute` rejected (exit 3); no security settings changed |
| Browser-quarantined fresh user Gatekeeper / Open Anyway | Pending; existing TCC permissions are not proof |
| macOS 26 hardware / fresh permissions / representative live features | Pending |

The first full test run had one intermittent transfer-ordering failure (120 of
5,040 orderings); the next two completed runs passed without transfer-code or
test changes. Its log is retained in
`dist/1.0.0-preview-first-test-failure/logs/package-tests.txt`. Do not erase that
history or describe every run as passing.

The final packaging invocation's snapshot included a newly added compact-media
layout test that failed four placement assertions. The test was updated in the
checkout during validation; no media layout changes were made by Stage 24.
A subsequent complete checkout suite passed all 692 XCTest and 5 Swift Testing
cases. The packaged production source hashes still match the checkout. The
original preview manifest correctly retains `package_tests: failed`, alongside
the original snapshot hashes; `local-validation.json` records the later passing
suite and installed-app evidence separately. A clean tagged rebuild must include
the reviewed current test, rather than treating the earlier preview as final.

The initial artifact audit rejected a hard-coded mock directory and fixture
artwork URLs in the Release executable. Mock environment/registry factories,
the mock media provider, and fixture artwork rendering now compile only in
Debug. The diagnostic Release binary passes the path/fixture byte checks after
symbol stripping. Effective Release settings originally had dead-code stripping
disabled. The linker also pulled in the profiling runtime despite
`ENABLE_CODE_COVERAGE=NO`: Xcode's separate Clang coverage-mapping linker policy
needed explicit disabling. The corrected binary contains no profiling markers;
the verifier rejects them in every future artifact. The finished DMG was mounted
read-only, its Applications link checked, its extracted app re-audited, and its
exact-filename SHA-256 verified. The installed app's executable hash matches the
app copied back from the image. Local launch used existing development-account
state; it establishes neither browser-quarantined approval nor fresh permissions.

## Local preview files

Directory: `dist/1.0.0-preview/` (ignored, never upload this preview).

- `Notchium-1.0.0-preview.dmg`: **3,638,803 bytes**.
- SHA-256: `a43c0b29f9198abd0212881ae7113d081f66f8b99ae3f03595d082a9e54932c1`.
- Matching `.sha256`, extracted `Notchium.app`, generated release notes,
  source/toolchain manifest, private logs, separate dSYM, and local validation receipt.
- `/Applications/Notchium.app` is the installed copy tested locally, left quit.

This is a validated packaging preview, not a publishable tagged candidate.
No ZIP was produced; that fallback remains available through `--zip`.

## Security and release review

The available `security-review`, Apple project-governance, Swift code-review,
Apple device-validation, and XcodeBuildMCP skills were read and applied. The
named STRIDE, code-review-excellence, write-swift, debugging, and
verification-before-completion skills were not found in the available skill
locations; their relevant checks were covered directly. XcodeBuildMCP tools are
not exposed, so local Xcode tools were used. Apple-design guidance was applied
only to restrained install instructions and DMG presentation.

| STRIDE category | Release control / remaining boundary |
|---|---|
| Spoofing | Official HTTPS repository/release links; no claim of an Apple-verified identity. GitHub account protection remains the publisher's responsibility. |
| Tampering | Exact-filename SHA-256, ad-hoc resource verification, read-only image, packaged-app reinspection. Same-account checksum publication cannot authenticate against an account takeover. |
| Repudiation | Immutable tagged source for normal builds; preview source-file hashes, base revision, toolchain and measured artifact metadata. No automatic publishing actions. |
| Information disclosure | Production/history secret scan, byte-level path/secret audit, explicit bundle inventory. User stores/Keychain data are never inputs. Build logs and dSYMs stay outside the download. GitHub account secrets were not accessible or audited. |
| Denial of service | Fail-fast checks, disk-space preflight, sequential build stages, no overwritten output, safe mktemp cleanup. One intermittent existing product test is recorded above. |
| Elevation of privilege | Free artifact omits the daemon; existing authenticated-helper requirements are preserved. No installer, postinstall, Gatekeeper/quarantine modification, shell interpolation into privileged operations, or global security change. |

Swift changes are limited to the free profile, capability gating, clipboard
Keychain selection, settings availability, and exclusion of Debug fixtures. Product, activity,
media, transfer, persistence-format, and lifecycle architecture are preserved.
The script quotes paths, validates versions/builds, does not remove arbitrary
directories, and writes only new local output plus its own temporary work.
Review completeness: release-supporting code/configuration and relevant Swift
boundaries reviewed; native first-run and minimum-OS acceptance remain unverified.

## Final acceptance and publication

Use [RELEASING.md](RELEASING.md) for the exact local command and fresh-user
installation checklist. The only upload assets will be the final DMG/ZIP and its
checksum, built from the clean tag after acceptance. Preview filenames, build
logs, rejected binaries, symbols, and source snapshots must not be uploaded.
