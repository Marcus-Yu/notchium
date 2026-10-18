import Foundation
import NotchiumCore
@testable import NotchiumFocusFeature
import NotchiumDynamicIsland
import NotchiumServices
import XCTest

@MainActor
final class Stage27FocusOrderingTests: XCTestCase {
    func testStopCancelsTheRunningShortcutAndDoesNotStartQueuedWork() async throws {
        let suite = "Notchium.Stage27.FocusStop.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let started = expectation(description: "Shortcut started")
        let canceled = expectation(description: "Running shortcut canceled")
        let queued = expectation(description: "Queued work must not start after stop")
        queued.isInverted = true
        let shortcuts = CancelObservedFocusShortcuts(started: started, canceled: canceled, queued: queued)
        let activities = ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        defer { activities.clearAll() }
        let model = FocusModeModel(service: MockFocusService(), activities: activities,
                                  shortcuts: shortcuts, preferences: defaults)
        model.timerControlsFocus = true
        model.focusOnShortcut = .init(id: UUID(), name: "On")
        model.focusOffShortcut = .init(id: UUID(), name: "Off")
        model.focusSessionBegan()
        await fulfillment(of: [started], timeout: 2)
        model.focusSessionEnded()
        model.stop()
        await fulfillment(of: [canceled], timeout: 2)
        await fulfillment(of: [queued], timeout: 0.1)
    }

    func testFocusOffWaitsForAnInFlightFocusOnShortcut() async throws {
        let suite = "Notchium.Stage27.Focus.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let on = ExistingShortcut(id: UUID(), name: "On")
        let off = ExistingShortcut(id: UUID(), name: "Off")
        let onBegan = expectation(description: "On is running")
        let prematureOff = expectation(description: "Off must not run while On is suspended")
        prematureOff.isInverted = true
        let offFinished = expectation(description: "Off finished")
        let shortcuts = SuspendedFocusShortcuts(on: on, onBegan: onBegan,
            prematureOff: prematureOff, offFinished: offFinished)
        let activities = ActivityCoordinator(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        defer { activities.clearAll() }
        let model = FocusModeModel(service: MockFocusService(), activities: activities,
                                  shortcuts: shortcuts, preferences: defaults)
        model.timerControlsFocus = true
        model.focusOnShortcut = on
        model.focusOffShortcut = off
        model.focusSessionBegan()
        await fulfillment(of: [onBegan], timeout: 2)
        model.focusSessionEnded()
        await fulfillment(of: [prematureOff], timeout: 0.1)
        await shortcuts.finishOn()
        await fulfillment(of: [offFinished], timeout: 2)
        let completions = await shortcuts.completions
        XCTAssertEqual(completions, [on, off], "The compensating Off must be the last side effect")
    }
}

private actor CancelObservedFocusShortcuts: ShortcutService {
    let started: XCTestExpectation
    let canceled: XCTestExpectation
    let queued: XCTestExpectation
    let clock = TestAppClock(now: .now, automaticallyAdvances: false)
    init(started: XCTestExpectation, canceled: XCTestExpectation, queued: XCTestExpectation) {
        self.started = started; self.canceled = canceled; self.queued = queued
    }
    func list() -> [ExistingShortcut] { [] }
    func run(_ shortcut: ExistingShortcut) async throws {
        guard shortcut.name == "On" else { queued.fulfill(); return }
        started.fulfill()
        do { try await clock.sleep(for: .seconds(3_600)) }
        catch { canceled.fulfill(); throw error }
    }
}

private actor SuspendedFocusShortcuts: ShortcutService {
    let on: ExistingShortcut
    let onBegan: XCTestExpectation
    let prematureOff: XCTestExpectation
    let offFinished: XCTestExpectation
    private var pendingOn: CheckedContinuation<Void, Never>?
    private(set) var completions: [ExistingShortcut] = []

    init(on: ExistingShortcut, onBegan: XCTestExpectation, prematureOff: XCTestExpectation,
         offFinished: XCTestExpectation) {
        self.on = on; self.onBegan = onBegan
        self.prematureOff = prematureOff; self.offFinished = offFinished
    }
    func list() -> [ExistingShortcut] { [] }
    func run(_ shortcut: ExistingShortcut) async throws {
        if shortcut == on {
            await withCheckedContinuation { pendingOn = $0; onBegan.fulfill() }
        } else if pendingOn != nil { prematureOff.fulfill() }
        completions.append(shortcut)
        if shortcut != on { offFinished.fulfill() }
    }
    func finishOn() { pendingOn?.resume(); pendingOn = nil }
}
