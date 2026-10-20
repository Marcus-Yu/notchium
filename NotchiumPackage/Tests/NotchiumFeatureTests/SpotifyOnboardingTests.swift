import Carbon
import XCTest
import NotchiumCore
import NotchiumPersistence
@testable import NotchiumServices
@testable import NotchiumFeature

@MainActor final class SpotifyOnboardingTests: XCTestCase {
    func testAlreadyAuthorizedAndFirstAuthorizationSuccess() async throws {
        let native = SetupAutomationProbe(code: noErr)
        let service = SpotifySetupAuthorization(application: SetupSpotifyApp(), authorizer: native)
        let before = await service.status()
        XCTAssertEqual(before.authorization, .granted)
        try await service.request()
        let after = await service.status()
        XCTAssertEqual(after.authorization, .granted)
    }

    func testFirstUndeterminedAuthorizationSucceedsOnlyAfterNativeConsent() async throws {
        let native = SetupAutomationProbe(code: Int32(errAEEventWouldRequireUserConsent))
        let service = SpotifySetupAuthorization(application: SetupSpotifyApp(), authorizer: native)
        let before = await service.status()
        XCTAssertEqual(before.authorization, .notDetermined)
        await native.setCode(noErr)
        try await service.request()
        let after = await service.status()
        XCTAssertEqual(after.authorization, .granted)
        let prompts = await native.prompts
        XCTAssertEqual(prompts, [false, true, false])
    }

    func testExactOSStatusMappingNeverPromotesFailuresToGranted() {
        let cases: [(Int32, SetupAuthorization)] = [
            (noErr, .granted), (Int32(errAEEventNotPermitted), .denied),
            (Int32(errAEEventWouldRequireUserConsent), .notDetermined),
            (Int32(errAETimeout), .needsSystemSettings), (Int32(procNotFound), .requiresApplication),
            (Int32(connectionInvalid), .requiresApplication), (-50, .needsSystemSettings)
        ]
        for (code, expected) in cases {
            XCTAssertEqual(SpotifySetupAuthorization.status(for: code).authorization, expected, "\(code)")
        }
    }

    func testDeniedNoDialogTimeoutAndErrorHaveActionableResults() async {
        for code in [Int32(errAEEventNotPermitted), Int32(errAEEventWouldRequireUserConsent), Int32(errAETimeout), -50] {
            let native = SetupAutomationProbe(code: code)
            let service = SpotifySetupAuthorization(application: SetupSpotifyApp(), authorizer: native)
            do { try await service.request(); XCTFail("Failure \(code) must be reported") }
            catch { XCTAssertTrue(error is SpotifySetupRequestFailure) }
            let status = await service.status()
            XCTAssertNotEqual(status.authorization, .granted)
            XCTAssertFalse(status.detail.isEmpty)
        }
    }

    func testMissingSpotifyDoesNotRequestAutomation() async {
        let app = SetupSpotifyApp(installed: false)
        let native = SetupAutomationProbe(code: noErr)
        let service = SpotifySetupAuthorization(application: app, authorizer: native)
        let status = await service.status()
        XCTAssertEqual(status.authorization, .unavailable)
        do { try await service.request(); XCTFail("Missing app") } catch { }
        let prompts = await native.prompts
        XCTAssertEqual(prompts, [])
    }

    func testStoppedSpotifyLaunchesBeforeConsent() async throws {
        let app = SetupSpotifyApp(running: false)
        let native = SetupAutomationProbe(code: noErr)
        let service = SpotifySetupAuthorization(application: app, authorizer: native)
        let before = await service.status()
        XCTAssertEqual(before.authorization, .requiresApplication)
        try await service.request()
        let launches = await app.launches
        let prompts = await native.prompts
        XCTAssertEqual(launches, 1)
        XCTAssertEqual(prompts, [true])
    }

    func testLaunchReadinessIsBoundedAndLaunchFailureIsReported() async {
        for fail in [false, true] {
            let app = SetupSpotifyApp(running: false, becomesReady: false, failLaunch: fail)
            let native = SetupAutomationProbe(code: noErr)
            let service = SpotifySetupAuthorization(application: app, authorizer: native,
                clock: TestAppClock(now: .distantPast))
            do { try await service.request(); XCTFail("Unready app") } catch { }
            let prompts = await native.prompts
            XCTAssertEqual(prompts, [])
        }
    }

    func testRequestWaitExpiresWithoutCancellingSheetOrDuplicatingRequestAndCanRepairLater() async throws {
        let native = SetupAutomationProbe(code: noErr, holdPrompt: true)
        let clock = TestAppClock(now: .distantPast, automaticallyAdvances: false)
        let service = SpotifySetupAuthorization(application: SetupSpotifyApp(), authorizer: native, clock: clock)
        let request = Task { try await service.request() }
        await native.waitForPrompt()
        await clock.waitForPendingSleeps()
        try await service.request() // Coalesced while native consent is still open.
        await clock.advance(by: .seconds(30))
        do { try await request.value; XCTFail("UI wait must expire") } catch { }
        let waiting = await service.status()
        XCTAssertEqual(waiting.authorization, .needsSystemSettings)
        let prompts = await native.prompts
        XCTAssertEqual(prompts, [true])
        await native.resolve(noErr) // User answers the original sheet after UI wait expires.
        for _ in 0..<20 { await Task.yield() }
        let repaired = await service.status()
        XCTAssertEqual(repaired.authorization, .granted)
        let wasCancelled = await native.wasCancelled
        XCTAssertFalse(wasCancelled)
    }

    func testNonpromptingCheckHasBoundedWaitAndDoesNotDuplicateBlockedChecks() async {
        let native = SetupAutomationProbe(code: noErr, holdCheck: true)
        let clock = TestAppClock(now: .distantPast, automaticallyAdvances: false)
        let service = SpotifySetupAuthorization(application: SetupSpotifyApp(), authorizer: native, clock: clock)
        let check = Task { await service.status() }
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(3))
        let unknown = await check.value
        XCTAssertEqual(unknown.authorization, .needsSystemSettings)
        let second = Task { await service.status() }
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(3))
        _ = await second.value
        let prompts = await native.prompts
        XCTAssertEqual(prompts, [false])
        await native.resolve(noErr)
    }

    func testSpotifyExitsDuringConsent() async {
        let native = SetupAutomationProbe(code: Int32(connectionInvalid))
        let service = SpotifySetupAuthorization(application: SetupSpotifyApp(), authorizer: native)
        do { try await service.request(); XCTFail("Exited app") } catch { }
        let status = await service.status()
        XCTAssertEqual(status.authorization, .requiresApplication)
    }

    func testExplicitExceptionEnablesFinishPreservesDenialAndReturningUserThenSettingsRepair() async {
        let permissions = HotfixSetupPermissions()
        let store = InMemoryOnboardingStore()
        let model = OnboardingModel(store: store, permissions: permissions)
        await model.refresh()
        model.chooseClipboard(false)
        XCTAssertFalse(model.canFinish)
        model.continueWithoutSpotify()
        XCTAssertTrue(model.canFinish)
        XCTAssertEqual(model.statuses[.spotify]?.authorization, .denied)
        XCTAssertTrue(model.state.reviewed.contains(.spotify))
        model.finish()
        await idle(model)
        XCTAssertEqual(model.state.step, .ready)
        XCTAssertEqual(model.state.completion, .userCompleted)
        let returning = OnboardingModel(store: store, permissions: permissions)
        XCTAssertFalse(returning.requiresOnboarding)
        returning.request(.spotify)
        await idle(returning)
        XCTAssertEqual(returning.statuses[.spotify]?.authorization, .granted)
        XCTAssertFalse(returning.requiresOnboarding)
        XCTAssertEqual(permissions.clipboardWrites, [false])
    }

    func testSpotifyExceptionLeavesAllOtherRequirementsUnchanged() async {
        let permissions = HotfixSetupPermissions()
        permissions.calendarDenied = true
        let model = OnboardingModel(store: InMemoryOnboardingStore(), permissions: permissions)
        await model.refresh()
        model.chooseClipboard(false)
        model.continueWithoutSpotify()
        XCTAssertFalse(model.canFinish)
        XCTAssertFalse(model.canAcknowledge(.calendar))
        XCTAssertEqual(model.statuses[.spotify]?.authorization, .denied)
    }

    func testStoppedModelIgnoresStaleRequestCompletion() async {
        let permissions = HotfixSetupPermissions()
        permissions.hold = true
        let model = OnboardingModel(store: InMemoryOnboardingStore(), permissions: permissions)
        model.request(.spotify)
        for _ in 0..<20 { await Task.yield() }
        model.stop()
        model.continueWithoutSpotify()
        permissions.resume()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(model.statuses[.spotify])
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.state.reviewed.contains(.spotify))
    }

    private func idle(_ model: OnboardingModel) async {
        for _ in 0..<200 where model.isBusy { await Task.yield() }
        XCTAssertFalse(model.isBusy)
    }
}

private actor SetupSpotifyApp: SpotifyApplicationLaunching {
    var installed: Bool
    var running: Bool
    var becomesReady: Bool
    var failLaunch: Bool
    var launches = 0
    init(installed: Bool = true, running: Bool = true, becomesReady: Bool = true, failLaunch: Bool = false) {
        self.installed = installed; self.running = running
        self.becomesReady = becomesReady; self.failLaunch = failLaunch
    }
    func isSpotifyInstalled() -> Bool { installed }
    func isSpotifyRunning() -> Bool { running }
    func launchSpotify() throws {
        launches += 1
        if failLaunch { throw MediaFailure.spotifyUnavailable }
        running = becomesReady
    }
}

private actor SetupAutomationProbe: SpotifyAutomationAuthorizing {
    var code: Int32
    var holdPrompt: Bool
    var holdCheck: Bool
    var prompts: [Bool] = []
    var wasCancelled = false
    var continuation: CheckedContinuation<Int32, Never>?
    var promptObserver: CheckedContinuation<Void, Never>?
    init(code: Int32, holdPrompt: Bool = false, holdCheck: Bool = false) {
        self.code = code; self.holdPrompt = holdPrompt; self.holdCheck = holdCheck
    }
    func authorization(prompt: Bool) async -> Int32 {
        prompts.append(prompt)
        if (prompt && holdPrompt) || (!prompt && holdCheck) {
            let result: Int32 = await withCheckedContinuation { continuation in
                self.continuation = continuation
                promptObserver?.resume(); promptObserver = nil
            }
            wasCancelled = Task.isCancelled
            return result
        }
        return code
    }
    func waitForPrompt() async {
        if continuation != nil { return }
        await withCheckedContinuation { promptObserver = $0 }
    }
    func setCode(_ value: Int32) { code = value }
    func resolve(_ result: Int32) {
        code = result; holdPrompt = false; holdCheck = false
        continuation?.resume(returning: result); continuation = nil
    }
}

@MainActor private final class HotfixSetupPermissions: OnboardingPermissionProviding {
    var spotify: SetupAuthorization = .denied
    var calendarDenied = false
    var clipboardWrites: [Bool] = []
    var hold = false
    var continuation: CheckedContinuation<Void, Never>?
    func status(for permission: SetupPermission) async -> SetupPermissionStatus {
        .init(permission == .spotify ? spotify : (permission == .calendar && calendarDenied ? .denied : .granted))
    }
    func request(_ permission: SetupPermission) async throws {
        if hold { await withCheckedContinuation { continuation = $0 } }
        if permission == .spotify { spotify = .granted }
    }
    func resume() { continuation?.resume(); continuation = nil }
    func openSettings(for permission: SetupPermission) { }
    func setClipboardConsent(_ enabled: Bool) { clipboardWrites.append(enabled) }
}
