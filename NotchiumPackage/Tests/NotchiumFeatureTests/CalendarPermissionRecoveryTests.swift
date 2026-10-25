import EventKit
import Foundation
import NotchiumCore
@testable import NotchiumServices
import XCTest

@MainActor
final class CalendarPermissionRecoveryTests: XCTestCase {
    private let selectionKey = "notchium.calendar.selectedIdentifiers"

    func testWriteOnlyAccessCanUpgradeToFullAccess() async throws {
        let store = PermissionRecoveryCalendarStore(authorization: .writeOnly)
        let service = RealCalendarService(store: store, preferences: try preferences())
        var updates = await service.updates().makeAsyncIterator()
        let initial = await updates.next()
        XCTAssertEqual(initial?.permission, .needsFullAccess)
        XCTAssertEqual(initial?.availability, .unavailable(.permissionDenied))
        XCTAssertTrue(store.calls.isEmpty, "Write-only access must not read calendars")

        store.authorizationAfterRequest = .fullAccess
        await service.requestAccess()
        let granted = await updates.next()
        XCTAssertEqual(granted?.permission, .granted)
        XCTAssertEqual(granted?.availability, .available)
        XCTAssertEqual(store.calls, ["request", "reset", "calendars"])
        await service.stop()
    }

    func testDeniedAndRestrictedAccessDoNotRequestOrReadCalendarData() async throws {
        for authorization in [EKAuthorizationStatus.denied, .restricted] {
            let store = PermissionRecoveryCalendarStore(authorization: authorization)
            let service = RealCalendarService(store: store, preferences: try preferences())
            var updates = await service.updates().makeAsyncIterator()
            let initial = await updates.next()
            let expected: CalendarPermission = authorization == .denied ? .denied : .restricted
            XCTAssertEqual(initial?.permission, expected)

            await service.requestAccess()
            let refreshed = await updates.next()
            XCTAssertEqual(refreshed?.permission, expected)
            await service.setCalendarSelected("unread-calendar", selected: true)
            XCTAssertTrue(store.calls.isEmpty, "A denied or restricted store must remain unread")
            XCTAssertEqual(refreshed?.calendars, [])
            XCTAssertEqual(refreshed?.upcomingEvents, [])
            await service.stop()
        }
    }

    func testExternalGrantResetsStoreBeforeReadingAndOnlyOncePerGrant() async throws {
        let store = PermissionRecoveryCalendarStore(authorization: .denied)
        let service = RealCalendarService(store: store, preferences: try preferences())
        var updates = await service.updates().makeAsyncIterator()
        _ = await updates.next()

        // Another EventKit store, such as setup, or System Settings grants access.
        store.authorizationStatus = .fullAccess
        try await service.refresh()
        let granted = await updates.next()
        XCTAssertEqual(granted?.permission, .granted)
        XCTAssertEqual(store.calls, ["reset", "calendars"])

        try await service.refresh()
        _ = await updates.next()
        XCTAssertEqual(store.calls, ["reset", "calendars", "calendars"],
                       "Ordinary refreshes must not repeatedly reset a granted store")
        await service.stop()
    }

    func testRequestCallbackCannotFabricateOrHideAnAuthorizationGrant() async throws {
        for reportedGrant in [true, false] {
            let store = PermissionRecoveryCalendarStore(authorization: .notDetermined)
            store.requestResult = reportedGrant
            store.authorizationAfterRequest = reportedGrant ? .denied : .fullAccess
            let service = RealCalendarService(store: store, preferences: try preferences())
            var updates = await service.updates().makeAsyncIterator()
            _ = await updates.next()

            await service.requestAccess()
            let refreshed = await updates.next()
            XCTAssertEqual(refreshed?.permission, reportedGrant ? .denied : .granted,
                           "The current authorization status is authoritative")
            XCTAssertEqual(store.calls, reportedGrant ? ["request"] : ["request", "reset", "calendars"])
            await service.stop()
        }
    }

    func testRevocationStopsReadsAndRegrantReconnectsWithoutErasingSelection() async throws {
        let preferences = try preferences()
        preferences.set(["selected-calendar"], forKey: selectionKey)
        let store = PermissionRecoveryCalendarStore(authorization: .fullAccess)
        let service = RealCalendarService(store: store, preferences: preferences)
        var updates = await service.updates().makeAsyncIterator()
        _ = await updates.next()
        XCTAssertEqual(store.calls, ["reset", "calendars"])

        store.authorizationStatus = .denied
        try await service.refresh()
        let revoked = await updates.next()
        XCTAssertEqual(revoked?.permission, .denied)
        XCTAssertEqual(revoked?.calendars, [])
        XCTAssertEqual(revoked?.upcomingEvents, [])
        XCTAssertEqual(store.calls, ["reset", "calendars"], "Revocation must prevent subsequent native reads")

        store.authorizationStatus = .fullAccess
        try await service.refresh()
        let restored = await updates.next()
        XCTAssertEqual(restored?.permission, .granted)
        XCTAssertEqual(store.calls, ["reset", "calendars", "reset", "calendars"])
        XCTAssertEqual(preferences.stringArray(forKey: selectionKey), ["selected-calendar"])
        await service.stop()
    }

    func testTemporarilyEmptyCalendarsDoNotCreateAnEmptySelectionButPreserveAnExplicitOne() async throws {
        for hasExplicitSelection in [false, true] {
            let preferences = try preferences()
            if hasExplicitSelection { preferences.set([String](), forKey: selectionKey) }
            let store = PermissionRecoveryCalendarStore(authorization: .fullAccess)
            let service = RealCalendarService(store: store, preferences: preferences)
            var updates = await service.updates().makeAsyncIterator()
            _ = await updates.next()
            try await service.refresh()
            _ = await updates.next()

            if hasExplicitSelection {
                XCTAssertEqual(preferences.stringArray(forKey: selectionKey), [])
            } else {
                XCTAssertNil(preferences.object(forKey: selectionKey),
                             "Calendar loading must not save a choice to monitor nothing")
            }
            await service.stop()
        }
    }

    func testDuplicateAccessRequestsShareOneInFlightPrompt() async throws {
        let store = PermissionRecoveryCalendarStore(authorization: .notDetermined)
        store.suspendRequest = true
        let service = RealCalendarService(store: store, preferences: try preferences())
        var updates = await service.updates().makeAsyncIterator()
        _ = await updates.next()
        let firstRequest = Task { await service.requestAccess() }
        try await waitForRequest(store)

        await service.requestAccess()
        await service.requestAccess()
        XCTAssertEqual(store.calls, ["request"], "Repeated clicks must not open concurrent prompts")

        store.authorizationStatus = .fullAccess
        store.completeRequest(granted: true)
        await firstRequest.value
        let granted = await updates.next()
        XCTAssertEqual(granted?.permission, .granted)
        XCTAssertEqual(store.calls, ["request", "reset", "calendars"])
        await service.stop()
    }

    func testPermissionResponseAfterStopDoesNotReadOrPublishUntilRestart() async throws {
        let store = PermissionRecoveryCalendarStore(authorization: .notDetermined)
        store.suspendRequest = true
        let service = RealCalendarService(store: store, preferences: try preferences())
        var updates = await service.updates().makeAsyncIterator()
        _ = await updates.next()
        let request = Task { await service.requestAccess() }
        try await waitForRequest(store)

        await service.stop()
        store.authorizationStatus = .fullAccess
        store.completeRequest(granted: true)
        await request.value
        let finished = await updates.next()
        XCTAssertNil(finished)
        XCTAssertEqual(store.calls, ["request"], "An expired request must not resume native reads")

        var restarted = await service.updates().makeAsyncIterator()
        let granted = await restarted.next()
        XCTAssertEqual(granted?.permission, .granted)
        XCTAssertEqual(store.calls, ["request", "reset", "calendars"])
        await service.stop()
    }

    private func preferences() throws -> UserDefaults {
        let suite = "Notchium.CalendarPermissionRecoveryTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return preferences
    }

    private func waitForRequest(_ store: PermissionRecoveryCalendarStore,
                                file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if store.hasPendingRequest { return }
            await Task.yield()
        }
        // Release even a late-starting fake request so a regression fails without hanging.
        store.completeRequest(granted: false)
        XCTFail("The access request did not start", file: file, line: line)
        throw CancellationError()
    }
}

/// This fake never creates an EKEventStore or reads the user's Calendar database.
@MainActor
private final class PermissionRecoveryCalendarStore: CalendarEventStoreAccessing {
    var authorizationStatus: EKAuthorizationStatus
    var authorizationAfterRequest: EKAuthorizationStatus?
    var requestResult = true
    var suspendRequest = false
    private(set) var calls: [String] = []
    private var pendingRequest: CheckedContinuation<Bool, Never>?

    init(authorization: EKAuthorizationStatus) { authorizationStatus = authorization }

    var hasPendingRequest: Bool { pendingRequest != nil }

    func requestFullAccess() async throws -> Bool {
        calls.append("request")
        let result: Bool
        if suspendRequest {
            result = await withCheckedContinuation { pendingRequest = $0 }
        } else {
            result = requestResult
        }
        if let authorizationAfterRequest { authorizationStatus = authorizationAfterRequest }
        return result
    }

    func completeRequest(granted: Bool) {
        suspendRequest = false
        requestResult = granted
        let pending = pendingRequest
        pendingRequest = nil
        pending?.resume(returning: granted)
    }

    func reset() { calls.append("reset") }
    func calendars() -> [EKCalendar] { calls.append("calendars"); return [] }
    func events(from start: Date, to end: Date, calendars: [EKCalendar]) -> [EKEvent] {
        calls.append("events")
        return []
    }
}
