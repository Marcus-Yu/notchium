import AppKit
import IOKit.hidsystem
import NotchiumCore
import XCTest
@testable import NotchiumAudioFeature
@testable import NotchiumDynamicIsland
@testable import NotchiumServices

@MainActor
final class VolumeBoundaryHUDTests: XCTestCase {
    func testOnlyVolumeKeyDownAndRepeatsDecodeAsCommands() {
        func data(_ key: Int32, down: Bool = true, repeatKey: Bool = false) -> Int {
            (Int(key) << 16) | ((down ? Int(NX_KEYDOWN) : Int(NX_KEYUP)) << 8) | (repeatKey ? 1 : 0)
        }
        let subtype = Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS)
        XCTAssertEqual(AudioVolumeCommand(systemDefinedSubtype: subtype, data1: data(NX_KEYTYPE_SOUND_DOWN)), .down)
        XCTAssertEqual(AudioVolumeCommand(systemDefinedSubtype: subtype, data1: data(NX_KEYTYPE_SOUND_UP)), .up)
        XCTAssertEqual(AudioVolumeCommand(systemDefinedSubtype: subtype,
                                          data1: data(NX_KEYTYPE_SOUND_DOWN, repeatKey: true)), .down)
        XCTAssertNil(AudioVolumeCommand(systemDefinedSubtype: subtype, data1: data(NX_KEYTYPE_SOUND_DOWN, down: false)))
        XCTAssertNil(AudioVolumeCommand(systemDefinedSubtype: subtype, data1: data(NX_KEYTYPE_MUTE)))
        XCTAssertNil(AudioVolumeCommand(systemDefinedSubtype: 0, data1: data(NX_KEYTYPE_SOUND_DOWN)))
    }

    func testOrdinaryVolumeStillUsesHALAndBoundaryCommandsDoNotWriteAudio() async {
        let service = RecordingVolumeService()
        let audio = makeAudio(service)
        var values: [Double?] = []
        audio.onHUD = { values.append($0.volume) }
        audio.receive(snapshot(0.5))
        XCTAssertTrue(values.isEmpty, "Launch snapshot is silent")
        audio.receiveVolumeCommand(.init(command: .down, output: output(0.5)))
        XCTAssertTrue(values.isEmpty, "An interior press uses the normal HAL update")
        audio.receive(snapshot(0.4375))
        XCTAssertEqual(values, [0.4375])
        audio.receive(snapshot(0))
        audio.receiveVolumeCommand(.init(command: .down, output: output(0)))
        audio.receiveVolumeCommand(.init(command: .down, output: output(0)))
        XCTAssertEqual(values, [0.4375, 0, 0, 0])
        XCTAssertEqual(audio.devices.currentOutput?.volume, 0)
        XCTAssertNil(audio.displayVolume)
        audio.receive(snapshot(1))
        audio.receiveVolumeCommand(.init(command: .up, output: output(1)))
        XCTAssertEqual(values.suffix(2), [1, 1])
        let writes = await service.writeCount
        XCTAssertEqual(writes, 0)
    }

    func testBoundaryFeedbackCoalescesRefreshesAndUsesExistingShellInBothStates() async throws {
        for expanded in [false, true] {
            let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
            let presentation = DynamicIslandPresentationModel(clock: clock)
            defer { presentation.reset() }
            let audio = makeAudio(RecordingVolumeService())
            audio.onHUD = { presentation.showAudioHUD($0) }
            if expanded {
                presentation.present(.expanded, animated: false)
                presentation.pageModel.selectedPage = .shelf
            }
            audio.receive(snapshot(0))
            audio.receiveVolumeCommand(.init(command: .down, output: output(0)))
            await clock.waitForPendingSleeps()
            let identity = try XCTUnwrap(presentation.activityCoordinator.activeTransient?.id)
            XCTAssertEqual(presentation.audioHUD?.volume, 0)
            for press in 1...3 {
                await clock.advance(by: .seconds(1))
                audio.receiveVolumeCommand(.init(command: .down, output: output(0)))
                await settleDeadline(presentation, at: Date(timeIntervalSince1970: Double(press) + 1.75))
                XCTAssertEqual(presentation.activityCoordinator.activeTransient?.id, identity)
                XCTAssertEqual(presentation.activityCoordinator.liveActivities.count, 1)
                XCTAssertEqual(presentation.activityCoordinator.queueCount, 0)
                XCTAssertEqual(presentation.audioHUD?.volume, 0)
                if expanded {
                    XCTAssertEqual(presentation.expandedMinorActivity?.id, identity)
                    XCTAssertNil(presentation.presentedNotification)
                    XCTAssertEqual(presentation.pageModel.selectedPage, .shelf)
                    XCTAssertEqual(presentation.visualState, .expanded)
                } else {
                    XCTAssertEqual(presentation.presentedNotification?.id, identity)
                    XCTAssertNil(presentation.expandedMinorActivity)
                    XCTAssertEqual(presentation.visualState, .collapsed)
                }
            }
            await clock.advance(by: .milliseconds(1749))
            await drainMainActorTasks()
            XCTAssertNotNil(presentation.audioHUD)
            await clock.advance(by: .milliseconds(1))
            for _ in 0..<100 where presentation.audioHUD != nil { await Task.yield() }
            XCTAssertNil(presentation.audioHUD)
            XCTAssertNil(presentation.expandedMinorActivity)
            XCTAssertTrue(presentation.activityCoordinator.liveActivities.isEmpty)
        }
    }

    func testUnsupportedOrChangedOutputDoesNotPresentBoundaryFeedback() {
        let audio = makeAudio(RecordingVolumeService())
        var count = 0
        audio.onHUD = { _ in count += 1 }
        audio.receive(snapshot(0))
        audio.receiveVolumeCommand(.init(command: .down, output: output(nil)))
        audio.receiveVolumeCommand(.init(command: .down, output: output(0, writable: false)))
        audio.receiveVolumeCommand(.init(command: .down, output: output(0, id: "stale")))
        audio.receiveVolumeCommand(.init(command: .up, output: output(0)))
        XCTAssertEqual(count, 0)
    }

    func testCommandStreamIsConsumedAndCancelledWithAudioFeature() async {
        let service = RecordingVolumeService(initial: snapshot(0))
        let audio = makeAudio(service)
        let presented = expectation(description: "Boundary command reaches HUD")
        var count = 0
        audio.onHUD = { hud in
            count += 1
            XCTAssertEqual(hud.volume, 0)
            presented.fulfill()
        }
        audio.start()
        for _ in 0..<100 where audio.devices.currentOutput == nil { await Task.yield() }
        await service.emit(.init(command: .down, output: output(0)))
        await fulfillment(of: [presented], timeout: 2)
        audio.stop()
        await service.emit(.init(command: .down, output: output(0)))
        await drainMainActorTasks()
        XCTAssertEqual(count, 1)
        let writes = await service.writeCount
        XCTAssertEqual(writes, 0)
    }

    func testDuplicateSnapshotsStillDoNotRefreshLifetime() async {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        defer { presentation.reset() }
        let notification = NotchNotification.audio(.init(kind: .volume, deviceName: "Speakers", volume: 0, isMuted: false))
        presentation.notificationCoordinator.present(notification)
        await clock.waitForPendingSleeps()
        let deadline = presentation.notificationCoordinator.expiresAt
        await clock.advance(by: .seconds(1))
        presentation.notificationCoordinator.present(notification)
        await drainMainActorTasks()
        XCTAssertEqual(presentation.notificationCoordinator.expiresAt, deadline)
        presentation.showAudioHUD(.init(kind: .volume, deviceName: "Speakers", volume: 0, isMuted: false))
        await settleDeadline(presentation, at: Date(timeIntervalSince1970: 2.75))
        XCTAssertEqual(presentation.activityCoordinator.activeTransient?.id, notification.id)
    }

    private func settleDeadline(_ presentation: DynamicIslandPresentationModel, at expected: Date) async {
        for _ in 0..<200 where presentation.notificationCoordinator.expiresAt != expected { await Task.yield() }
        XCTAssertEqual(presentation.notificationCoordinator.expiresAt, expected)
    }

    private func makeAudio(_ service: RecordingVolumeService) -> AudioFeatureModel {
        AudioFeatureModel(devices: service, processes: MockAudioProcessesService(), mixer: MockAppAudioMixerService())
    }

    private func output(_ volume: Double?, writable: Bool = true, id: String = "7") -> AudioDevice {
        .init(id: id, name: "Speakers", isDefaultOutput: true, volume: volume,
              isMuted: false, canSetVolume: writable)
    }

    private func snapshot(_ volume: Double) -> AudioDevicesSnapshot {
        .init(availability: .available, outputs: [output(volume)])
    }
}

private actor RecordingVolumeService: AudioDevicesService {
    private let initial: AudioDevicesSnapshot
    private let events = AsyncStream<AudioVolumeCommandEvent>.makeStream()
    private(set) var writeCount = 0

    init(initial: AudioDevicesSnapshot = .init(availability: .available)) { self.initial = initial }
    func availability() async -> FeatureAvailability { .available }
    func updates() async -> AsyncStream<AudioDevicesSnapshot> {
        AsyncStream { $0.yield(initial); $0.finish() }
    }
    func volumeCommands() async -> AsyncStream<AudioVolumeCommandEvent> { events.stream }
    func emit(_ event: AudioVolumeCommandEvent) { events.continuation.yield(event) }
    func selectOutput(id: String) async throws { writeCount += 1 }
    func setVolume(_ volume: Double, deviceID: String) async throws { writeCount += 1 }
    func setMuted(_ muted: Bool, deviceID: String) async throws { writeCount += 1 }
}
