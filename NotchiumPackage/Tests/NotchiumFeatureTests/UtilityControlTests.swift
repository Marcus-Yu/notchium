import Foundation
import NotchiumCaffeineFeature
import NotchiumCore
@testable import NotchiumDynamicIsland
@testable import NotchiumKeyboardLockFeature
@testable import NotchiumServices
import CoreGraphics
import XCTest

@MainActor
final class UtilityControlTests: XCTestCase {
    func testCaffeineClicksToggleAndHoldSelectsDisplayMode() async {
        let service = MockCaffeineService()
        let model = CaffeineControlModel(service: service)
        model.start()
        defer { model.stop() }
        await drainMainActorTasks()

        model.cycleMode()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .system)

        model.cycleMode()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .off)

        model.keepDisplayAwake()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .systemAndDisplay)

        model.cycleMode()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .off)
    }

    func testCaffeineHoldFromGreenAndBlueClick() async {
        let model = CaffeineControlModel(service: MockCaffeineService())
        model.start()
        defer { model.stop() }
        await drainMainActorTasks()
        model.cycleMode()
        await drainMainActorTasks()
        model.keepDisplayAwake()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .systemAndDisplay)
        model.cycleMode()
        await drainMainActorTasks()
        XCTAssertEqual(model.mode, .off)
    }

    func testCaffeinePressDeadlineConsumesClickExactlyOnce() {
        let start = ContinuousClock.now
        var press = CaffeinePressState()
        press.begin(at: start)
        XCTAssertFalse(press.complete(at: start + .milliseconds(749)))
        XCTAssertTrue(press.complete(at: start + .milliseconds(750)))
        XCTAssertFalse(press.complete(at: start + .seconds(1)))
        XCTAssertFalse(press.end())
        XCTAssertFalse(press.end())
    }

    func testCaffeineShortPressClicksAndCancelledPressDoesNothing() {
        let start = ContinuousClock.now
        var press = CaffeinePressState()
        press.begin(at: start)
        XCTAssertFalse(press.complete(at: start + .milliseconds(200)))
        XCTAssertTrue(press.end())
        XCTAssertFalse(press.complete(at: start + .seconds(1)))
        press.begin(at: start)
        press.cancel()
        XCTAssertFalse(press.complete(at: start + .seconds(1)))
        XCTAssertFalse(press.end())
    }

    func testKeyboardFirstLockExplanationAppearsOnlyOncePerInstallation() async throws {
        let suiteName = "UtilityControlTests.firstLock.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let service = MockKeyboardLockService()
        let model = KeyboardLockControlModel(service: service, preferences: preferences)
        model.start()
        defer { model.stop() }
        await drainMainActorTasks()

        model.toggleLock()
        for _ in 0..<1_000 where model.guidance == nil {
            await Task.yield()
        }
        XCTAssertTrue(model.isLocked)
        XCTAssertEqual(model.guidance, .firstLock)

        model.dismissGuidance()
        model.toggleLock()
        await drainMainActorTasks()
        model.toggleLock()
        await drainMainActorTasks()
        XCTAssertTrue(model.isLocked)
        XCTAssertNil(model.guidance)
    }

    func testPermissionGuidanceDoesNotOpenSettingsUntilExplicitAction() async {
        let service = PermissionKeyboardLockService()
        let model = KeyboardLockControlModel(service: service)
        model.start()
        defer { model.stop() }
        await drainMainActorTasks()

        model.toggleLock()
        for _ in 0..<1_000 where model.guidance == nil {
            await Task.yield()
        }

        XCTAssertFalse(model.isLocked)
        XCTAssertEqual(
            model.guidance,
            .permissionsRequired([.accessibility, .inputMonitoring])
        )
        XCTAssertEqual(service.openSettingsCount, 0)

        model.openSystemSettings()
        XCTAssertEqual(service.openSettingsCount, 1)
        XCTAssertNil(model.guidance)
    }

    func testRealKeyboardCallbackPassesThroughWhenUnlocked() throws {
        let service = RealKeyboardLockService()
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        XCTAssertNotNil(service.handleTapEvent(type: .keyDown, event: event))
        XCTAssertNotNil(service.handleTapEvent(type: .keyUp, event: event))
        XCTAssertNotNil(service.handleTapEvent(type: .flagsChanged, event: event))
        XCTAssertNotNil(service.handleTapEvent(type: .leftMouseDown, event: event))
        XCTAssertNotNil(service.handleTapEvent(type: .tapDisabledByTimeout, event: event))
    }

    func testSecureInputEndsLockAndExplainsWhy() async {
        let service = MockKeyboardLockService()
        let model = KeyboardLockControlModel(service: service)
        model.start()
        defer { model.stop() }
        await drainMainActorTasks()
        service.publish(KeyboardLockSnapshot(availability: .available, isLocked: true))
        await drainMainActorTasks()
        XCTAssertTrue(model.isLocked)
        service.publish(KeyboardLockSnapshot(availability: .available, issue: .secureInputEnabled))
        await drainMainActorTasks()
        XCTAssertFalse(model.isLocked)
        XCTAssertEqual(model.guidance, .secureInputEnabled)
    }

    func testEmergencyProgressAndTapDisableFailOpenArePublished() async throws {
        let suiteName = "UtilityControlTests.failOpen.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let service = MockKeyboardLockService()
        let model = KeyboardLockControlModel(service: service, preferences: preferences)
        model.start()
        defer {
            model.stop()
            preferences.removePersistentDomain(forName: suiteName)
        }
        await drainMainActorTasks()

        let startedAt = Date(timeIntervalSince1970: 42)
        service.publish(KeyboardLockSnapshot(
            availability: .available,
            isLocked: true,
            emergencyUnlockStartedAt: startedAt
        ))
        await drainMainActorTasks()
        XCTAssertTrue(model.isLocked)
        XCTAssertEqual(model.emergencyUnlockStartedAt, startedAt)

        service.publish(KeyboardLockSnapshot(
            availability: .available,
            isLocked: false,
            issue: .eventTapDisabled
        ))
        await drainMainActorTasks()
        XCTAssertFalse(model.isLocked)
        XCTAssertNil(model.emergencyUnlockStartedAt)
        XCTAssertEqual(model.guidance, .lockEnded)
    }
}

private final class PermissionKeyboardLockService: KeyboardLockService, @unchecked Sendable {
    private let gate = NSLock()
    private var settingsOpenCount = 0

    var openSettingsCount: Int {
        gate.withLock { settingsOpenCount }
    }

    func availability() async -> FeatureAvailability { .available }

    func updates() async -> AsyncStream<KeyboardLockSnapshot> {
        AsyncStream { continuation in
            continuation.yield(KeyboardLockSnapshot(availability: .available))
        }
    }

    func lock(policy: KeyboardLockPolicy) async throws {
        throw KeyboardLockFailure.permissionsRequired([.accessibility, .inputMonitoring])
    }

    func unlock() async {}

    func openPermissionSettings(for permissions: Set<PermissionKind>) {
        gate.withLock { settingsOpenCount += 1 }
    }

    func shutdown() {}
}
