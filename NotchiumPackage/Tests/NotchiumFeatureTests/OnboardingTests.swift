import Foundation
import AppKit
import XCTest
import NotchiumCore
import NotchiumPersistence
import NotchiumServices
@testable import NotchiumFeature

@MainActor final class OnboardingTests: XCTestCase {
    func testFreshProfileStartsWelcomeAndWritesBeforeFeaturesSeedPreferences() throws {
        let store = InMemoryOnboardingStore()
        let permissions = SetupTestPermissions()
        let model = OnboardingModel(store: store, permissions: permissions)
        XCTAssertTrue(model.requiresOnboarding)
        XCTAssertEqual(model.state.step, .welcome)
        XCTAssertNotNil(store.state)
        XCTAssertTrue(permissions.requests.isEmpty)
        XCTAssertTrue(model.canFinish)
    }

    func testLegacyMigrationIsSeparateFromVerifiedSetupAndPreservesConfiguration() {
        let store = InMemoryOnboardingStore()
        store.legacy = true
        let model = OnboardingModel(store: store, permissions: SetupTestPermissions())
        XCTAssertFalse(model.requiresOnboarding)
        XCTAssertEqual(model.state.completion, .legacyRecognized)
        XCTAssertNotEqual(model.state.completion, .userCompleted)
        XCTAssertNil(model.state.clipboardChoice)
    }

    func testPartialSetupWinsOverLegacyEvidenceOnRelaunch() {
        let store = InMemoryOnboardingStore()
        let first = OnboardingModel(store: store, permissions: SetupTestPermissions())
        first.select(.camera)
        first.chooseClipboard(false)
        store.legacy = true
        let resumed = OnboardingModel(store: store, permissions: SetupTestPermissions())
        XCTAssertTrue(resumed.requiresOnboarding)
        XCTAssertEqual(resumed.current, .camera)
        XCTAssertEqual(resumed.state.step, .permissions)
        XCTAssertEqual(resumed.state.clipboardChoice, false)
    }

    func testDeniedPermissionRemainsDeniedButDoesNotBlockCompletion() async {
        let permissions = SetupTestPermissions()
        permissions.values[.calendar] = .init(.denied)
        let model = OnboardingModel(store: InMemoryOnboardingStore(), permissions: permissions)
        await model.refresh()
        model.chooseClipboard(false)
        model.select(.calendar)
        model.acknowledgeCurrent()
        XCTAssertFalse(model.state.reviewed.contains(.calendar))
        XCTAssertTrue(model.canFinish)
        model.finish()
        await waitUntilIdle(model)
        XCTAssertFalse(model.requiresOnboarding)
        XCTAssertEqual(model.state.step, .ready)
        XCTAssertEqual(model.statuses[.calendar]?.authorization, .denied)
        XCTAssertNil(model.error)
    }

    func testEveryMissingGrantAllowsCompletionWithoutRequestsOrReviews() async {
        for state in [SetupAuthorization.notDetermined, .denied, .needsSystemSettings,
                      .needsFullAccess, .requiresUserSelection, .requiresApplication] {
            let permissions = SetupTestPermissions()
            for permission in SetupPermission.allCases { permissions.values[permission] = .init(state) }
            let store = InMemoryOnboardingStore()
            let model = OnboardingModel(store: store, permissions: permissions)
            await model.refresh()
            XCTAssertTrue(model.canFinish, "\(state)")
            model.finish()
            XCTAssertEqual(store.state?.completion, .userCompleted, "\(state)")
            XCTAssertEqual(model.state.step, .ready)
            XCTAssertTrue(model.state.reviewed.isEmpty)
            XCTAssertNil(model.state.clipboardChoice)
            XCTAssertTrue(permissions.requests.isEmpty)
            XCTAssertTrue(permissions.consent.isEmpty)
            XCTAssertEqual(model.statuses, permissions.values)
            XCTAssertFalse(model.canFinish, "Completed setup cannot be completed again")
        }
    }

    func testUnavailableRestrictedAndNonPregrantableReviewsAreOptionalAndTruthful() async {
        for state in [SetupAuthorization.unavailable, .restricted, .notPregrantable, .noPermissionRequired] {
            let permissions = SetupTestPermissions()
            permissions.values[.camera] = .init(state)
            let model = OnboardingModel(store: InMemoryOnboardingStore(), permissions: permissions)
            await model.refresh()
            model.chooseClipboard(false)
            XCTAssertTrue(model.canFinish)
            XCTAssertFalse(model.isSatisfied(.camera))
            model.select(.camera)
            model.acknowledgeCurrent()
            XCTAssertTrue(model.canFinish)
            XCTAssertEqual(model.statuses[.camera]?.authorization, state)
        }
    }

    func testSkippingClipboardNeverInfersOptInFromCompletion() {
        let permissions = SetupTestPermissions()
        let model = OnboardingModel(store: InMemoryOnboardingStore(), permissions: permissions)
        model.go(to: .review)
        model.finish()
        XCTAssertEqual(model.state.completion, .userCompleted)
        XCTAssertNil(model.state.clipboardChoice)
        XCTAssertTrue(permissions.consent.isEmpty)
        XCTAssertEqual(permissions.statusReads, 0, "Completion must not wait on optional permission checks")
    }

    func testExplicitClipboardChoiceIsPreservedOnCompletion() async {
        let permissions = SetupTestPermissions()
        let model = OnboardingModel(store: InMemoryOnboardingStore(), permissions: permissions)
        await model.refresh()
        XCTAssertTrue(model.canFinish)
        XCTAssertTrue(permissions.consent.isEmpty)
        model.select(.clipboard)
        model.acknowledgeCurrent()
        XCTAssertNil(model.state.clipboardChoice)
        model.chooseClipboard(false)
        XCTAssertEqual(permissions.consent, [false])
        XCTAssertTrue(model.canFinish)
        model.finish()
        await waitUntilIdle(model)
        XCTAssertEqual(model.state.completion, .userCompleted)
        XCTAssertEqual(permissions.consent, [false])
    }

    func testRevocationBeforeCompletionDoesNotBlockSetupOrClaimAccess() async {
        let permissions = SetupTestPermissions()
        let model = OnboardingModel(store: InMemoryOnboardingStore(), permissions: permissions)
        await model.refresh()
        model.chooseClipboard(true)
        XCTAssertTrue(model.canFinish)
        permissions.values[.calendar] = .init(.denied)
        await model.refresh()
        model.finish()
        await waitUntilIdle(model)
        XCTAssertFalse(model.requiresOnboarding)
        XCTAssertEqual(model.statuses[.calendar]?.authorization, .denied)
    }

    func testRevocationAfterCompletionDoesNotReopenWizardOrResetState() async {
        var state = OnboardingState()
        state.completion = .userCompleted
        let store = InMemoryOnboardingStore(state: state)
        let permissions = SetupTestPermissions()
        permissions.values[.calendar] = .init(.denied)
        let model = OnboardingModel(store: store, permissions: permissions)
        await model.refresh()
        XCTAssertFalse(model.requiresOnboarding)
        XCTAssertEqual(model.statuses[.calendar]?.authorization, .denied)
        XCTAssertEqual(store.state, state)
    }

    func testOneRequestAtATimeAndProgressSavedBeforeSystemDialog() async {
        let store = InMemoryOnboardingStore()
        let permissions = SetupTestPermissions()
        permissions.hold = true
        let model = OnboardingModel(store: store, permissions: permissions)
        model.request(.camera)
        XCTAssertFalse(model.canFinish)
        model.finish()
        XCTAssertTrue(model.requiresOnboarding, "Wait for the in-flight native request before finishing")
        model.request(.reminders)
        model.next()
        XCTAssertEqual(store.state?.currentPermission, .camera)
        await Task.yield()
        XCTAssertEqual(permissions.requests, [.camera])
        permissions.resume()
        await waitUntilIdle(model)
        XCTAssertFalse(model.isBusy)
    }

    func testRequestFailureDoesNotPretendPermissionGranted() async {
        let permissions = SetupTestPermissions()
        permissions.values[.camera] = .init(.notDetermined)
        permissions.fail = true
        let model = OnboardingModel(store: InMemoryOnboardingStore(), permissions: permissions)
        model.request(.camera)
        await waitUntilIdle(model)
        XCTAssertEqual(model.statuses[.camera]?.authorization, .notDetermined)
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.requiresOnboarding)
        XCTAssertTrue(model.canFinish)
        model.finish()
        XCTAssertEqual(model.state.step, .ready)
        XCTAssertNil(model.error)
    }

    func testActivationRefreshCoalescesAndBlocksConcurrentPermissionRequests() async {
        let permissions = SetupTestPermissions()
        let model = OnboardingModel(store: InMemoryOnboardingStore(), permissions: permissions)
        model.refreshStatus()
        model.refreshStatus()
        model.request(.calendar)
        await waitUntilIdle(model)
        XCTAssertEqual(permissions.statusReads, SetupPermission.allCases.count)
        XCTAssertTrue(permissions.requests.isEmpty)
    }

    func testCompletedStateSurvivesTenIndependentStoreRecreationsAndChangedBuildContext() throws {
        let (preferences, directory) = isolatedStorage()
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = OnboardingState()
        state.step = .ready
        state.completion = .userCompleted
        state.clipboardChoice = false
        try OnboardingStore(preferences: preferences, supportDirectory: directory).save(state)
        for _ in 0..<10 {
            let store = OnboardingStore(preferences: preferences, supportDirectory: directory)
            let model = OnboardingModel(store: store, permissions: SetupTestPermissions())
            XCTAssertFalse(model.requiresOnboarding)
            XCTAssertEqual(model.state, state)
        }
    }

    func testMigrationPreservesEveryExistingPreferenceAndOpaqueDataFile() throws {
        let (preferences, directory) = isolatedStorage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let values: [String: Any] = [
            "SpotifyLocalControlEnabled": false,
            "notchium.calendar.selectedIdentifiers": ["calendar-fixture"],
            "notchium.clipboard.capture-enabled.v1": true,
            "shelf.items.v1": Data([4, 5, 6]), "home.configuration.v1": Data([7, 8, 9]),
            "notchium.pomodoro.work-minutes.v1": 38
        ]
        for (key, value) in values { preferences.set(value, forKey: key) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Clipboard"), withIntermediateDirectories: true)
        let files = ["FocusTimer.json", "Clipboard/history.clip", "Clipboard/pinned-image.clip"]
        for file in files { try Data([0xCA, 0xFE]).write(to: directory.appendingPathComponent(file)) }
        let store = OnboardingStore(preferences: preferences, supportDirectory: directory)
        let model = OnboardingModel(store: store, permissions: SetupTestPermissions())
        XCTAssertFalse(model.requiresOnboarding)
        for (key, value) in values {
            XCTAssertEqual(preferences.object(forKey: key) as? NSObject, value as? NSObject, key)
        }
        for file in files { XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(file)), Data([0xCA, 0xFE])) }
    }

    func testPersistentFilesAloneRecognizeReturningInstallation() throws {
        for name in ["FocusTimer.json", "Clipboard"] {
            let (preferences, directory) = isolatedStorage()
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([1]).write(to: directory.appendingPathComponent(name))
            XCTAssertTrue(OnboardingStore(preferences: preferences, supportDirectory: directory).hasLegacyConfiguration())
        }
    }

    func testLegacyAudioOrWaveformPreferencesAloneArePreservedWithoutWelcome() {
        let values: [String: Any] = ["audio.pinnedBundles": ["fixture.app"],
                                    "media.waveform.staticColor": "AABBCC", "media.waveform.colorMode": "adaptive"]
        for (key, value) in values {
            let (preferences, directory) = isolatedStorage()
            defer { try? FileManager.default.removeItem(at: directory) }
            preferences.set("native-window-fixture", forKey: "NSWindow Frame Settings")
            let store = OnboardingStore(preferences: preferences, supportDirectory: directory)
            XCTAssertFalse(store.hasLegacyConfiguration(), "System defaults alone are not app configuration")
            preferences.set(value, forKey: key)
            let model = OnboardingModel(store: store, permissions: SetupTestPermissions())
            XCTAssertFalse(model.requiresOnboarding, key)
            XCTAssertEqual(model.state.completion, .legacyRecognized)
            XCTAssertEqual(preferences.object(forKey: key) as? NSObject, value as? NSObject)
        }
    }

    func testCorruptRecordIsPreservedAndFailsClosed() throws {
        let (preferences, directory) = isolatedStorage()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Onboarding.json")
        let original = Data("unreadable-fixture".utf8)
        try original.write(to: url)
        let model = OnboardingModel(store: OnboardingStore(preferences: preferences, supportDirectory: directory),
                                    permissions: SetupTestPermissions())
        model.go(to: .ready)
        XCTAssertTrue(model.requiresOnboarding)
        XCTAssertFalse(model.canFinish)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testSaveFailureNeverAdvancesOrMarksSetupComplete() async {
        let store = FailingSetupStore()
        let model = OnboardingModel(store: store, permissions: SetupTestPermissions())
        await model.refresh()
        model.chooseClipboard(false)
        store.failWrites = true
        model.go(to: .review)
        XCTAssertEqual(model.state.step, .welcome)
        model.finish()
        await waitUntilIdle(model)
        XCTAssertTrue(model.requiresOnboarding)
        XCTAssertNotNil(model.error)
    }

    func testCameraPermissionRequestNeverStartsPreviewAndPreservesDenial() async throws {
        let camera = MockCameraService(authorization: .notDetermined)
        let adapter = NativeOnboardingPermissions(camera: camera, profile: .freeDirect)
        let before = await adapter.status(for: .camera)
        XCTAssertEqual(before.authorization, .notDetermined)
        try await adapter.request(.camera)
        let granted = await adapter.status(for: .camera)
        XCTAssertEqual(granted.authorization, .granted)
        XCTAssertTrue(camera.startedDevices.isEmpty)
        XCTAssertFalse(camera.isRunning)
        camera.grantsAccess = false
        try await adapter.request(.camera)
        XCTAssertEqual(camera.authorization, .authorized, "Already-granted access must not request again")
        camera.authorization = .denied
        camera.grantsAccess = true
        try await adapter.request(.camera)
        XCTAssertEqual(camera.authorization, .denied, "Denied access must never be requested again")
    }

    func testCameraHardwareAvailabilityAndAuthorizationStayDistinct() async {
        let camera = MockCameraService(authorization: .notDetermined, devices: [])
        let adapter = NativeOnboardingPermissions(camera: camera, profile: .freeDirect)
        var status = await adapter.status(for: .camera)
        XCTAssertEqual(status.authorization, .unavailable)
        camera.authorization = .denied
        status = await adapter.status(for: .camera)
        XCTAssertEqual(status.authorization, .denied)
        camera.authorization = .authorized
        status = await adapter.status(for: .camera)
        XCTAssertEqual(status.authorization, .granted)
        XCTAssertTrue(status.detail.contains("no camera"))
    }

    func testAudioFilesKeychainAndNotificationDisclosuresNeverClaimOSAuthorization() async throws {
        let adapter = NativeOnboardingPermissions(camera: MockCameraService(), profile: .freeDirect)
        for permission in [SetupPermission.systemAudio, .files, .shortcuts, .keychain] {
            let status = await adapter.status(for: permission)
            XCTAssertEqual(status.authorization, .notPregrantable, "\(permission)")
            try await adapter.request(permission)
            let after = await adapter.status(for: permission)
            XCTAssertEqual(after.authorization, .notPregrantable)
        }
        let notifications = await adapter.status(for: .notifications)
        XCTAssertEqual(notifications.authorization, .noPermissionRequired)
        let focus = await adapter.status(for: .focus)
        XCTAssertEqual(focus.authorization, .unavailable)
    }

    func testFutureCompletedSchemaNeverResetsOrOverwritesExistingRecord() {
        var state = OnboardingState()
        state.schemaVersion = 99
        state.completion = .userCompleted
        let store = InMemoryOnboardingStore(state: state)
        let model = OnboardingModel(store: store, permissions: SetupTestPermissions())
        model.select(.calendar)
        XCTAssertFalse(model.requiresOnboarding)
        XCTAssertEqual(store.state, state)
    }

    func testReadOnlyPasteboardBehaviorIsSeparateFromAppConsent() async {
        let cases: [(NSPasteboard.AccessBehavior, SetupAuthorization)] = [
            (.default, .notPregrantable), (.ask, .notPregrantable),
            (.alwaysAllow, .granted), (.alwaysDeny, .denied)
        ]
        for (behavior, expected) in cases {
            let adapter = NativeOnboardingPermissions(camera: MockCameraService(), profile: .freeDirect,
                                                       pasteboardBehavior: { behavior })
            let consent = await adapter.status(for: .clipboard)
            let os = await adapter.status(for: .clipboardAccess)
            XCTAssertEqual(consent.authorization, .noPermissionRequired)
            XCTAssertEqual(os.authorization, expected)
        }
    }

    func testPasteboardDenialStaysTruthfulWithEitherClipboardChoiceWithoutBlockingSetup() async {
        let permissions = SetupTestPermissions()
        permissions.values[.clipboardAccess] = .init(.denied)
        let model = OnboardingModel(store: InMemoryOnboardingStore(), permissions: permissions)
        await model.refresh()
        model.chooseClipboard(true)
        model.select(.clipboardAccess)
        model.acknowledgeCurrent()
        XCTAssertFalse(model.isSatisfied(.clipboardAccess))
        XCTAssertTrue(model.canFinish)
        model.chooseClipboard(false)
        XCTAssertFalse(model.isSatisfied(.clipboardAccess), "Review stays separate from completion")
        XCTAssertTrue(model.canFinish)
        model.acknowledgeCurrent()
        XCTAssertTrue(model.canFinish)
        XCTAssertEqual(model.statuses[.clipboardAccess]?.authorization, .denied)
        model.chooseClipboard(true)
        XCTAssertFalse(model.isSatisfied(.clipboardAccess), "An old Off exception cannot claim OS access after opt-in")
        XCTAssertTrue(model.canFinish)
    }

    func testEveryStageAndPermissionResumesAndAdvancesWithoutAccess() async {
        let permissions = SetupTestPermissions()
        for permission in SetupPermission.allCases { permissions.values[permission] = .init(.denied) }
        let store = InMemoryOnboardingStore()
        var model = OnboardingModel(store: store, permissions: permissions)
        model.go(to: .overview)
        model = OnboardingModel(store: store, permissions: permissions)
        XCTAssertEqual(model.state.step, .overview)
        model.go(to: .permissions)
        await model.refresh()
        for permission in SetupPermission.allCases {
            XCTAssertEqual(model.current, permission)
            XCTAssertEqual(model.state.step, .permissions)
            model = OnboardingModel(store: store, permissions: permissions)
            XCTAssertEqual(model.current, permission)
            XCTAssertEqual(model.state.step, .permissions)
            model.next()
        }
        XCTAssertEqual(model.state.step, .review)
        model = OnboardingModel(store: store, permissions: permissions)
        XCTAssertEqual(model.state.step, .review)
        model.select(.camera)
        XCTAssertEqual(model.current, .camera)
        XCTAssertEqual(model.state.step, .permissions)
        model.go(to: .review)
        model.finish()
        XCTAssertEqual(store.state?.step, .ready)
        model = OnboardingModel(store: store, permissions: permissions)
        XCTAssertFalse(model.requiresOnboarding)
        XCTAssertEqual(model.state.step, .ready)
        XCTAssertTrue(permissions.requests.isEmpty)
        XCTAssertTrue(permissions.consent.isEmpty)
    }

    func testFutureIncompleteSchemaCannotBeFinishedOrOverwritten() {
        var state = OnboardingState()
        state.schemaVersion = 99
        state.step = .review
        let store = InMemoryOnboardingStore(state: state)
        let model = OnboardingModel(store: store, permissions: SetupTestPermissions())
        XCTAssertFalse(model.canFinish)
        model.finish()
        XCTAssertTrue(model.requiresOnboarding)
        XCTAssertEqual(store.state, state)
        XCTAssertNotNil(model.error)
    }

    func testUnresolvableScreenshotSelectionFailsClosedInsteadOfWatchingDefaultFolder() async {
        let suite = "Notchium.ScreenshotGrantTests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let original = Data("invalid-bookmark-fixture".utf8)
        preferences.set(original, forKey: ScreenshotFolderAccess.key)
        let access = ScreenshotFolderAccess(defaults: preferences)
        XCTAssertTrue(access.hasSelection)
        XCTAssertNil(access.resolve())
        let service = RealScreenshotService(folderAccess: access)
        let stream = await service.events()
        let availability = await service.availability()
        XCTAssertEqual(availability, .unavailable(.permissionDenied))
        XCTAssertEqual(preferences.data(forKey: ScreenshotFolderAccess.key), original)
        let task = Task { for await _ in stream { } }
        task.cancel()
        await task.value
    }

    private func isolatedStorage() -> (UserDefaults, URL) {
        let id = UUID().uuidString
        return (UserDefaults(suiteName: "Notchium.SetupTests.\(id)")!,
                FileManager.default.temporaryDirectory.appendingPathComponent("Notchium.SetupTests.\(id)"))
    }
    private func waitUntilIdle(_ model: OnboardingModel) async {
        for _ in 0..<500 where model.isBusy { await Task.yield() }
        XCTAssertFalse(model.isBusy)
    }
}

@MainActor private final class SetupTestPermissions: OnboardingPermissionProviding {
    var values: [SetupPermission: SetupPermissionStatus] = [:]
    var requests: [SetupPermission] = []
    var consent: [Bool] = []
    var statusReads = 0
    var hold = false
    var fail = false
    var continuation: CheckedContinuation<Void, Never>?
    func status(for permission: SetupPermission) async -> SetupPermissionStatus {
        statusReads += 1
        return values[permission] ?? .init(.granted)
    }
    func request(_ permission: SetupPermission) async throws {
        requests.append(permission)
        if hold { await withCheckedContinuation { continuation = $0 } }
        if fail { throw CocoaError(.fileReadNoPermission) }
        values[permission] = .init(.granted)
    }
    func resume() { hold = false; continuation?.resume(); continuation = nil }
    func openSettings(for permission: SetupPermission) { }
    func setClipboardConsent(_ enabled: Bool) { consent.append(enabled) }
}

@MainActor private final class FailingSetupStore: OnboardingStoring {
    var state: OnboardingState?
    var failWrites = false
    func load() -> OnboardingState? { state }
    func save(_ state: OnboardingState) throws {
        if failWrites { throw CocoaError(.fileWriteOutOfSpace) }
        self.state = state
    }
    func hasLegacyConfiguration() -> Bool { false }
}
