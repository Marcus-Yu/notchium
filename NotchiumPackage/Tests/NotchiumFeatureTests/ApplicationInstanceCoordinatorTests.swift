import Foundation
import NotchiumCore
@testable import NotchiumServices
import XCTest

@MainActor
final class ApplicationInstanceCoordinatorTests: XCTestCase {
    func testOtherBundleIdentitiesCanRunAlongsideTheApp() async throws {
        let current = instance(200, launchedAt: 20)
        let fixture = instance(300, launchedAt: 30, bundle: "com.marcusyu.notchium.uitesting")
        var terminated: [Int32] = []
        let coordinator = ApplicationInstanceCoordinator(current: current,
            snapshots: { [current, fixture] }, terminate: { terminated.append($0.processIdentifier); return true })

        let outcome = try await coordinator.waitForOlderInstancesToExit()

        XCTAssertEqual(outcome, .ready)
        XCTAssertTrue(terminated.isEmpty)
    }

    func testNewestInstanceWaitsForEveryOlderCopyToExitBeforeAdmission() async throws {
        let current = instance(200, launchedAt: 20)
        let older = [instance(100, launchedAt: 10), instance(500, launchedAt: 15)]
        let roster = ApplicationInstanceRoster(older + [current])
        var terminated: [Int32] = []
        let clock = TestAppClock(now: .distantPast, automaticallyAdvances: false)
        let coordinator = ApplicationInstanceCoordinator(current: current, snapshots: { roster.peers },
            terminate: { terminated.append($0.processIdentifier); return true }, clock: clock)
        let admission = Task { try await coordinator.waitForOlderInstancesToExit() }
        defer { admission.cancel() }
        await clock.waitForPendingSleeps()
        XCTAssertEqual(terminated, [100, 500], "Launch date takes precedence over a larger PID")

        roster.peers.removeAll { $0 == older[0] }
        await clock.advance(by: .milliseconds(50))
        await clock.waitForPendingSleeps()
        XCTAssertEqual(terminated, [100, 500], "A normal quit request is sent only once per process")

        roster.peers.removeAll { $0 == older[1] }
        await clock.advance(by: .milliseconds(50))
        let outcome = try await admission.value
        XCTAssertEqual(outcome, .ready)
    }

    func testAnAlreadyNewerInstancePreventsAllTerminationRequests() async throws {
        let current = instance(200, launchedAt: 20)
        var terminated: [Int32] = []
        let coordinator = ApplicationInstanceCoordinator(current: current,
            snapshots: { [self.instance(100, launchedAt: 10), self.instance(300, launchedAt: 30)] },
            terminate: { terminated.append($0.processIdentifier); return true })

        let outcome = try await coordinator.waitForOlderInstancesToExit()

        XCTAssertEqual(outcome, .superseded)
        XCTAssertTrue(terminated.isEmpty, "The losing launch must leave takeover to the newer one")
    }

    func testSameLaunchDateUsesPIDToAvoidMutualTermination() async throws {
        for date in [Date?.none, Date(timeIntervalSince1970: 20)] {
            let older = ApplicationInstanceCoordinator.Instance(processIdentifier: 100,
                bundleIdentifier: "com.marcusyu.notchium", launchDate: date)
            let newer = ApplicationInstanceCoordinator.Instance(processIdentifier: 200,
                bundleIdentifier: "com.marcusyu.notchium", launchDate: date)
            var terminated: [Int32] = []
            let losing = ApplicationInstanceCoordinator(current: older, snapshots: { [older, newer] },
                terminate: { terminated.append($0.processIdentifier); return true })

            let outcome = try await losing.waitForOlderInstancesToExit()

            XCTAssertEqual(outcome, .superseded)
            XCTAssertTrue(terminated.isEmpty)
            XCTAssertTrue(newer.isNewer(than: older))
            XCTAssertFalse(older.isNewer(than: newer))
        }
    }

    func testANewerLaunchArrivingDuringTakeoverSupersedesThisLaunch() async throws {
        let current = instance(200, launchedAt: 20)
        let older = instance(100, launchedAt: 10)
        let newer = instance(300, launchedAt: 30)
        let roster = ApplicationInstanceRoster([older])
        var terminated: [Int32] = []
        let clock = TestAppClock(now: .distantPast, automaticallyAdvances: false)
        let coordinator = ApplicationInstanceCoordinator(current: current, snapshots: { roster.peers },
            terminate: { terminated.append($0.processIdentifier); return true }, clock: clock)
        let admission = Task { try await coordinator.waitForOlderInstancesToExit() }
        defer { admission.cancel() }
        await clock.waitForPendingSleeps()

        roster.peers.append(newer)
        await clock.advance(by: .milliseconds(50))
        let outcome = try await admission.value

        XCTAssertEqual(outcome, .superseded)
        XCTAssertEqual(terminated, [older.processIdentifier])
    }

    func testARefusedNormalQuitDoesNotAdmitOrForceTerminate() async throws {
        let current = instance(200, launchedAt: 20)
        let clock = TestAppClock(now: .distantPast)
        var requests = 0
        let coordinator = ApplicationInstanceCoordinator(current: current,
            snapshots: { [self.instance(100, launchedAt: 10)] }, terminate: { _ in requests += 1; return false },
            clock: clock)

        let outcome = try await coordinator.waitForOlderInstancesToExit()
        let sleeps = await clock.sleepHistory()

        XCTAssertEqual(outcome, .terminationRefused)
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(sleeps.isEmpty)
    }

    func testWaitingHasABoundedBudgetAndDoesNotRepeatQuitRequests() async throws {
        let current = instance(200, launchedAt: 20)
        let clock = TestAppClock(now: .distantPast)
        var requests = 0
        let coordinator = ApplicationInstanceCoordinator(current: current,
            snapshots: { [self.instance(100, launchedAt: 10)] }, terminate: { _ in requests += 1; return true },
            clock: clock, timeout: .milliseconds(125), pollInterval: .milliseconds(50))

        let outcome = try await coordinator.waitForOlderInstancesToExit()
        let sleeps = await clock.sleepHistory()

        XCTAssertEqual(outcome, .timedOut)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(sleeps, [.milliseconds(50), .milliseconds(50), .milliseconds(25)])
    }

    func testCancellationWhileWaitingCannotAdmitTheProcess() async throws {
        let current = instance(200, launchedAt: 20)
        let clock = TestAppClock(now: .distantPast, automaticallyAdvances: false)
        let coordinator = ApplicationInstanceCoordinator(current: current,
            snapshots: { [self.instance(100, launchedAt: 10)] }, terminate: { _ in true }, clock: clock)
        let admission = Task { try await coordinator.waitForOlderInstancesToExit() }
        await clock.waitForPendingSleeps()

        admission.cancel()
        do {
            _ = try await admission.value
            XCTFail("Cancelled startup must not create application services")
        } catch is CancellationError { }
    }

    private func instance(_ pid: Int32, launchedAt: TimeInterval,
                          bundle: String = "com.marcusyu.notchium") -> ApplicationInstanceCoordinator.Instance {
        .init(processIdentifier: pid, bundleIdentifier: bundle, launchDate: Date(timeIntervalSince1970: launchedAt))
    }
}

@MainActor
private final class ApplicationInstanceRoster {
    var peers: [ApplicationInstanceCoordinator.Instance]

    init(_ peers: [ApplicationInstanceCoordinator.Instance]) {
        self.peers = peers
    }
}
