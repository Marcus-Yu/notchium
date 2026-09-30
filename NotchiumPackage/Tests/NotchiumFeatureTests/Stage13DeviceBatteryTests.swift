import Foundation
import NotchiumCore
import SwiftUI
import XCTest
@testable import NotchiumAudioFeature
@testable import NotchiumDynamicIsland
@testable import NotchiumFeature
@testable import NotchiumServices

/// Stage 13: normalized device state and Mac battery severity, presented through the
/// Stage 12 ActivityCoordinator (one route identity, one battery identity).
@MainActor
final class Stage13DeviceBatteryTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let musicID = UUID()
    private let outputKey = NotchActivityKey("audio.output")

    private func clock() -> TestAppClock { TestAppClock(now: base, automaticallyAdvances: false) }
    private func drain() async { for _ in 0..<200 { await Task.yield() } }
    private func settle(_ clock: TestAppClock) async {
        await drain()
        await clock.waitForPendingSleeps()
    }

    // MARK: Fixtures

    private let speakers = AudioDevice(id: "10", uid: "BuiltInSpeakerDevice", name: "MacBook Air Speakers",
                                       isDefaultOutput: true, volume: 0.5, transport: .builtIn)
    private func airPods(default isDefault: Bool = true, objectID: String = "40",
                         battery: DeviceBatteryStatus = .unsupported) -> AudioDevice {
        AudioDevice(id: objectID, uid: "AA-BB-CC:output", name: "Marcus’s AirPods Pro",
                    isDefaultOutput: isDefault, volume: 0.4, transport: .bluetooth, battery: battery)
    }
    private func usb(default isDefault: Bool = true) -> AudioDevice {
        AudioDevice(id: "55", uid: "USB-DAC", name: "USB Audio DAC", isDefaultOutput: isDefault, transport: .usb)
    }
    private func speakers(default isDefault: Bool) -> AudioDevice {
        AudioDevice(id: speakers.id, uid: speakers.uid, name: speakers.name, isDefaultOutput: isDefault,
                    volume: 0.5, transport: .builtIn)
    }
    private func snapshot(_ outputs: AudioDevice...) -> AudioDevicesSnapshot {
        .init(availability: .available, outputs: outputs)
    }

    private func music() -> NotchActivity {
        NotchActivity(id: musicID, key: .media, kind: .media, title: "Media", subtitle: nil,
                      priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
                      isDismissible: false, destination: .music, duration: nil,
                      payload: .mediaPlayback(isPlaying: true), minimal: .artwork)
    }

    /// The production wiring: AudioFeatureModel.onHUD → presentation.showAudioHUD.
    private func wired(_ clock: TestAppClock, now: Date? = nil) -> (DynamicIslandPresentationModel, AudioFeatureModel) {
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let audio = AudioFeatureModel(devices: MockAudioDevicesService(), processes: MockAudioProcessesService(),
                                      mixer: MockAppAudioMixerService(), now: { [base] in now ?? base })
        audio.onHUD = { [weak presentation] in presentation?.showAudioHUD($0) }
        audio.receive(snapshot(speakers))
        return (presentation, audio)
    }

    private func compact(_ presentation: DynamicIslandPresentationModel) -> NotchCompactActivity? {
        presentation.notificationCoordinator.active?.content.compactActivity
    }

    // MARK: AirPods connection

    func testAirPodsConnectionTakesNotchMusicHiddenUnderneathThenReturns() async {
        let clock = clock()
        let (presentation, audio) = wired(clock)
        defer { presentation.reset() }
        presentation.mediaRenderer = VisibleMedia()
        presentation.activityCoordinator.present(music())

        // macOS reports the device first, then makes it the default: one activity, not two.
        audio.receive(snapshot(speakers, airPods(default: false)))
        let id = presentation.notificationCoordinator.active?.id
        audio.receive(snapshot(speakers(default: false), airPods()))
        XCTAssertEqual(presentation.notificationCoordinator.active?.id, id)
        XCTAssertEqual(presentation.activityCoordinator.liveActivities.count, 2)
        XCTAssertEqual(compact(presentation)?.glyph, .device(.airPodsPro))
        XCTAssertEqual(compact(presentation)?.trailing, .text("Connected"))
        XCTAssertFalse(compact(presentation)?.showsTitle ?? true, "No device name beside the glyph")
        XCTAssertEqual(presentation.activityCoordinator.persistentActivity?.id, musicID, "Music stays alive")
        XCTAssertNil(presentation.presentedSecondary, "No Music artwork beside a device transient")

        await settle(clock)
        await clock.advance(by: .milliseconds(2500))
        await waitUntil { presentation.activityCoordinator.primary?.id == self.musicID }
        XCTAssertTrue(presentation.showsCollapsedMedia)
        XCTAssertNil(presentation.notificationCoordinator.active)
    }

    func testLaunchWithDeviceAlreadyConnectedIsNotAnnounced() {
        let presentation = DynamicIslandPresentationModel(clock: clock())
        let audio = AudioFeatureModel(devices: MockAudioDevicesService(), processes: MockAudioProcessesService(),
                                      mixer: MockAppAudioMixerService())
        audio.onHUD = { presentation.showAudioHUD($0) }
        audio.receive(snapshot(speakers(default: false), airPods()))
        XCTAssertNil(presentation.notificationCoordinator.active)
        XCTAssertEqual(audio.currentOutputState?.category, .airPodsPro)
        presentation.reset()
    }

    // MARK: Disconnect / reconnect / output change

    func testActiveDeviceDisconnectAnnouncesTheDeviceNotTheFallback() {
        let (presentation, audio) = wired(clock())
        defer { presentation.reset() }
        audio.receive(snapshot(speakers(default: false), airPods()))
        audio.receive(snapshot(speakers(default: true)))
        XCTAssertEqual(compact(presentation)?.glyph, .device(.airPodsPro, connected: false))
        XCTAssertEqual(compact(presentation)?.trailing, .text("Disconnected"))
        XCTAssertEqual(compact(presentation)?.tint, .muted)
        XCTAssertEqual(presentation.activityCoordinator.liveActivities.map(\.key), [outputKey],
                       "The stale Connected state is replaced, not stacked")
        XCTAssertEqual(audio.currentOutputState?.id, speakers.uid, "The current output is the fallback")
    }

    func testRapidConnectDisconnectReconnectKeepsOneActivityAndNewestStateWins() {
        let (presentation, audio) = wired(clock())
        defer { presentation.reset() }
        audio.receive(snapshot(speakers(default: false), airPods()))
        let id = presentation.notificationCoordinator.active?.id
        audio.receive(snapshot(speakers(default: true)))
        // Reconnect with a new Core Audio object ID: the stable UID is the same device.
        audio.receive(snapshot(speakers(default: false), airPods(objectID: "41")))
        XCTAssertEqual(presentation.activityCoordinator.liveActivities.map(\.key), [outputKey])
        XCTAssertEqual(presentation.notificationCoordinator.active?.id, id, "Updated in place, no pile-up")
        XCTAssertEqual(compact(presentation)?.glyph, .device(.airPodsPro, connected: true))
        XCTAssertEqual(compact(presentation)?.trailing, .text("Connected"))
        XCTAssertEqual(audio.currentOutputState?.objectID, "41")
    }

    func testRapidOutputSwitchesCoalesceToTheFinalOutput() {
        let (presentation, audio) = wired(clock())
        defer { presentation.reset() }
        audio.receive(snapshot(speakers(default: false), usb()))
        audio.receive(snapshot(speakers(default: true), usb(default: false)))
        audio.receive(snapshot(speakers(default: false), usb(default: true)))
        audio.receive(snapshot(speakers(default: true), usb(default: false)))
        XCTAssertEqual(presentation.activityCoordinator.liveActivities.map(\.key), [outputKey])
        XCTAssertEqual(compact(presentation)?.glyph, .device(.builtIn), "Laptop glyph, no name")
        XCTAssertEqual(compact(presentation)?.trailing, .text("Connected"))
    }

    func testNonWearableDeviceAppearingWithoutTakingTheRouteIsQuiet() {
        let (presentation, audio) = wired(clock())
        defer { presentation.reset() }
        audio.receive(snapshot(speakers, usb(default: false)))
        XCTAssertNil(presentation.notificationCoordinator.active)
        audio.receive(snapshot(speakers))
        XCTAssertNil(presentation.notificationCoordinator.active)
    }

    func testDeviceTransitionTimerCannotDismissANewerTransition() async {
        let clock = clock()
        let (presentation, audio) = wired(clock)
        defer { presentation.reset() }
        audio.receive(snapshot(speakers(default: false), airPods()))
        await settle(clock)
        await clock.advance(by: .milliseconds(2000))
        audio.receive(snapshot(speakers(default: true)))
        await settle(clock)
        await clock.advance(by: .milliseconds(600))
        await drain()
        XCTAssertEqual(compact(presentation)?.trailing, .text("Disconnected"))
        await clock.advance(by: .milliseconds(1900))
        await waitUntil { presentation.notificationCoordinator.active == nil }
        XCTAssertNil(presentation.notificationCoordinator.active)
    }

    // MARK: Device battery availability

    func testUnsupportedDeviceBatteryIsNeverInvented() {
        let (presentation, audio) = wired(clock())
        defer { presentation.reset() }
        audio.receive(snapshot(speakers(default: false), airPods(battery: .unsupported)))
        XCTAssertEqual(compact(presentation)?.trailing, .text("Connected"))
        XCTAssertNil(audio.currentOutputState?.aggregateBattery)
        audio.receive(snapshot(speakers(default: true), airPods(default: false, battery: .unavailable)))
        XCTAssertEqual(audio.state(for: airPods(default: false))?.battery, .unavailable)
    }

    func testFreshReportedBatteryIsShownAndStaleOrDepartedBatteryIsNot() {
        let fresh = DeviceBatteryLevels(left: 0.8, right: 0.7, caseLevel: 0.4, isCharging: false, measuredAt: base)
        let (presentation, audio) = wired(clock())
        defer { presentation.reset() }
        audio.receive(snapshot(speakers(default: false), airPods(battery: .available(fresh))))
        XCTAssertEqual(compact(presentation)?.trailing, .battery(level: 0.7, charging: false),
                       "Aggregate is the lower bud; the case never stands in")
        XCTAssertEqual(DeviceBatteryDetail.components(fresh).map(\.label), ["L", "R", "Case"])

        // Disconnect: the departed device's reading is not carried over.
        audio.receive(snapshot(speakers(default: true)))
        XCTAssertEqual(compact(presentation)?.trailing, .text("Disconnected"))
        XCTAssertNil(audio.outputStates.first { $0.id == "AA-BB-CC:output" })
        // Reconnect without a new reading: nothing old is shown as new.
        audio.receive(snapshot(speakers(default: false), airPods(battery: .unavailable)))
        XCTAssertEqual(compact(presentation)?.trailing, .text("Connected"))

        let stale = DeviceBatteryLevels(single: 0.9, measuredAt: base.addingTimeInterval(-600))
        let state = OutputDeviceState(airPods(battery: .available(stale)), now: base)
        XCTAssertEqual(state.battery, .unavailable, "A 10-minute-old reading is not live")
        let partial = DeviceBatteryLevels(caseLevel: 0.5, measuredAt: base)
        XCTAssertNil(OutputDeviceState(airPods(battery: .available(partial)), now: base).aggregateBattery,
                     "Case-only data is not presented as bud battery")
    }

    func testCategoriesKeepAirPodsVisualsForAirPodsOnly() {
        XCTAssertEqual(OutputDeviceState(airPods(), now: base).category, .airPodsPro)
        XCTAssertEqual(OutputDeviceState(usb(), now: base).category, .speaker)
        XCTAssertEqual(OutputDeviceState(speakers, now: base).category, .builtIn)
        let sony = AudioDevice(id: "9", uid: "sony", name: "WH-1000XM5", isDefaultOutput: true, transport: .bluetooth)
        XCTAssertEqual(OutputDeviceState(sony, now: base).category, .headphones)
        XCTAssertEqual(NotchCompactActivity(NotchAudioHUD(kind: .deviceDisconnected, deviceName: "WH-1000XM5",
            volume: nil, isMuted: false, deviceStyle: .headphones)).sideWidth, NotchCompactGeometry.sideWidth,
            "“Disconnected” gets full side width instead of truncating")
    }

    // MARK: Mac battery

    private func battery(_ level: Double, power: Bool = false) -> BatterySnapshot {
        .init(availability: .available, chargeLevel: level, isCharging: power, isConnectedToPower: power)
    }

    func testChargerConnectShowsChargingActivityAndExpires() async {
        var policy = BatteryActivityPolicy()
        XCTAssertNil(policy.receive(battery(0.37)))
        XCTAssertEqual(policy.receive(battery(0.37, power: true)), .charging(level: 0.37))
        XCTAssertNil(policy.receive(battery(0.38, power: true)), "Percentage updates are not events")

        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        activities.notifications.present(.charging(level: 0.37))
        let compact = activities.notifications.active?.content.compactActivity
        XCTAssertEqual(compact?.title, "Charging")
        XCTAssertEqual(compact?.trailing, .battery(level: 0.37, charging: true))
        await settle(clock)
        await clock.advance(by: .milliseconds(2500))
        await waitUntil { activities.primary == nil }
        XCTAssertNil(activities.primary)
    }

    func testRapidChargerPlugUnplugUpdatesOneBatteryActivity() {
        var policy = BatteryActivityPolicy()
        _ = policy.receive(battery(0.5))
        let activities = ActivityCoordinator(clock: clock())
        defer { activities.clearAll() }
        for power in [true, false, true, false] {
            switch policy.receive(battery(0.5, power: power)) {
            case let .charging(level): activities.notifications.present(.charging(level: level))
            case let .powerDisconnected(level): activities.notifications.present(.powerDisconnected(level: level))
            default: XCTFail("each plug change is one event")
            }
        }
        XCTAssertEqual(activities.liveActivities.map(\.key), [NotchActivityKey("battery")])
        XCTAssertEqual(activities.notifications.active?.kind, .powerDisconnected)
    }

    func testLowThresholdWarnsOnceAndFluctuationDoesNotNag() {
        var policy = BatteryActivityPolicy()
        XCTAssertNil(policy.receive(battery(0.30)))
        XCTAssertNil(policy.receive(battery(0.21)))
        XCTAssertEqual(policy.receive(battery(0.20)), .low(level: 0.20))
        for level in [0.21, 0.20, 0.22, 0.19, 0.21, 0.18] {
            XCTAssertNil(policy.receive(battery(level)), "fluctuation at \(level)")
        }
    }

    func testCriticalThresholdHasHigherPriorityThanLowAndUrgentCalendar() {
        var policy = BatteryActivityPolicy()
        _ = policy.receive(battery(0.15))
        XCTAssertEqual(policy.receive(battery(0.10)), .critical(level: 0.10))
        XCTAssertNil(policy.receive(battery(0.09)))
        XCTAssertNil(policy.receive(battery(0.11)))
        XCTAssertNil(policy.receive(battery(0.10)))

        XCTAssertEqual(ActivityPriorityPolicy.priority(for: .criticalBattery), .critical)
        XCTAssertGreaterThan(ActivityPriorityPolicy.priority(for: .criticalBattery),
                             ActivityPriorityPolicy.priority(for: .reminder5))
        XCTAssertGreaterThan(ActivityPriorityPolicy.priority(for: .lowBattery),
                             ActivityPriorityPolicy.priority(for: .outputDeviceChanged))

        let activities = ActivityCoordinator(clock: clock())
        defer { activities.clearAll() }
        activities.notifications.present(.init(kind: .reminder5, coalescingKey: "calendar.x", action: .calendar,
            presentationStyle: .calendar, content: .calendar(title: "Standup", status: "5 min")))
        activities.notifications.present(.lowBattery(level: 0.19))
        let id = activities.notifications.active?.id
        XCTAssertTrue(activities.notifications.present(.criticalBattery(level: 0.09)))
        XCTAssertEqual(activities.notifications.active?.id, id, "One Mac battery identity changes severity")
        XCTAssertEqual(activities.primary?.priority, .critical)
        XCTAssertFalse(activities.notifications.present(.init(kind: .reminder5, coalescingKey: "calendar.y",
            action: .calendar, presentationStyle: .calendar, content: .calendar(title: "Sync", status: "5 min"))))
    }

    func testRecoveryRearmsThresholdsForALaterCrossing() {
        var policy = BatteryActivityPolicy()
        _ = policy.receive(battery(0.30))
        XCTAssertEqual(policy.receive(battery(0.20)), .low(level: 0.20))
        XCTAssertNil(policy.receive(battery(0.24)), "below the re-arm margin")
        XCTAssertNil(policy.receive(battery(0.20)))
        XCTAssertNil(policy.receive(battery(0.25)))
        XCTAssertEqual(policy.receive(battery(0.20)), .low(level: 0.20), "meaningful recovery re-arms")

        XCTAssertEqual(policy.receive(battery(0.10)), .critical(level: 0.10))
        XCTAssertEqual(policy.receive(battery(0.10, power: true)), .charging(level: 0.10))
        XCTAssertNil(policy.receive(battery(0.60, power: true)))
        XCTAssertEqual(policy.receive(battery(0.60)), .powerDisconnected(level: 0.60))
        XCTAssertEqual(policy.receive(battery(0.20)), .low(level: 0.20), "recharging re-arms")
    }

    func testLaunchAndUnplugBelowThresholdAreNotCrossings() {
        var policy = BatteryActivityPolicy()
        XCTAssertNil(policy.receive(battery(0.08)), "launch state is known")
        XCTAssertNil(policy.receive(battery(0.07)))
        var unplugged = BatteryActivityPolicy()
        _ = unplugged.receive(battery(0.15, power: true))
        XCTAssertEqual(unplugged.receive(battery(0.15)), .powerDisconnected(level: 0.15))
        XCTAssertNil(unplugged.receive(battery(0.14)))
        XCTAssertEqual(unplugged.receive(battery(0.10)), .critical(level: 0.10), "a new crossing still warns")
        var desktop = BatteryActivityPolicy()
        XCTAssertNil(desktop.receive(.init(availability: .unavailable(.unsupportedHardware))))
    }

    // MARK: Stage 12 integration

    func testBatteryTransientRestoresMusicWithoutSecondaryArtwork() async {
        let clock = clock()
        let presentation = DynamicIslandPresentationModel(clock: clock)
        presentation.mediaRenderer = VisibleMedia()
        defer { presentation.reset() }
        presentation.activityCoordinator.present(music())
        for notification in [NotchNotification.criticalBattery(level: 0.08), .lowBattery(level: 0.19),
                             .powerDisconnected(level: 0.5)] {
            presentation.notificationCoordinator.present(notification)
            XCTAssertNil(presentation.presentedSecondary)
            XCTAssertTrue(presentation.activityCoordinator.contains(id: musicID))
            presentation.notificationCoordinator.dismiss()
        }
        presentation.notificationCoordinator.present(.criticalBattery(level: 0.08))
        await settle(clock)
        await clock.advance(by: .seconds(6))
        await waitUntil { presentation.activityCoordinator.primary?.id == self.musicID }
        XCTAssertTrue(presentation.showsCollapsedMedia)
    }

    func testDeviceAndBatteryEventsNeverChangeTheManualPage() async {
        for page in NotchPage.allCases {
            let clock = clock()
            let (presentation, audio) = wired(clock)
            presentation.present(.expanded, animated: false)
            presentation.pageModel.selectedPage = page
            var selections: [NotchPage] = []
            let observation = presentation.pageModel.$selectedPage.dropFirst().sink { selections.append($0) }
            audio.receive(snapshot(speakers(default: false), airPods()))
            audio.receive(snapshot(speakers(default: true)))
            presentation.notificationCoordinator.present(.charging(level: 0.4))
            presentation.notificationCoordinator.present(.criticalBattery(level: 0.05))
            await settle(clock)
            await clock.advance(by: .seconds(10))
            await drain()
            XCTAssertEqual(presentation.pageModel.selectedPage, page)
            XCTAssertTrue(selections.isEmpty, "\(page): \(selections)")
            observation.cancel()
            presentation.reset()
        }
    }
}

@MainActor private final class VisibleMedia: NotchMediaRendering {
    var collapsedMediaVisible: Bool { true }
    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView { AnyView(Color.clear) }
    func expandedMedia() -> AnyView { AnyView(Color.clear) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(Color.clear) }
}
