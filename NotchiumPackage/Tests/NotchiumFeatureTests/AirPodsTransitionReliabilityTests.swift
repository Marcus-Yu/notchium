import Foundation
import Synchronization
import XCTest
import NotchiumServices
import NotchiumDynamicIsland
@testable import NotchiumAudioFeature

@MainActor
final class AirPodsTransitionReliabilityTests: XCTestCase {
    func testManualSelectionJustAfterAppearanceIsASeparateConfirmedTransition() throws {
        let model = AudioFeatureModel(devices: MockAudioDevicesService(), processes: MockAudioProcessesService(),
                                     mixer: MockAppAudioMixerService(), now: { Date(timeIntervalSince1970: 10) })
        var feedback: [NotchAudioHUD] = []
        model.onHUD = { feedback.append($0) }
        model.receive(snapshot(pods: false, selected: false))
        model.receive(snapshot(pods: true, selected: false))
        model.select(try XCTUnwrap(model.devices.outputs.last))
        XCTAssertEqual(feedback.count, 1, "A selection request alone must not pretend to succeed")
        model.receive(snapshot(pods: true, selected: true))
        model.receive(snapshot(pods: true, selected: true))
        XCTAssertEqual(feedback.map(\.transitionRevision), [1, 2])
        XCTAssertEqual(feedback.map(\.deviceID), ["pods-uid", "pods-uid"])
    }

    func testSystemRouteSwitchesBetweenAvailableAirPodsReachTheSameBannerWithNewMotion() throws {
        let model = AudioFeatureModel(devices: MockAudioDevicesService(), processes: MockAudioProcessesService(),
                                     mixer: MockAppAudioMixerService())
        let presentation = DynamicIslandPresentationModel()
        defer { presentation.activityCoordinator.clearAll() }
        model.onHUD = { presentation.showAudioHUD($0) }
        func outputs(_ active: String) -> AudioDevicesSnapshot {
            .init(availability: .available, outputs: ["speaker", "pods-a", "pods-b"].map { id in
                AudioDevice(id: id, uid: id, name: id == "speaker" ? "Speakers" : "AirPods Pro",
                            isDefaultOutput: active == id, transport: id == "speaker" ? .builtIn : .bluetooth)
            })
        }
        model.receive(outputs("speaker"))
        var bannerID: UUID?
        for (index, id) in ["pods-a", "pods-b", "speaker", "pods-a"].enumerated() {
            model.receive(outputs(id))
            let banner = try XCTUnwrap(presentation.presentedNotification)
            if let bannerID { XCTAssertEqual(banner.id, bannerID, "Keep a single coalesced banner") }
            else { bannerID = banner.id }
            let activity = try XCTUnwrap(banner.content.compactActivity)
            XCTAssertEqual(activity.deviceID, id)
            XCTAssertEqual(activity.transitionRevision, UInt64(index + 1))
            model.receive(outputs(id))
            XCTAssertEqual(presentation.presentedNotification?.content.compactActivity?.transitionRevision,
                           activity.transitionRevision, "Unchanged snapshots must not replay motion")
        }
    }

    func testAppearanceThenRouteSelectionAnnouncesOneLogicalConnection() {
        let model = AudioFeatureModel(devices: MockAudioDevicesService(), processes: MockAudioProcessesService(),
                                     mixer: MockAppAudioMixerService(), now: { Date(timeIntervalSince1970: 10) })
        var feedback: [NotchAudioHUD] = []
        model.onHUD = { feedback.append($0) }
        model.receive(snapshot(pods: false, selected: false))
        model.receive(snapshot(pods: true, selected: false))
        model.receive(snapshot(pods: true, selected: true))
        model.receive(snapshot(pods: true, selected: true))
        XCTAssertEqual(feedback.count, 1)
        XCTAssertEqual(feedback.first?.deviceID, "pods-uid")
        XCTAssertEqual(model.currentOutputState?.id, "pods-uid")
    }

    func testDisconnectClearsDeduplicationSoRapidReconnectionStillAnnounces() {
        let model = AudioFeatureModel(devices: MockAudioDevicesService(), processes: MockAudioProcessesService(),
                                     mixer: MockAppAudioMixerService(), now: { Date(timeIntervalSince1970: 10) })
        var feedback: [NotchAudioHUD] = []
        model.onHUD = { feedback.append($0) }
        model.receive(snapshot(pods: false, selected: false))
        model.receive(snapshot(pods: true, selected: false))
        model.receive(snapshot(pods: false, selected: false))
        model.receive(snapshot(pods: true, selected: false))
        model.receive(snapshot(pods: true, selected: true))
        XCTAssertEqual(feedback.map(\.kind), [.outputChanged, .deviceDisconnected, .outputChanged])
    }

    func testLaterRouteSelectionStillAnnouncesAndObjectIDChangesDoNotReconnect() {
        let now = Mutex(Date(timeIntervalSince1970: 10))
        let model = AudioFeatureModel(devices: MockAudioDevicesService(), processes: MockAudioProcessesService(),
                                     mixer: MockAppAudioMixerService(), now: { now.withLock { $0 } })
        var feedback: [NotchAudioHUD] = []
        model.onHUD = { feedback.append($0) }
        model.receive(snapshot(pods: false, selected: false))
        model.receive(snapshot(pods: true, selected: false))
        now.withLock { $0 = $0.addingTimeInterval(3) }
        model.receive(snapshot(pods: true, selected: true))
        model.receive(snapshot(pods: true, selected: true, objectID: "3"))
        XCTAssertEqual(feedback.count, 2, "A later route choice is distinct, but a new HAL object ID is not")
    }

    private func snapshot(pods: Bool, selected: Bool, objectID: String = "2") -> AudioDevicesSnapshot {
        var outputs = [AudioDevice(id: "1", uid: "speaker", name: "Speakers", isDefaultOutput: !selected,
                                   volume: 0.5, transport: .builtIn)]
        if pods { outputs.append(AudioDevice(id: objectID, uid: "pods-uid", name: "AirPods Pro",
            isDefaultOutput: selected, volume: 0.5, transport: .bluetooth)) }
        return .init(availability: .available, outputs: outputs)
    }
}
