# Stage 7 utility validation — 2026-09-24

## Results

- SwiftPM utility tests: 9 passed, 0 failures. Includes Caffeine click modes, green-to-blue, 749/750 ms deadline, completed-hold click consumption, early release, cancellation, permission guidance, Secure Input guidance, and unlocked real callback pass-through.
- Privileged power adapter harness: passed acquire, idempotent renewal, release, foreign ownership rejection, unsafe-condition rejection, crash recovery, and restoration retry. Fake command runner; no real power settings changed.
- Debug workspace app build and embedded helper build: succeeded with Swift 6 strict concurrency.
- App and nested helper: `codesign --verify --deep --strict` succeeded outside the restricted sandbox.
- Project/plist validation, shell syntax, and `git diff --check`: passed.
- Existing running build: TextEdit baseline `abc123` appeared. With UI showing Locked, automated `abc123` and `a` still appeared. Mouse unlock worked. Automated targeted input is not proof of physical keyboard behavior.
- System diagnostic: `IsSecureEventInputEnabled()` returned true. Event-tap inventory showed the existing app's active session tap enabled with the full keyboard mask (7168). An enabled tap alone did not establish keyboard coverage under Secure Input.
- Updated running build: clicking Keyboard Lock showed the specific Secure Input unavailable alert; UI remained Unlocked. Verified new closed-lid Settings section exists and defaults off.
- Updated Caffeine: native UI clicks verified neutral → green → neutral. The timed hold border and long-press completion were covered by code/state tests, not a physical timed-hold visual test.

## Outstanding acceptance tests

**Keyboard Lock is not yet accepted as fixed end-to-end.** Secure Input must be off, then a physical keyboard must verify browser and TextEdit suppression for abc123, Cmd+A/C/V, Return, Space, and arrows; normal typing after mouse unlock; and Command–Option–Escape held two seconds with early-release cancellation. Computer-use targeted input may bypass a session tap and cannot substitute for those physical tests.

**Closed-lid operation is unverified on hardware.** The helper is built and signed but has not been registered or granted administrator approval by this task. No `pmset` mutation or root daemon installation was performed. Live tests require approval and physical lid closure on AC and battery, including off/exit/crash restoration. See [LID_AWAKE.md](LID_AWAKE.md).

## Files changed by this task

Existing unrelated working-tree edits were preserved. This task edited or added only:

- `NotchiumPackage/Sources/NotchiumCaffeineFeature/CaffeineControlModel.swift`
- `NotchiumPackage/Sources/NotchiumCaffeineFeature/LidAwakeSettingsSection.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/CaffeinePressButtonStyle.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchUtilityControlling.swift`
- `NotchiumPackage/Sources/NotchiumDynamicIsland/NotchSettingsButton.swift` (utility behavior and error guidance)
- `NotchiumPackage/Sources/NotchiumKeyboardLockFeature/KeyboardLockControlModel.swift`
- `NotchiumPackage/Sources/NotchiumServices/KeyboardLockService.swift`
- `NotchiumPackage/Sources/NotchiumServices/LidAwakeController.swift`
- `NotchiumPackage/Sources/NotchiumServices/LidAwakeProtocol.swift`
- `NotchiumPackage/Sources/NotchiumFeature/NotchiumSettingsView.swift` (closed-lid section only)
- `NotchiumPackage/Tests/NotchiumFeatureTests/UtilityControlTests.swift`
- `Notchium/NotchiumApp.swift` (Settings injection only)
- `Notchium.xcodeproj/project.pbxproj` (helper packaging phase)
- `Helpers/LidAwake/main.swift`
- `Helpers/LidAwake/PowerOverride.swift`
- `Helpers/LidAwake/com.marcusyu.notchium.lid-awake.plist`
- `Helpers/LidAwakeTests/main.swift`
- `scripts/build-lid-awake-helper.sh`
- `docs/ARCHITECTURE.md`
- `docs/PERMISSIONS.md`
- `docs/PRODUCT_SPEC.md`
- `docs/LID_AWAKE.md`
- `docs/STAGE7_UTILITY_VALIDATION.md`
