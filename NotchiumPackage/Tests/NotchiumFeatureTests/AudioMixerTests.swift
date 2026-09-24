import CoreAudio
@testable import NotchiumAudioFeature
import NotchiumRealtimeAudio
@testable import NotchiumServices
import XCTest

@MainActor
final class AudioMixerTests: XCTestCase {
    func testPerAppSettingsPersistByBundleAndDriveMixerTarget() async throws {
        let suiteName = "AudioMixerTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let mixer = MockAppAudioMixerService()
        let model = AudioFeatureModel(devices: MockAudioDevicesService(),
                                      processes: MockAudioProcessesService(),
                                      mixer: mixer, preferences: preferences)
        let process = AudioProducingProcess(id: 42, bundleID: "com.example.player",
                                            controllableOutputDeviceIDs: ["7"])
        model.receive(AudioDevicesSnapshot(availability: .available, outputs: [
            AudioDevice(id: "7", name: "Speakers", isDefaultOutput: true)
        ]))
        model.receiveProcesses([process])

        model.setAppVolume(0.42, process: process)
        model.commitAppVolume(process)
        model.toggleAppMute(process)
        for _ in 0..<6 { await Task.yield() }

        XCTAssertEqual(model.appVolume(process), 0.42, accuracy: 0.001)
        XCTAssertTrue(model.isAppMuted(process))
        let targets = await mixer.targets
        XCTAssertEqual(targets, [AppAudioMixTarget(processID: 42,
                                                   bundleID: "com.example.player",
                                                   volume: 0.42, isMuted: true)])
        let saved = try XCTUnwrap(preferences.dictionary(forKey: "audio.appVolumes")?["com.example.player"] as? Double)
        XCTAssertEqual(saved, 0.42, accuracy: 0.001)
        let restored = AudioFeatureModel(devices: MockAudioDevicesService(),
                                         processes: MockAudioProcessesService(),
                                         mixer: MockAppAudioMixerService(), preferences: preferences)
        XCTAssertEqual(restored.appVolume(process), 0.42, accuracy: 0.001)
        XCTAssertTrue(restored.isAppMuted(process))
    }

    func testResetRemovesTargetAndRestoresDirectAudio() async throws {
        let suiteName = "AudioMixerTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let mixer = MockAppAudioMixerService()
        let model = AudioFeatureModel(devices: MockAudioDevicesService(),
                                      processes: MockAudioProcessesService(),
                                      mixer: mixer, preferences: preferences)
        let process = AudioProducingProcess(id: 8, bundleID: "com.example.browser",
                                            controllableOutputDeviceIDs: ["9"])
        model.receive(AudioDevicesSnapshot(availability: .available, outputs: [
            AudioDevice(id: "9", name: "Display", isDefaultOutput: true)
        ]))
        model.receiveProcesses([process])
        model.setAppVolume(0.2, process: process)
        model.commitAppVolume(process)
        for _ in 0..<4 { await Task.yield() }
        let adjustedTargets = await mixer.targets
        XCTAssertFalse(adjustedTargets.isEmpty)

        model.resetAppVolume(process)
        for _ in 0..<4 { await Task.yield() }
        let restoredTargets = await mixer.targets
        XCTAssertTrue(restoredTargets.isEmpty)
        XCTAssertEqual(model.appVolume(process), 1)
        XCTAssertFalse(model.isAppMuted(process))
    }

    func testProcessExitAndOutputChangeReconcileTheTapGraph() async throws {
        let suiteName = "AudioMixerTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let mixer = MockAppAudioMixerService()
        let model = AudioFeatureModel(devices: MockAudioDevicesService(),
                                      processes: MockAudioProcessesService(),
                                      mixer: mixer, preferences: preferences)
        let process = AudioProducingProcess(id: 14, bundleID: "com.example.music",
                                            controllableOutputDeviceIDs: ["20", "21"])
        model.receive(AudioDevicesSnapshot(availability: .available, outputs: [
            AudioDevice(id: "20", name: "Speakers", isDefaultOutput: true)
        ]))
        model.receiveProcesses([process])
        model.setAppVolume(0.6, process: process)
        model.commitAppVolume(process)
        for _ in 0..<4 { await Task.yield() }
        let firstOutput = await mixer.outputDeviceID
        XCTAssertEqual(firstOutput, "20")

        model.receive(AudioDevicesSnapshot(availability: .available, outputs: [
            AudioDevice(id: "21", name: "Headphones", isDefaultOutput: true)
        ]))
        for _ in 0..<4 { await Task.yield() }
        let secondOutput = await mixer.outputDeviceID
        XCTAssertEqual(secondOutput, "21")

        model.receiveProcesses([])
        for _ in 0..<4 { await Task.yield() }
        let remaining = await mixer.targets
        XCTAssertTrue(remaining.isEmpty)
    }

    func testPermissionFailureIsPublishedWithoutLosingSavedGain() async throws {
        let suiteName = "AudioMixerTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let mixer = MockAppAudioMixerService(status: .permissionRequired)
        let model = AudioFeatureModel(devices: MockAudioDevicesService(),
                                      processes: MockAudioProcessesService(),
                                      mixer: mixer, preferences: preferences)
        let process = AudioProducingProcess(id: 15, bundleID: "com.example.video",
                                            controllableOutputDeviceIDs: ["22"])
        model.receive(AudioDevicesSnapshot(availability: .available, outputs: [
            AudioDevice(id: "22", name: "Speakers", isDefaultOutput: true)
        ]))
        model.receiveProcesses([process])
        model.setAppVolume(0.3, process: process)
        model.commitAppVolume(process)
        for _ in 0..<4 { await Task.yield() }
        XCTAssertEqual(model.mixerStatus, .permissionRequired)
        XCTAssertEqual(model.appVolume(process), 0.3, accuracy: 0.001)
    }

    func testRealtimeMixerAppliesAtomicGainWithoutAllocatingScratchBuffers() {
        let slots = UnsafeMutablePointer<NTAudioGainSlot>.allocate(capacity: 1)
        defer { slots.deallocate() }
        NTAudioGainSlotsInitialize(slots, 1)
        NTAudioGainSlotSet(slots, 0.5)

        var input: [Float] = [1, -1, 0.5, -0.5]
        var output: [Float] = [0, 0, 0, 0]
        input.withUnsafeMutableBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                var inputList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(mNumberChannels: 2,
                                          mDataByteSize: UInt32(inputBytes.count),
                                          mData: inputBytes.baseAddress)
                )
                var outputList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(mNumberChannels: 2,
                                          mDataByteSize: UInt32(outputBytes.count),
                                          mData: outputBytes.baseAddress)
                )
                NTAudioMixFloat32(&inputList, &outputList, slots, 1, false, false)
            }
        }
        XCTAssertEqual(output, [0.5, -0.5, 0.25, -0.25])
    }

    func testCompactRowsFitRequiredDensity() {
        XCTAssertGreaterThanOrEqual(AudioPageMetrics.appRowHeight, 52)
        XCTAssertLessThanOrEqual(AudioPageMetrics.appRowHeight, 58)
        XCTAssertEqual(AudioPageMetrics.twoRowViewportHeight, 113)
    }

    func testInternalAudioDevicesAreNotUserVisible() {
        XCTAssertFalse(AudioDeviceVisibility.isUserVisible(
            uid: NotchiumAudioInfrastructure.appMixerDeviceUID
        ))
        XCTAssertFalse(AudioDeviceVisibility.isUserVisible(
            uid: "\(NotchiumAudioInfrastructure.legacyAppMixerDeviceUIDPrefix)A1B2C3"
        ))
        XCTAssertFalse(AudioDeviceVisibility.isUserVisible(
            uid: "\(NotchiumAudioInfrastructure.spotifyTapDeviceUIDPrefix)D4E5F6"
        ))
        XCTAssertTrue(AudioDeviceVisibility.isUserVisible(uid: "BuiltInSpeakerDevice"))
    }

    func testProcessIsControllableOnlyOnVerifiedTapRoutes() {
        let controllable = AudioProducingProcess(
            id: 91,
            bundleID: "com.example.player",
            controllableOutputDeviceIDs: ["7"]
        )
        let unrouted = AudioProducingProcess(
            id: 92,
            bundleID: "com.example.developer-tool",
            controllableOutputDeviceIDs: []
        )

        XCTAssertTrue(controllable.isControllable(on: "7"))
        XCTAssertFalse(controllable.isControllable(on: "8"))
        XCTAssertFalse(unrouted.isControllable(on: "7"))
    }

    func testAppOptionsMenuContainsOnlyResetAndPinActions() {
        XCTAssertEqual(
            AudioAppOptionsButton.itemTitles(isPinned: false),
            ["Reset Volume to 100%", "Pin in Mixer"]
        )
        XCTAssertEqual(
            AudioAppOptionsButton.itemTitles(isPinned: true),
            ["Reset Volume to 100%", "Unpin from Mixer"]
        )
    }
}
