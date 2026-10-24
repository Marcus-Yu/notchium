import NotchiumCore
import XCTest
@testable import NotchiumAudioFeature
@testable import NotchiumDynamicIsland
@testable import NotchiumServices

@MainActor
final class InlineVolumeFeedbackTests: XCTestCase {
    func testDraggingAudioPageVolumeKeepsFeedbackInline() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))

        audio.setVolumeEditing(true)
        audio.changeVolume(0.6)
        try await waitForWrites(1, service: service)
        audio.receive(snapshot(0.6))
        audio.changeVolume(0.7)
        try await waitForWrites(2, service: service)
        audio.receive(snapshot(0.7))
        audio.setVolumeEditing(false)
        audio.changeVolume(0.7, finished: true)
        try await waitForWrites(3, service: service)
        audio.receive(snapshot(0.7))

        XCTAssertTrue(huds.isEmpty, "The existing Audio slider supplies feedback during a drag")
        XCTAssertEqual(audio.devices.currentOutput?.volume, 0.7)
        XCTAssertNil(audio.displayVolume)
        audio.receive(snapshot(0.8))
        XCTAssertEqual(huds.map(\.volume), [0.8], "An independent system change still presents feedback")
    }

    func testConfirmationAfterMouseUpDoesNotOpenVolumeHUD() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))

        audio.setVolumeEditing(true)
        audio.changeVolume(0.8)
        audio.setVolumeEditing(false)
        audio.changeVolume(0.8, finished: true)
        try await waitForWrites(1, service: service)
        audio.receive(snapshot(0.8))

        XCTAssertTrue(huds.isEmpty, "HAL confirmation may arrive after the drag has ended")
        XCTAssertNil(audio.displayVolume)
    }

    func testAccessibleSliderAdjustmentDoesNotRequireDragToSuppressDuplicateHUD() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))

        audio.changeVolume(0.55, finished: true)
        try await waitForWrites(1, service: service)
        audio.receive(snapshot(0.55))

        XCTAssertTrue(huds.isEmpty)
        XCTAssertEqual(audio.devices.currentOutput?.volume, 0.55)
    }

    func testPassiveHardwareKeyDuringPendingInlineWriteStillPresentsAndFollowsHALReadback() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))
        audio.setVolumeEditing(true)
        audio.changeVolume(0.6)
        try await waitForWrites(1, service: service)
        XCTAssertTrue(huds.isEmpty)

        // The command and HAL streams can arrive in either order. A key may be read
        // before native volume application; its next HAL snapshot must remain visible.
        audio.receiveVolumeCommand(.init(command: .down, output: output(0.5)))
        XCTAssertEqual(huds.last?.volume, 0.5)
        audio.receive(snapshot(0.4375))
        XCTAssertEqual(huds.last?.volume, 0.4375)

        audio.changeVolume(0.7)
        try await waitForWrites(2, service: service)
        audio.receive(snapshot(0.7))
        XCTAssertEqual(huds.count, 2, "Resuming the page slider returns feedback to the inline control")
    }

    func testHardwareCommandFollowingHALReadbackDuringDragUsesCurrentValue() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))
        audio.setVolumeEditing(true)
        audio.changeVolume(0.6)
        try await waitForWrites(1, service: service)
        audio.receive(snapshot(0.6))

        audio.receive(snapshot(0.5375))
        audio.receiveVolumeCommand(.init(command: .down, output: output(0.5375)))

        XCTAssertEqual(huds.map(\.volume), [0.5375])
    }

    func testReplacedAndBoundaryHardwareCommandsStillPresentWhileInlineValueIsPending() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))
        audio.changeVolume(0.6)
        try await waitForWrites(1, service: service)
        audio.receiveVolumeCommand(.init(command: .up, output: output(0.6625), wasReplaced: true))
        audio.changeVolume(0)
        try await waitForWrites(2, service: service)
        audio.receiveVolumeCommand(.init(command: .down, output: output(0)))

        XCTAssertEqual(huds.map(\.volume), [0.6625, 0])
    }

    func testInlineMuteDoesNotPresentDuplicateSliderButHardwareMuteStillDoes() {
        let audio = makeAudio(InlineVolumeService())
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))
        audio.toggleMute()
        audio.receive(snapshot(0.5, muted: true))
        XCTAssertTrue(huds.isEmpty)

        audio.toggleMute()
        audio.receiveVolumeCommand(.init(command: .mute, output: output(0.5, muted: false)))
        XCTAssertEqual(huds.last?.isMuted, false)
        audio.receive(snapshot(0.5, muted: false))
        XCTAssertEqual(huds.last?.isMuted, false)
    }

    func testChangingOutputDuringInlineEditStillPresentsDeviceTransition() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))
        audio.changeVolume(0.6)
        try await waitForWrites(1, service: service)

        audio.receive(snapshot(0.3, id: "8"))

        XCTAssertEqual(huds.last?.kind, .outputChanged)
        XCTAssertNil(audio.displayVolume)
        audio.receive(snapshot(0.4, id: "8"))
        XCTAssertEqual(huds.last?.kind, .volume)
        XCTAssertEqual(huds.last?.volume, 0.4)
    }

    func testSameValueInlineWriteWithoutHALEchoDoesNotHideExternalVolume() async throws {
        let service = InlineVolumeService(holdVolumeWrites: true)
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))

        audio.changeVolume(0.5, finished: true)
        try await waitForWrites(1, service: service)
        audio.receive(snapshot(0.7))

        XCTAssertEqual(huds.map(\.volume), [0.7], "No-op writes have no HAL echo to suppress")
        await service.releaseVolumeWrites()
    }

    func testMissingInlineConfirmationDoesNotHideUnrelatedHardwareSnapshot() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))

        audio.changeVolume(0.8, finished: true)
        try await waitForWrites(1, service: service)
        // HAL can report hardware input without a passive key-command event. A different
        // value must present, then discard the unconfirmed local request.
        audio.receive(snapshot(0.4375))
        audio.receive(snapshot(0.8))

        XCTAssertEqual(huds.map(\.volume), [0.4375, 0.8])
    }

    func testCoalescedInlineConfirmationsDoNotLeaveObsoleteSuppression() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))

        audio.setVolumeEditing(true)
        audio.changeVolume(0.6)
        try await waitForWrites(1, service: service)
        audio.changeVolume(0.7)
        try await waitForWrites(2, service: service)
        audio.receive(snapshot(0.7))
        XCTAssertTrue(huds.isEmpty)
        audio.receive(snapshot(0.6))

        XCTAssertEqual(huds.map(\.volume), [0.6], "The latest confirmation consumes earlier coalesced targets")
    }

    func testFailedInlineWriteDoesNotSuppressLaterVolume() async throws {
        let service = InlineVolumeService(failsVolumeWrites: true)
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))
        audio.changeVolume(0.8, finished: true)
        try await waitForWrites(1, service: service)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while audio.errorMessage == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertNotNil(audio.errorMessage)
        audio.receive(snapshot(0.8))
        XCTAssertEqual(huds.map(\.volume), [0.8])
    }

    func testCloselySpacedSequentialConfirmationsKeepBothInline() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))

        audio.setVolumeEditing(true)
        audio.changeVolume(0.60)
        try await waitForWrites(1, service: service)
        audio.changeVolume(0.61)
        try await waitForWrites(2, service: service)
        audio.receive(snapshot(0.60))
        audio.receive(snapshot(0.61))

        XCTAssertTrue(huds.isEmpty, "The first exact echo must not consume the nearby later target")
        audio.receive(snapshot(0.60))
        XCTAssertEqual(huds.map(\.volume), [0.60], "Both confirmed requests leave no stale suppression")
    }

    func testRepeatedFinalWriteNeedsOnlyOneConfirmation() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))

        audio.setVolumeEditing(true)
        audio.changeVolume(0.60)
        try await waitForWrites(1, service: service)
        audio.setVolumeEditing(false)
        audio.changeVolume(0.60, finished: true)
        try await waitForWrites(2, service: service)
        audio.receive(snapshot(0.60))
        XCTAssertTrue(huds.isEmpty)

        // The last drag value and mouse-up commit can write the same scalar twice, but
        // HAL emits only one state change. A nearby hardware value must not match a stale duplicate.
        audio.receive(snapshot(0.61))
        XCTAssertEqual(huds.map(\.volume), [0.61])
    }

    func testEquidistantQuantizedConfirmationPreservesLaterTarget() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))

        audio.setVolumeEditing(true)
        audio.changeVolume(0.60)
        try await waitForWrites(1, service: service)
        audio.changeVolume(0.61)
        try await waitForWrites(2, service: service)
        audio.receive(snapshot(0.605))
        audio.receive(snapshot(0.61))

        XCTAssertTrue(huds.isEmpty, "Equidistant quantization acknowledges the earlier submitted value")
        audio.receive(snapshot(0.60))
        XCTAssertEqual(huds.map(\.volume), [0.60])
    }

    func testNearestQuantizedConfirmationConsumesCoalescedEarlierTargets() async throws {
        let service = InlineVolumeService()
        let audio = makeAudio(service)
        defer { audio.stop() }
        var huds: [NotchAudioHUD] = []
        audio.onHUD = { huds.append($0) }
        audio.receive(snapshot(0.5))

        audio.setVolumeEditing(true)
        audio.changeVolume(0.60)
        try await waitForWrites(1, service: service)
        audio.changeVolume(0.65)
        try await waitForWrites(2, service: service)
        audio.receive(snapshot(0.649))
        XCTAssertTrue(huds.isEmpty)
        audio.receive(snapshot(0.60))

        XCTAssertEqual(huds.map(\.volume), [0.60])
    }

    private func makeAudio(_ service: InlineVolumeService) -> AudioFeatureModel {
        AudioFeatureModel(devices: service, processes: MockAudioProcessesService(),
                          mixer: MockAppAudioMixerService())
    }

    private func waitForWrites(_ count: Int, service: InlineVolumeService) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await service.volumeWriteCount < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        let actual = await service.volumeWriteCount
        XCTAssertEqual(actual, count, "Wait for the actual service command before simulating its HAL echo")
    }

    private func snapshot(_ volume: Double, muted: Bool = false, id: String = "7") -> AudioDevicesSnapshot {
        .init(availability: .available, outputs: [output(volume, muted: muted, id: id)])
    }

    private func output(_ volume: Double, muted: Bool = false, id: String = "7") -> AudioDevice {
        .init(id: id, name: id == "7" ? "Speakers" : "Headphones", isDefaultOutput: true,
              volume: volume, isMuted: muted, canSetVolume: true, canSetMute: true)
    }
}

private actor InlineVolumeService: AudioDevicesService {
    private var holdVolumeWrites: Bool
    private let failsVolumeWrites: Bool
    private var pendingWrites: [CheckedContinuation<Void, Never>] = []
    private(set) var volumeWriteCount = 0

    init(holdVolumeWrites: Bool = false, failsVolumeWrites: Bool = false) {
        self.holdVolumeWrites = holdVolumeWrites
        self.failsVolumeWrites = failsVolumeWrites
    }

    func availability() async -> FeatureAvailability { .available }
    func updates() async -> AsyncStream<AudioDevicesSnapshot> { AsyncStream { $0.finish() } }
    func selectOutput(id: String) async throws {}
    func setMuted(_ muted: Bool, deviceID: String) async throws {}
    func setVolume(_ volume: Double, deviceID: String) async throws {
        volumeWriteCount += 1
        if holdVolumeWrites {
            await withCheckedContinuation { pendingWrites.append($0) }
        }
        if failsVolumeWrites { throw ServiceFailure.unavailable(.audioDevices) }
    }
    func releaseVolumeWrites() {
        holdVolumeWrites = false
        let writes = pendingWrites
        pendingWrites = []
        writes.forEach { $0.resume() }
    }
}
