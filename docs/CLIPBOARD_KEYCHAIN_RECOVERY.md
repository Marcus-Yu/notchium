# Clipboard Keychain investigation and recovery hardening

Date: 2026-10-10. Scope: Clipboard encryption and persistence only. The zero-cost GitHub update objective remains **unresolved**; this is a preservation and recovery hardening patch, not a claim that every ad-hoc update can access the original key automatically.

**Stage 26 follow-up (2026-10-15):** new non-Store Debug and free Release histories now use the same login-Keychain identity. Existing encrypted history can authenticate a read-only candidate from the previously shipped backend. Only after the index and every referenced image authenticate can the same original key be added to an absent canonical non-Store slot and verified. Neither original key nor an existing canonical record is overwritten; no ciphertext is re-keyed. The historical backend decision below describes the October 10 investigation; [the Stage 26 audit](STAGE26_AUDIT.md) records the current implementation, backup verification, tests, and remaining recovery/update blockers.

## Observed failure

The exact executable at `/Applications/Notchium.app` (1.0.0 build 2, arm64, ad-hoc, no entitlements, CDHash `9900aff64a8a97f31d65a1c142abffefbdcba54b`) returned **`errSecItemNotFound` (-25300)** from `SecItemCopyMatching` for the Clipboard key. Its query used generic-password class, service `Notchium.Clipboard`, account `payload-key.v1`, synchronization disabled, and no Data Protection flag. `LAContext` was present.

A temporary native interposition hook captured only public query attributes and OSStatus, and exited before the Clipboard store could decrypt, migrate, save, or clean up. It suppressed system interaction in that diagnostic process only. The installed app was not replaced. A debugger attachment failed and supplied no evidence.

Explicit file-based and Data Protection reads also returned -25300 under the retained Apple Development executable. This establishes that these queries did not return the original key. It does **not** establish permanent key loss, identify the inaccessible access group of any older key, or prove signing changes caused the missing item. No original key was deleted or replaced.

The source configurations differ: free distribution selects the file-based Keychain; development/provisioned builds select Data Protection. The old code collapsed missing keys, entitlement errors, denied access, and invalid key bytes into a generic unavailable message. Existing ciphertext correctly prevented replacement-key generation. The error shown in the installed app is the resulting fail-closed state, not evidence of failed AES-GCM authentication.

## Security decision

Retain the existing profile-specific Keychain backend and service/account identifiers. Explicitly select the backend with `kSecUseDataProtectionKeychain`; do not let a library guess another identifier or silently migrate keys. Keep AES-256-GCM, its existing authenticated identity context, default file-Keychain application ACLs, and non-synchronizing secret storage. Apply `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` only to Data Protection items; file-based protection uses the Keychain's lock state and application ACL instead.

Ad-hoc signatures identify one executable version. A different executable does not satisfy its predecessor's default designated requirement. Isolated native probes reproduced successful creation/read by build A, a system authorization wait by build B, and `errSecAuthFailed` (-25293) from a newly rebuilt B when process-level interaction was suppressed. The query-level authentication UI setting did not reliably suppress the file-Keychain dialog on this host. The agent did not enter credentials or authorize it.

The production patch does not toggle process-wide Keychain interaction settings: that could affect Spotify's separate Keychain calls. It also does not trust all applications, add a bundle-identifier-only requirement, invent signing entitlements, store a plaintext key, or introduce an external Keychain library. Consequently, file-Keychain authorization after an ad-hoc update can still be necessary. There is no demonstrated secure, silent, perpetual ad-hoc update solution in this investigation.

Apple authorities: [TN3137: Mac Keychain APIs and implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains), [TN3127: Code signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), and [code-signing requirement language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html). Apple's Security source was also inspected through Context7.

## Implementation

Changed implementation files are `ClipboardEncryption.swift`, new `ClipboardKeychainAccess.swift`, `EncryptedClipboardStore.swift`, `ClipboardStore.swift`, `ClipboardModel.swift`, and `ClipboardPageView.swift` in `NotchiumClipboardFeature`. `NotchiumApplicationController.swift` passes the existing environment clock into Clipboard. Regression changes are in new `ClipboardKeychainTests.swift` and `ClipboardRetryConcurrencyTests.swift`, plus `ClipboardStorageRecoveryTests.swift`, `Stage16ClipboardTests.swift`, and `Stage23ClipboardSecurityTests.swift`. Documentation changes are this report and the Keychain entry/recovery section in `docs/PERMISSIONS.md`.

- The Clipboard-only native adapter supports injected Security results for isolated tests. Diagnostics log fixed public identifiers, operation, selected backend, and OSStatus; never keys, query/result dictionaries, plaintext, thumbnails, fingerprints, or filenames.
- Reads distinguish item-not-found, invalid key length, exact Security failures, malformed sealed boxes, and AES-GCM authentication failure. Authentication failure can mean a wrong key or changed ciphertext; the UI does not assert which.
- Fresh creation uses CryptoKit randomness and a create-once `SecItemAdd`. A successful add must read back the same 32-byte key before ciphertext can be written. Duplicate creation reads the winner. Failed readback preserves the stored item and blocks writes.
- Existing `.clip` files still prohibit key generation if the key cannot be read. Authentication, decoding, and asset validation must finish before writes/cleanup are allowed. No new key migration was implemented because no original key was retrieved and authenticated.
- Disk initialization and Retry use the existing ordered utility queue through an asynchronous continuation. Memory fixtures keep immediate hydration. Capture and actions are gated until the restored snapshot is committed on the main actor.
- Rapid Retry calls share one owned operation. Only the explicit button allows Data Protection authentication; page access retains the noninteractive request. File-Keychain UI can still be controlled by macOS rather than `LAContext`.
- A 30-second injected-clock deadline replaces the spinner with an actionable authorization/wait message. It does not falsely report an OSStatus or start another native call. Native file-Keychain authorization has no per-call cancellation; a stopped model keeps ownership of that read until it returns. Restart rehydrates before accepting captures, and stale completion cannot replace the model's snapshot.
- Shutdown skips the queue flush while a read/authorization is pending; no model writes are submitted during that hydration. Normal ordered writes still flush. No polling, per-render key reads, plaintext fallback, or new cleanup on unchanged page visits was introduced.

## Verification evidence

Host: macOS 27.0.1, Apple Silicon, Xcode 27.0 (27A266a), Swift 6 language mode. macOS 26 runtime behavior remains unverified.

Focused regression tests cover missing items, missing entitlement, denied/canceled/interaction-required/unavailable Security results, bad key length, failed/mismatched creation readback, duplicate creation, corrupt/authentication-failed ciphertext, interrupted migration evidence, index and image preservation, asynchronous retry, rapid clicks, timeout, cancellation, and stop/start before hydration. Existing tests cover capture/search for all four kinds, encrypted text/image/pin persistence and relaunch, encryption at rest, filesystem safety, and Stage 22 write/cleanup bounds.

The complete practical package suite passed **704 XCTest tests plus 5 Swift Testing tests**. A separate run compiled with `NOTCH_FREE_DISTRIBUTION` passed **37 focused Clipboard tests**. Release-tool safety tests passed (5 tests). Debug and free-distribution Release builds passed. `git diff --check` passed. An independent Swift/security review found no surviving material source defect after the cancellation/restart correction.

Build/test logs and private diagnostic fixtures are under `.build/clipboard-reliability/`. An isolated source snapshot excludes concurrently created volume-control files. Concurrent repository activity committed shared files during this work; this chat did not commit, tag, upload, or publish anything. Clipboard source hashes in that snapshot matched the reviewed source.

The local ad-hoc package audit and additional runtime receipts are recorded in that directory. A successful package audit checks executable architecture, signature, absence of entitlements/helper/debug artifacts, and sealed resources. It does not prove UI persistence or update authorization.

A new validation DMG was created, checksum-verified, mounted read-only, audited, and extracted to a private installation path. Packaged Release A created and read back a disposable 32-byte file-Keychain key with the system default ACL; a second launch retrieved it. Release B contained a real executable change (a generic error-message change in a private source copy), had a different CDHash, and replaced A at that same installation path. Its native read returned **`errSecAuthFailed` (-25293)** with interaction disabled in that diagnostic process. A's CDHash was `d74412fe4ab66befb044193ba8605e9f23829e9d`; B's was `2e68a1a97146602cc5d568ef879f970457061353`.

These probes executed inside the packaged binaries through a temporary interposition hook with isolated service identifiers. They exited before passing any key to the production store. They demonstrate native creation/read/relaunch and the changed-build authorization boundary, not complete GUI capture, ciphertext decryption, pin persistence, or a user-authorized update. No test key was supplied to the user's history. Both disposable Keychain items created by this investigation were removed by exact test-service/account matches; no production Keychain item was deleted. The original installed executable remained unchanged, and a final SHA-256 comparison found all **19 original history files byte-identical** to the pre-diagnosis baseline.

| Required scenario | Evidence / limitation |
|---|---|
| Fresh DMG installation with all entry types and pins | DMG checksum, mounted package audit, private extraction, and packaged native key creation/readback pass. Automated file-store fixtures pass; full isolated GUI persistence remains unverified. |
| Quit/relaunch | Automated encrypted-store/model relaunch passes; the privately installed packaged A retrieves its disposable key after relaunch. Full GUI persistence remains unverified. |
| Different ad-hoc build A → B | Packaged B at the same installation path returns -25293 for A's disposable key with interaction disabled. Silent automatic update compatibility fails this check; authorized GUI update remains unverified. |
| Existing user history recovery | Original key not returned by the tested identities/configurations; history preserved, recovery unresolved. |
| Keychain failure protection | Automated status/readback/preservation/retry matrix passes. |
| Clipboard regression tests | Pass. |
| Full practical suite | 704 XCTest + 5 Swift Testing pass. |
| Debug / Release builds | Pass; separate Clipboard-only snapshot builds exclude concurrent work. |
| Packaged Release | Local structural/signing audit; see private receipts. This is not full GUI update proof. |

## Remaining release gate

Do not claim the installed Clipboard issue is resolved. Recovery needs an authorized mechanism that returns the **original** key, such as an original entitled/authorized executable or an intact Keychain backup. Validate authentication against preserved ciphertext before any future key migration. If the original key is permanently unavailable, encrypted history cannot be recovered; keep its ciphertext rather than resetting it implicitly.

Before approving a release, perform fresh DMG install and two genuinely changed ad-hoc Release installs in a disposable GUI environment, including authorize/deny/cancel paths and real quit/relaunch with all Clipboard kinds and pins. Decide whether explicit Keychain authorization after updates is acceptable for the product. Neither a same-binary relaunch nor fixture tests demonstrate effortless access across every future ad-hoc signature.
