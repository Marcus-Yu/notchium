import EventKit
import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumPersistence
@testable import NotchiumQuickActionsFeature
@testable import NotchiumServices
import XCTest

@MainActor
final class ReminderServiceTests: XCTestCase {
    func testComposerObservationDoesNotRestartFailedVerificationOrRepeatConsent() async throws {
        let preferencesName = "ReminderServiceTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: preferencesName))
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let store = ReminderPermissionStore(authorization: .notDetermined)
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let service = EventKitReminderService(store: store, clock: clock)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let model = QuickReminderModel(service: service, workspace: NativeQuickActionWorkspace(),
            store: QuickActionStore(preferences: preferences), notifications: presentation.notificationCoordinator,
            clock: clock)
        defer { model.endSession(); presentation.reset() }

        await model.prepare()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.access, .verificationFailed)
        let delays = await clock.sleepHistory()
        XCTAssertEqual(delays, EventKitReminderService.authorizationRecheckDelays,
                       "Preparation and service notifications must share one bounded verification")
        XCTAssertEqual(store.calls, ["request"])
        model.draft.title = "Review fixture notes"
        XCTAssertFalse(model.canSaveReminder)
        XCTAssertEqual(model.draft.title, "Review fixture notes")
    }

    func testSuccessfulRequestWithUnverifiedAuthorizationDoesNotReturnFirstUseState() async throws {
        let store = ReminderPermissionStore(authorization: .notDetermined)
        let service = EventKitReminderService(store: store, clock: TestAppClock(now: .distantPast))
        let result = try await service.requestAccess()
        XCTAssertEqual(result, .verificationFailed)
        XCTAssertEqual(store.calls, ["request"])
    }

    func testPreviouslyVerifiedAccessIsRecheckedWithoutPretendingToBeFirstUse() {
        let store = ReminderPermissionStore(authorization: .fullAccess)
        let service = EventKitReminderService(store: store)
        XCTAssertEqual(service.access(), .allowed)
        store.authorizationStatus = .notDetermined
        XCTAssertEqual(service.access(), .checking)
        XCTAssertTrue(service.lists().isEmpty)
    }

    func testSuccessfulCallbackCannotReadOrSaveUntilStatusActuallyGrantsAccess() async throws {
        let store = ReminderPermissionStore(authorization: .notDetermined)
        let clock = TestAppClock(now: .distantPast, automaticallyAdvances: false)
        let service = EventKitReminderService(store: store, clock: clock)
        let request = Task { try await service.requestAccess() }
        await clock.waitForPendingSleeps()
        XCTAssertEqual(service.access(), .checking)
        XCTAssertTrue(service.lists().isEmpty)
        XCTAssertThrowsError(try service.save(.init(title: "Fixture", date: .distantPast), listID: nil))
        XCTAssertEqual(store.calls, ["request"])

        store.authorizationStatus = .fullAccess
        await clock.advance(by: EventKitReminderService.authorizationRecheckDelays[0])
        let result = try await request.value
        XCTAssertEqual(result, .allowed)
        XCTAssertEqual(service.lists().count, 1)
        try service.save(.init(title: "  Fixture  ", date: .distantPast), listID: "fixture")
        XCTAssertEqual(store.calls, ["request", "reset", "lists", "save"])
        XCTAssertEqual(store.savedDraft?.title, "Fixture")
    }

    func testUnresolvedRequestIsBoundedAndRepeatedRequestDoesNotPromptAgain() async throws {
        let store = ReminderPermissionStore(authorization: .notDetermined)
        let clock = TestAppClock(now: .distantPast)
        let service = EventKitReminderService(store: store, clock: clock)
        let first = try await service.requestAccess()
        XCTAssertEqual(first, .verificationFailed)
        let delays = await clock.sleepHistory()
        XCTAssertEqual(delays, EventKitReminderService.authorizationRecheckDelays)
        let second = try await service.requestAccess()
        XCTAssertEqual(second, .verificationFailed)
        XCTAssertEqual(store.calls, ["request"])
        XCTAssertTrue(service.lists().isEmpty)

        store.authorizationStatus = .fullAccess
        let recovered = await service.refreshAccess()
        XCTAssertEqual(recovered, .allowed)
        XCTAssertEqual(store.calls, ["request", "reset"])
    }

    func testExistingGrantLossRecoversAutomaticallyAndResetsNativeStore() async {
        let store = ReminderPermissionStore(authorization: .fullAccess)
        let clock = TestAppClock(now: .distantPast, automaticallyAdvances: false)
        let service = EventKitReminderService(store: store, clock: clock)
        XCTAssertEqual(service.lists().count, 1)
        XCTAssertEqual(service.lists().count, 1)
        XCTAssertEqual(store.calls, ["reset", "lists", "lists"])
        store.authorizationStatus = .notDetermined
        let refresh = Task { await service.refreshAccess() }
        await clock.waitForPendingSleeps()
        XCTAssertEqual(service.access(), .checking)
        store.authorizationStatus = .fullAccess
        await clock.advance(by: EventKitReminderService.authorizationRecheckDelays[0])
        let recovered = await refresh.value
        XCTAssertEqual(recovered, .allowed)
        XCTAssertEqual(store.calls, ["reset", "lists", "lists", "reset"])
    }

    func testConfirmedDenialOrRestrictionDoesNotRequestOrReadData() async throws {
        for status in [EKAuthorizationStatus.denied, .restricted, .writeOnly] {
            let store = ReminderPermissionStore(authorization: status)
            let service = EventKitReminderService(store: store)
            let result = try await service.requestAccess()
            XCTAssertEqual(result, status == .restricted ? .restricted : .denied)
            XCTAssertTrue(service.lists().isEmpty)
            XCTAssertThrowsError(try service.save(.init(title: "Fixture", date: .distantPast), listID: nil))
            XCTAssertTrue(store.calls.isEmpty)
        }
    }

    func testConfirmedRevocationOverridesVerificationImmediately() async {
        let store = ReminderPermissionStore(authorization: .fullAccess)
        let clock = TestAppClock(now: .distantPast, automaticallyAdvances: false)
        let service = EventKitReminderService(store: store, clock: clock)
        XCTAssertEqual(service.access(), .allowed)
        store.authorizationStatus = .notDetermined
        let refresh = Task { await service.refreshAccess() }
        await clock.waitForPendingSleeps()
        store.authorizationStatus = .denied
        let revoked = await service.refreshAccess()
        XCTAssertEqual(revoked, .denied)
        let interrupted = await refresh.value
        XCTAssertEqual(interrupted, .denied)
        XCTAssertEqual(store.calls, ["reset"])
        XCTAssertTrue(service.lists().isEmpty)
    }

    func testFalseRequestResultRemainsFirstUseAndDoesNotRunVerification() async throws {
        let store = ReminderPermissionStore(authorization: .notDetermined)
        store.requestResult = false
        let clock = TestAppClock(now: .distantPast)
        let service = EventKitReminderService(store: store, clock: clock)
        let result = try await service.requestAccess()
        XCTAssertEqual(result, .notDetermined)
        let delays = await clock.sleepHistory()
        XCTAssertTrue(delays.isEmpty)
        XCTAssertEqual(store.calls, ["request"])
    }

    func testConcurrentCallersShareOnePermissionRequestAndVerification() async throws {
        let store = ReminderPermissionStore(authorization: .notDetermined)
        store.holdRequest = true
        let clock = TestAppClock(now: .distantPast, automaticallyAdvances: false)
        let service = EventKitReminderService(store: store, clock: clock)
        let first = Task { try await service.requestAccess() }
        for _ in 0..<100 where store.requestContinuation == nil { await Task.yield() }
        XCTAssertNotNil(store.requestContinuation)
        let second = Task { try await service.requestAccess() }
        for _ in 0..<20 { await Task.yield() }
        store.requestContinuation?.resume(returning: true)
        store.requestContinuation = nil
        await clock.waitForPendingSleeps()
        XCTAssertEqual(store.calls, ["request"])
        let pendingSleeps = await clock.pendingSleepCount()
        XCTAssertEqual(pendingSleeps, 1)
        store.authorizationStatus = .fullAccess
        await clock.advance(by: EventKitReminderService.authorizationRecheckDelays[0])
        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(firstResult, .allowed)
        XCTAssertEqual(secondResult, .allowed)
        XCTAssertEqual(store.calls, ["request", "reset"])
    }
}

@MainActor
private final class ReminderPermissionStore: ReminderEventStoreAccessing {
    var authorizationStatus: EKAuthorizationStatus
    var requestResult = true
    var authorizationAfterRequest: EKAuthorizationStatus?
    var holdRequest = false
    var requestContinuation: CheckedContinuation<Bool, any Error>?
    var savedDraft: ReminderDraft?
    var calls: [String] = []
    init(authorization: EKAuthorizationStatus) { authorizationStatus = authorization }
    func requestFullAccess() async throws -> Bool {
        calls.append("request")
        if holdRequest {
            return try await withCheckedThrowingContinuation { requestContinuation = $0 }
        }
        if let authorizationAfterRequest { authorizationStatus = authorizationAfterRequest }
        return requestResult
    }
    func reset() { calls.append("reset") }
    func lists() -> [ReminderList] { calls.append("lists"); return [.init(id: "fixture", title: "Fixture")] }
    func save(_ draft: ReminderDraft, listID: String?) throws { calls.append("save"); savedDraft = draft }
}
