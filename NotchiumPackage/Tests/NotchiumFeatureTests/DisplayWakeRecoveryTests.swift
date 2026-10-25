import AppKit
import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
final class DisplayWakeRecoveryTests: XCTestCase {
    func testWakeRecoversWhenScreensReturnAfterTheInitialSettlingRead() async {
        let fixture = WakeRecoveryFixture()
        fixture.coordinator.start()
        defer { fixture.coordinator.stop() }
        fixture.sleep()
        fixture.source.displays = []
        fixture.wake()
        await waitForSleeps(fixture.clock, count: 2)

        await advance(fixture, by: .milliseconds(80), expectedReads: 3)
        XCTAssertNil(fixture.coordinator.shellPlacement)
        XCTAssertFalse(fixture.primaryPanel.isVisible)
        await advance(fixture, by: .milliseconds(170), expectedReads: 4)
        XCTAssertNil(fixture.coordinator.shellPlacement)

        // WindowServer returns a display without another screen-parameter notification.
        fixture.source.displays = [builtInDisplay()]
        await advance(fixture, by: .milliseconds(750), expectedReads: 5)
        XCTAssertEqual(fixture.coordinator.shellPlacement?.display.id.rawValue, 1)
        XCTAssertTrue(fixture.primaryPanel.isVisible)
        XCTAssertFalse(fixture.coordinator.displayState.sleeping)
    }

    func testWakeRetriesNativeReconciliationWhenGeometryIsUnchanged() async {
        let fixture = WakeRecoveryFixture()
        fixture.coordinator.start()
        defer { fixture.coordinator.stop() }
        let placement = fixture.coordinator.shellPlacement
        fixture.sleep()
        // Model the native screen lookup failing during both initial wake reads.
        fixture.primaryPanel.reconciliationsToReject = 2
        fixture.wake()
        await waitForSleeps(fixture.clock, count: 2)
        await advance(fixture, by: .milliseconds(80), expectedReads: 3)
        XCTAssertEqual(fixture.coordinator.shellPlacement, placement)
        XCTAssertFalse(fixture.primaryPanel.isVisible)

        await advance(fixture, by: .milliseconds(170), expectedReads: 4)
        XCTAssertTrue(fixture.primaryPanel.isVisible,
                      "An unchanged cached layout must not suppress a native placement retry")
        XCTAssertEqual(fixture.primaryPanel.placement, placement)
    }

    func testWakeRecoveryRestoresAnUnexpectedlyHiddenPanelWithoutGeometryChanges() async {
        let fixture = WakeRecoveryFixture()
        fixture.coordinator.start()
        defer { fixture.coordinator.stop() }
        fixture.sleep()
        fixture.wake()
        await waitForSleeps(fixture.clock, count: 2)
        await advance(fixture, by: .milliseconds(80), expectedReads: 3)
        let placement = fixture.primaryPanel.placement
        let reconciliations = fixture.primaryPanel.reconciliations
        fixture.primaryPanel.isVisible = false

        await advance(fixture, by: .milliseconds(170), expectedReads: 4)

        XCTAssertEqual(fixture.primaryPanel.reconciliations, reconciliations + 1)
        XCTAssertEqual(fixture.primaryPanel.placement, placement)
        XCTAssertTrue(fixture.primaryPanel.isVisible)
    }

    func testRepeatedWakeReplacesRecoveryAndStopsAfterItsBoundedAttempts() async {
        let fixture = WakeRecoveryFixture()
        fixture.coordinator.start()
        defer { fixture.coordinator.stop() }
        fixture.sleep()
        fixture.wake()
        await waitForSleeps(fixture.clock, count: 2)
        await advance(fixture, by: .milliseconds(80), expectedReads: 3)
        await advance(fixture, by: .milliseconds(170), expectedReads: 4)

        // Restart at 250 ms, after the old loop registered its next 750 ms wait.
        fixture.wake()
        await waitForSleeps(fixture.clock, count: 2, quarterSecondRequests: 2)
        await advance(fixture, by: .milliseconds(80), expectedReads: 6)
        await advance(fixture, by: .milliseconds(170), expectedReads: 7)
        await fixture.clock.advance(by: .milliseconds(500))
        await drainMainActorTasks()
        XCTAssertEqual(fixture.source.reads, 7,
                       "The cancelled loop must not read topology at its former one-second deadline")

        await advance(fixture, by: .milliseconds(250), expectedReads: 8)
        await advance(fixture, by: .seconds(2), expectedReads: 9)
        await advance(fixture, by: .seconds(5), expectedReads: 10, remainingSleeps: 0)
        let reassertions = fixture.primaryPanel.reassertions
        await fixture.clock.advance(by: .seconds(60))
        await drainMainActorTasks()
        XCTAssertEqual(fixture.source.reads, 10, "Wake recovery must not become periodic polling")
        XCTAssertEqual(fixture.primaryPanel.reassertions, reassertions)
    }

    func testSleepingAgainCancelsRecoveryAndKeepsPanelsHidden() async {
        let fixture = WakeRecoveryFixture()
        fixture.coordinator.start()
        defer { fixture.coordinator.stop() }
        fixture.sleep()
        fixture.wake()
        await waitForSleeps(fixture.clock, count: 2)
        fixture.sleep()
        await waitForSleeps(fixture.clock, count: 0)
        let reads = fixture.source.reads
        let reconciliations = fixture.primaryPanel.reconciliations
        let reassertions = fixture.primaryPanel.reassertions

        await fixture.clock.advance(by: .seconds(10))
        await drainMainActorTasks()

        XCTAssertTrue(fixture.coordinator.displayState.sleeping)
        XCTAssertFalse(fixture.primaryPanel.isVisible)
        XCTAssertEqual(fixture.source.reads, reads)
        XCTAssertEqual(fixture.primaryPanel.reconciliations, reconciliations)
        XCTAssertEqual(fixture.primaryPanel.reassertions, reassertions)
    }

    func testStopAndRestartCannotBeChangedByThePreviousWakeRecovery() async {
        let fixture = WakeRecoveryFixture()
        fixture.coordinator.start()
        defer { fixture.coordinator.stop() }
        fixture.sleep()
        fixture.wake()
        await waitForSleeps(fixture.clock, count: 2)
        fixture.coordinator.stop()
        fixture.coordinator.start()
        await waitForSleeps(fixture.clock, count: 0)
        let reads = fixture.source.reads
        let reconciliations = fixture.primaryPanel.reconciliations
        let reassertions = fixture.primaryPanel.reassertions

        await fixture.clock.advance(by: .seconds(10))
        await drainMainActorTasks()

        XCTAssertFalse(fixture.coordinator.displayState.sleeping)
        XCTAssertTrue(fixture.primaryPanel.isVisible)
        XCTAssertEqual(fixture.source.reads, reads)
        XCTAssertEqual(fixture.primaryPanel.reconciliations, reconciliations)
        XCTAssertEqual(fixture.primaryPanel.reassertions, reassertions)
    }

    func testWakeRestoresAllDisplaysWhenTheirOnlineIdentifiersChange() async throws {
        let externalIdentity = UUID()
        func monitor(id: UInt32) -> NotchiumDisplaySnapshot {
            NotchiumDisplaySnapshot(id: .init(rawValue: id), name: "External",
                frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                isBuiltIn: false, isPrimary: false, persistentID: externalIdentity)
        }
        let fixture = WakeRecoveryFixture(displays: [builtInDisplay(), monitor(id: 2)], allDisplays: true)
        fixture.coordinator.start()
        defer { fixture.coordinator.stop() }
        let previousExternal = try XCTUnwrap(fixture.coordinator.presentationModel(for: .init(rawValue: 2)))
        previousExternal.present(.expanded, animated: false)
        fixture.sleep()
        fixture.source.displays = []
        fixture.wake()
        await waitForSleeps(fixture.clock, count: 2)
        await advance(fixture, by: .milliseconds(80), expectedReads: 3)
        fixture.source.displays = [builtInDisplay(id: 7), monitor(id: 9)]

        await advance(fixture, by: .milliseconds(170), expectedReads: 4)

        XCTAssertEqual(fixture.coordinator.shellPlacements.map { $0.display.id.rawValue }, [7, 9])
        XCTAssertNil(fixture.coordinator.presentationModel(for: .init(rawValue: 2)))
        let returnedExternal = try XCTUnwrap(fixture.coordinator.presentationModel(for: .init(rawValue: 9)))
        XCTAssertFalse(returnedExternal === previousExternal)
        XCTAssertEqual(returnedExternal.visualState, .collapsed)
        let visibleIDs = fixture.panels.values.filter(\.isVisible).compactMap { $0.placement?.display.id.rawValue }
        XCTAssertEqual(Set(visibleIDs), Set([UInt32(7), UInt32(9)]))
    }

    private func advance(_ fixture: WakeRecoveryFixture, by duration: Duration,
                         expectedReads: Int, remainingSleeps: Int = 1,
                         file: StaticString = #filePath, line: UInt = #line) async {
        await fixture.clock.advance(by: duration)
        await waitUntil { fixture.source.reads >= expectedReads }
        XCTAssertEqual(fixture.source.reads, expectedReads, file: file, line: line)
        await waitForSleeps(fixture.clock, count: remainingSleeps, file: file, line: line)
    }

    /// Bounded registration waits make a missing/cancelled recovery fail instead of hanging.
    private func waitForSleeps(_ clock: TestAppClock, count: Int, quarterSecondRequests: Int = 0,
                               file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<10_000 {
            let pending = await clock.pendingSleepCount()
            let quarterSeconds = await clock.sleepHistory().filter { $0 == .milliseconds(250) }.count
            if pending == count, quarterSeconds >= quarterSecondRequests { return }
            await Task.yield()
        }
        let pending = await clock.pendingSleepCount()
        XCTFail("Expected \(count) pending sleeps; found \(pending)", file: file, line: line)
    }
}

@MainActor
private final class WakeRecoveryFixture {
    let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
    let source: WakeRecoveryDisplaySource
    let panels = WakeRecoveryPanels()
    let coordinator: NotchiumDisplayCoordinator
    var primaryPanel: WakeRecoveryPanel { panels.values[0] }

    init(displays: [NotchiumDisplaySnapshot] = [builtInDisplay()], allDisplays: Bool = false) {
        source = WakeRecoveryDisplaySource(displays: displays)
        let settings = NotchDisplaySettings()
        if allDisplays { settings.preferences.selection = .all }
        let panels = panels
        coordinator = NotchiumDisplayCoordinator(clock: clock, displaySource: source,
            panelControllerFactory: { _ in
                let panel = WakeRecoveryPanel()
                panels.values.append(panel)
                return panel
            }, settings: settings)
    }

    func sleep() {
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    }

    func wake() {
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    }
}

@MainActor
private final class WakeRecoveryDisplaySource: NotchiumDisplaySnapshotting {
    var displays: [NotchiumDisplaySnapshot]
    private(set) var reads = 0
    init(displays: [NotchiumDisplaySnapshot]) { self.displays = displays }
    func snapshots() -> [NotchiumDisplaySnapshot] {
        reads += 1
        return displays
    }
}

@MainActor
private final class WakeRecoveryPanels {
    var values: [WakeRecoveryPanel] = []
}

@MainActor
private final class WakeRecoveryPanel: NotchPanelControlling {
    var isVisible = false
    var reconciliationsToReject = 0
    private(set) var placement: NotchShellPlacement?
    private(set) var reconciliations = 0
    private(set) var reassertions = 0

    func reconcile(placement: NotchShellPlacement, layout: NotchPanelLayout,
                   renderConfiguration: NotchShellRenderConfiguration, animated: Bool) {
        reconciliations += 1
        guard reconciliationsToReject == 0 else {
            reconciliationsToReject -= 1
            hide()
            return
        }
        self.placement = placement
        isVisible = true
    }

    func hide() { isVisible = false; placement = nil }
    func orderFrontRegardless() {
        reassertions += 1
        if placement != nil { isVisible = true }
    }
}
