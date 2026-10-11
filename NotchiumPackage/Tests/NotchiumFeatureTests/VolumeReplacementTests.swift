import CoreGraphics
import IOKit.hidsystem
import Synchronization
import XCTest
import NotchiumServices
@testable import NotchiumServices
@testable import NotchiumFeature

final class VolumeReplacementTests: XCTestCase {
    func testReplayIsSingleUseAndMarkedEventsAlwaysBypassInterception() {
        let replay = SingleVolumeReplay()
        XCTAssertTrue(replay.claim())
        for _ in 0..<100 { XCTAssertFalse(replay.claim()) }
        XCTAssertTrue(VolumeEventReplayGuard.isReplay(VolumeEventReplayGuard.marker))
        XCTAssertFalse(VolumeEventReplayGuard.isReplay(0))
    }

    func testReadOnlyMutedOutputAndInvalidReadingsPassThroughBeforeWriting() {
        let hardware = Hardware(volumes: [0.5])
        hardware.muted = true
        hardware.supportsMute = false
        var operation = VolumeKeyOperation()
        XCTAssertEqual(operation.apply(.up, fine: false, repeated: false, deviceID: 7, hardware: hardware), .notApplied)
        hardware.muted = false
        hardware.unavailableReading = true
        XCTAssertEqual(operation.apply(.up, fine: false, repeated: false, deviceID: 7, hardware: hardware), .notApplied)
        hardware.unavailableReading = false
        hardware.volumes = [.nan]
        XCTAssertEqual(operation.apply(.up, fine: false, repeated: false, deviceID: 7, hardware: hardware), .notApplied)
        XCTAssertEqual(hardware.volumeWrites + hardware.muteWrites, 0)
    }
    func testSingleKeyChangesVolumeOnceAndReturnsActualQuantizedReadback() {
        let hardware = Hardware(volumes: [0.5], quantum: 0.1)
        var operation = VolumeKeyOperation()
        let result = operation.apply(.up, fine: false, repeated: false, deviceID: 7, hardware: hardware)
        XCTAssertEqual(hardware.volumeWrites, 1)
        guard case let .applied(actual) = result else { return XCTFail("Expected verified reading") }
        XCTAssertEqual(actual.volume!, 0.6, accuracy: 0.0001)
        XCTAssertNotEqual(actual.volume, 0.5625)
    }

    func testFineStepsAccumulateOnQuantizedOutputWithoutInventingReadings() {
        let hardware = Hardware(volumes: [0.5], quantum: 0.1)
        var operation = VolumeKeyOperation()
        for _ in 0..<4 {
            let result = operation.apply(.up, fine: true, repeated: true, deviceID: 7, hardware: hardware)
            guard case let .applied(actual) = result else { return XCTFail("Expected actual reading") }
            XCTAssertEqual(actual.volumes, hardware.volumes)
        }
        XCTAssertEqual(hardware.volumes[0], 0.6, accuracy: 0.0001)
        XCTAssertEqual(hardware.volumeWrites, 4)
    }

    func testVolumeLimitsAndMuteRepeatDoNotCauseExtraActions() {
        let hardware = Hardware(volumes: [1])
        var operation = VolumeKeyOperation()
        _ = operation.apply(.up, fine: false, repeated: true, deviceID: 7, hardware: hardware)
        XCTAssertEqual(hardware.volumeWrites, 0)
        hardware.volumes = [0]
        _ = operation.apply(.down, fine: false, repeated: false, deviceID: 7, hardware: hardware)
        XCTAssertEqual(hardware.volumeWrites, 0)
        _ = operation.apply(.mute, fine: false, repeated: false, deviceID: 7, hardware: hardware)
        _ = operation.apply(.mute, fine: false, repeated: true, deviceID: 7, hardware: hardware)
        XCTAssertTrue(hardware.muted)
        XCTAssertEqual(hardware.muteWrites, 1)
        _ = operation.apply(.up, fine: false, repeated: false, deviceID: 7, hardware: hardware)
        XCTAssertFalse(hardware.muted)
        XCTAssertEqual(hardware.volumes[0], 1.0 / 16)
    }

    func testChannelBalanceAndExternalChangesRemainAuthoritative() {
        let hardware = Hardware(volumes: [0.5, 0.25])
        var operation = VolumeKeyOperation()
        _ = operation.apply(.up, fine: false, repeated: false, deviceID: 7, hardware: hardware)
        XCTAssertEqual(hardware.volumes, [0.5625, 0.28125])
        hardware.volumes = [0.75, 0.375]
        _ = operation.apply(.down, fine: false, repeated: false, deviceID: 7, hardware: hardware)
        XCTAssertEqual(hardware.volumes, [0.6875, 0.34375])
    }

    func testRouteChangesAndUnsupportedControlsFailBeforeWriting() {
        let hardware = Hardware(volumes: [0.5])
        var operation = VolumeKeyOperation()
        hardware.defaultID = 8
        XCTAssertEqual(operation.apply(.up, fine: false, repeated: false, deviceID: 7, hardware: hardware), .notApplied)
        hardware.defaultID = 7
        hardware.supportsMute = false
        XCTAssertEqual(operation.apply(.mute, fine: false, repeated: false, deviceID: 7, hardware: hardware), .notApplied)
        hardware.supportsVolume = false
        XCTAssertEqual(operation.apply(.up, fine: false, repeated: false, deviceID: 7, hardware: hardware), .notApplied)
        XCTAssertEqual(hardware.volumeWrites + hardware.muteWrites, 0)
    }

    func testWriteFailureAndMissingReadbackNeverAuthorizeReplay() {
        for missingReadback in [false, true] {
            let hardware = Hardware(volumes: [0.5])
            hardware.failWrite = !missingReadback
            hardware.loseReadback = missingReadback
            var operation = VolumeKeyOperation()
            XCTAssertEqual(operation.apply(.up, fine: false, repeated: false, deviceID: 7, hardware: hardware), .uncertain)
            XCTAssertEqual(hardware.volumeWrites, 1)
        }
    }

    func testGateBoundsAndInvalidatesQueuedCommandsAcrossLifecycleChanges() throws {
        let gate = VolumeInputGate()
        XCTAssertNil(gate.reserve(.up))
        gate.configure(.init(deviceID: 7, volume: true, mute: false))
        XCTAssertNil(gate.reserve(.mute))
        let reservation = try XCTUnwrap(gate.reserve(.up))
        XCTAssertTrue(gate.isCurrent(reservation.1))
        for _ in 1..<VolumeInputGate.maximumPending { XCTAssertNotNil(gate.reserve(.down)) }
        XCTAssertNil(gate.reserve(.up))
        gate.invalidate()
        XCTAssertFalse(gate.isCurrent(reservation.1))
        XCTAssertNil(gate.reserve(.up))
        for _ in 0..<VolumeInputGate.maximumPending { gate.complete() }
        gate.configure(.init(deviceID: 8, volume: true, mute: true))
        let next = try XCTUnwrap(gate.reserve(.mute))
        XCTAssertNotEqual(reservation.1, next.1)
        gate.complete()
        gate.close()
        XCTAssertFalse(gate.isLive)
    }

    func testParserLeavesOtherKeysReleasesAndUnsupportedModifiersNative() throws {
        func input(_ key: Int32, down: Bool = true, flags: CGEventFlags = []) -> VolumeKeyInput? {
            VolumeKeyInput(subtype: Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                data1: Int(key) << 16 | (Int(down ? NX_KEYDOWN : NX_KEYUP) << 8), flags: flags)
        }
        XCTAssertNil(input(NX_KEYTYPE_PLAY))
        XCTAssertNil(input(NX_KEYTYPE_BRIGHTNESS_UP))
        XCTAssertFalse(try XCTUnwrap(input(NX_KEYTYPE_SOUND_UP, down: false)).isDown)
        for flags: CGEventFlags in [.maskAlternate, .maskShift, .maskControl, .maskCommand] {
            XCTAssertFalse(try XCTUnwrap(input(NX_KEYTYPE_SOUND_UP, flags: flags)).eligibleModifiers)
        }
        let fine = try XCTUnwrap(input(NX_KEYTYPE_SOUND_UP, flags: [.maskShift, .maskAlternate]))
        XCTAssertTrue(fine.fine)
        XCTAssertTrue(fine.eligibleModifiers)
    }
}

private final class Hardware: VolumeKeyHardware {
    var defaultID: UInt32 = 7
    var volumes: [Double]
    var muted = false
    var supportsVolume = true
    var supportsMute = true
    var failWrite = false
    var loseReadback = false
    var unavailableReading = false
    var volumeWrites = 0
    var muteWrites = 0
    let quantum: Double?
    init(volumes: [Double], quantum: Double? = nil) { self.volumes = volumes; self.quantum = quantum }
    func defaultOutputID() -> UInt32 { defaultID }
    func read(_ deviceID: UInt32) -> VolumeHardwareState? {
        if unavailableReading { return nil }
        if loseReadback && volumeWrites > 0 { return nil }
        return .init(deviceID: deviceID, volumeElements: supportsVolume ? Array(0..<UInt32(volumes.count)) : [],
            volumes: supportsVolume ? volumes : [], muteElements: supportsMute ? [0] : [], muted: muted)
    }
    func writeVolume(_ values: [Double], state: VolumeHardwareState) -> Bool {
        volumeWrites += 1
        if failWrite { return false }
        volumes = values.map { value in quantum.map { (value / $0).rounded() * $0 } ?? value }
        return true
    }
    func writeMute(_ muted: Bool, state: VolumeHardwareState) -> Bool {
        muteWrites += 1
        self.muted = muted
        return !failWrite
    }
}

@MainActor
final class SystemFeedbackCoordinatorTests: XCTestCase {
    func testPreferencePersistsAndNeverPromptsAtStartOrRelaunch() {
        let suite = "Notchium.SystemFeedbackTests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let control = FeedbackControl()
        let model = SystemFeedbackCoordinator(control: control, preferences: preferences)
        model.start()
        XCTAssertEqual(control.requests, [false])
        model.setReplaceVolumeHUD(true, requestPermission: true)
        XCTAssertEqual(control.requests, [false, true])
        model.stop()
        let restored = SystemFeedbackCoordinator(control: control, preferences: preferences)
        restored.start()
        XCTAssertTrue(restored.replaceVolumeHUD)
        XCTAssertEqual(control.requests, [false, true, false])
        XCTAssertEqual(restored.brightness, .unavailable)
        XCTAssertEqual(restored.airPods, .passive)
        restored.stop()
        XCTAssertEqual(control.stops, 2)
    }

    func testUnavailableControlsStayIndependent() {
        let model = SystemFeedbackCoordinator(control: nil)
        model.start()
        XCTAssertEqual(model.volume.mode, .unavailable)
        XCTAssertEqual(model.airPods, .passive)
        model.stop()
    }
}

@MainActor
private final class FeedbackControl: SystemFeedbackControlling {
    var requests: [Bool] = []
    var stops = 0
    func volumeReplacementUpdates() -> AsyncStream<VolumeReplacementStatus> {
        AsyncStream { $0.yield(.init(mode: .passive, fallback: .permissionRequired)); $0.finish() }
    }
    func setVolumeReplacementEnabled(_ enabled: Bool, requestPermission: Bool) { requests.append(requestPermission) }
    func stopVolumeReplacement() { stops += 1 }
}
