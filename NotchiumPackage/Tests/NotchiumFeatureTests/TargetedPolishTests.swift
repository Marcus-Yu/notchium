import AppKit
import SwiftUI
import XCTest
import NotchiumCore
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature
@testable import NotchiumServices
@testable import NotchiumShelfFeature

@MainActor
final class TargetedPolishTests: XCTestCase {
    private func presentation() -> DynamicIslandPresentationModel {
        .init(clock: TestAppClock(now: Date(), automaticallyAdvances: false))
    }

    private func files(_ model: DynamicIslandPresentationModel, service: any ShelfService) -> FilesFeatureModel {
        .init(transfers: MockFileTransferService(), screenshots: MockScreenshotService(), shelf: service,
              actions: NativeFileActions(), activities: model.activityCoordinator)
    }

    func testShelfInsertionConsumesOnlyAcceptedScreenshotRepresentations() {
        let model = presentation()
        defer { model.reset() }
        let accepted = URL(fileURLWithPath: "/test/accepted.png")
        let rejected = URL(fileURLWithPath: "/test/rejected.png")
        let service = MockShelfService(existingPaths: [accepted.path])
        let files = files(model, service: service)
        files.screenshots.receive(.captured(.init(fileURL: accepted, createdAt: Date())))
        files.screenshots.receive(.captured(.init(fileURL: rejected, createdAt: Date())))
        files.addToShelf([accepted, rejected])
        XCTAssertEqual(files.shelf.items.map(\.url), [accepted])
        XCTAssertEqual(files.screenshots.recent.map(\.fileURL), [rejected])
        XCTAssertEqual(model.presentedNotification?.content.compactActivity?.glyph, .thumbnail(rejected))
        XCTAssertTrue(service.existingPaths.contains(accepted.path))
        service.existingPaths.insert(rejected.path)
        files.addToShelf([rejected])
        XCTAssertTrue(files.screenshots.recent.isEmpty)
        XCTAssertFalse(model.activityCoordinator.liveActivities.contains { $0.kind == .screenshot })
        XCTAssertTrue(service.existingPaths.contains(rejected.path))
    }

    func testBookmarkFailureRetainsActivityAndOriginalFile() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = presentation()
        defer { model.reset() }
        let files = files(model, service: RejectingShelf())
        files.screenshots.receive(.captured(.init(fileURL: url, createdAt: Date())))
        files.addToShelf([url])
        XCTAssertTrue(files.shelf.items.isEmpty)
        XCTAssertEqual(files.screenshots.recent.count, 1)
        XCTAssertEqual(model.activityCoordinator.primary?.kind, .screenshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        files.stop()
    }

    func testCompletedDownloadHandOffRemovesUIAndKeepsOriginal() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = presentation()
        defer { model.reset() }
        let files = files(model, service: RealShelfService(defaults: UserDefaults(suiteName: "polish.\(UUID())")!))
        files.transfers.receive(.init(id: "finished", displayName: url.lastPathComponent, operation: .downloading,
                                     phase: .completed, fraction: 1, fileURL: url, startedAt: Date(), updatedAt: Date()))
        files.addToShelf([url])
        XCTAssertEqual(files.shelf.items.map(\.url), [url])
        XCTAssertTrue(files.transfers.recent.isEmpty)
        XCTAssertTrue(files.transfers.finishedFiles.isEmpty)
        XCTAssertNil(model.activityCoordinator.primary)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        files.shelf.clear()
    }

    func testNativeSharingLeasesComposeWithDragLayerAndRestoreLevel() {
        let model = presentation()
        defer { model.reset() }
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.applyNotchWindowBehavior()
        panel.setAcceptsFileDrags(true)
        XCTAssertEqual(panel.level, NotchPanel.fileDragLevel)
        let interaction = model.auxiliaryInteractionHandler
        interaction.beginNativeSharing(in: panel, source: "share")
        interaction.beginNativeSharing(in: panel, source: "airdrop")
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(model.isAuxiliaryInteractionPresented)
        interaction.endNativeSharing(in: panel, source: "share")
        XCTAssertTrue(model.isAuxiliaryInteractionPresented)
        XCTAssertEqual(panel.level, .floating)
        interaction.endNativeSharing(in: panel, source: "airdrop")
        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
        XCTAssertEqual(panel.level, NotchPanel.fileDragLevel)
        panel.setAcceptsFileDrags(false)
        XCTAssertEqual(panel.level, NotchPanel.restingLevel)
    }

    func testAirDropDelegateCompletionAndCancellationReleaseLease() {
        let model = presentation()
        defer { model.reset() }
        // The production delegate's terminal callbacks are idempotent. The native presentation
        // and recipient UI itself still require a real session on macOS.
        let sharing = NativeFileSharing()
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        var session = sharing.begin(window: nil, interaction: model.auxiliaryInteractionHandler, service: service)
        XCTAssertTrue(model.isAuxiliaryInteractionPresented)
        session.sharingService(service, didFailToShareItems: [], error: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
        session = sharing.begin(window: nil, interaction: model.auxiliaryInteractionHandler, service: service)
        session.sharingService(service, didShareItems: [])
        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
        session = sharing.begin(window: nil, interaction: model.auxiliaryInteractionHandler, service: service)
        session.sharingServicePicker(NSSharingServicePicker(items: []), didChoose: nil)
        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
    }

    func testCalendarIndicatorsUseSameDownloadIdentityAndSharedShell() {
        let model = presentation()
        defer { model.reset() }
        let music = musicActivity()
        model.activityCoordinator.present(music)
        let download = TransferActivityModel(notifications: model.notificationCoordinator)
        download.receive(.init(id: "download", displayName: "File", operation: .downloading, phase: .active,
                               fraction: 0.4, startedAt: Date(), updatedAt: Date()))
        let identity = model.activityCoordinator.primary?.id
        let calendar = NotchNotification(kind: .reminder5, coalescingKey: "calendar.test", action: .calendar,
                                         presentationStyle: .calendar, content: .calendar(title: "Meeting", status: "Now"))
        model.notificationCoordinator.present(calendar)
        XCTAssertEqual(model.presentedIndicators.map(\.kind), [.download, .media])
        XCTAssertEqual(model.presentedIndicators.first?.id, identity)
        let layout = NotchGeometryResolver.layout(for: .init(display: NotchShellDebugModel.builtInFixture,
                                                             mode: .physicalNotch), state: .collapsed)
        let left = NotchSecondaryGeometry.frame(layout: layout, beside: calendar, kind: .download)
        let right = NotchSecondaryGeometry.frame(layout: layout, beside: calendar, kind: .media)
        XCTAssertEqual(left.maxX, layout.hardwareNotchGeometry?.frame.minX)
        XCTAssertEqual(right.minX, layout.hardwareNotchGeometry?.frame.maxX)
        XCTAssertEqual(left.height, right.height)
        model.activityCoordinator.dismiss(kind: .calendar)
        XCTAssertEqual(model.activityCoordinator.primary?.id, identity)
        XCTAssertEqual(model.presentedIndicators.map(\.id), [music.id])
        let notification = model.presentedNotification
        let shellWidth = NotchSecondaryGeometry.shellWidth(layout: layout, notification: notification, hasIndicators: true)
        let art = NotchSecondaryGeometry.frame(layout: layout, beside: notification, kind: .media)
        let shellRight = layout.collapsedVisibleFrame.midX + shellWidth / 2
        XCTAssertLessThan(art.maxX, shellRight)
        let passive = NotchShape(width: layout.collapsedVisibleFrame.width, height: left.height,
                                 centerX: layout.panelFrame.width / 2, topCornerRadius: 0, bottomCornerRadius: 8)
        let shell = NotchShellSurface(width: shellWidth, height: left.height, centerX: passive.centerX,
                                      bottomRadius: 13, passiveShape: passive, shoulderRadius: 6)
        let path = shell.path(in: CGRect(origin: .zero, size: layout.panelFrame.size))
        for x in stride(from: passive.centerX, through: art.midX - layout.panelFrame.minX, by: 1) {
            XCTAssertTrue(path.contains(CGPoint(x: x, y: left.height / 2)), "No gap between hardware and artwork")
        }
    }

    func testRetiringDownloadYieldsBeforeMusicArtworkEmerges() {
        XCTAssertTrue(NotchCompactActivitySlot.retainsContent(reveal: 0.34, restoresMedia: true))
        XCTAssertFalse(NotchCompactActivitySlot.retainsContent(reveal: 0.33, restoresMedia: true))
        XCTAssertFalse(NotchCompactActivitySlot.retainsContent(reveal: 0.2, restoresMedia: true))
        XCTAssertTrue(NotchCompactActivitySlot.retainsContent(reveal: 0.2, restoresMedia: false))
    }

    func testSpotifyTransferBothWaysKeepsSelectedPageAndConfirmsDevice() async {
        let remote = device("phone", "iPhone", "Smartphone", active: true)
        let local = device("mac", "Test Mac", "Computer")
        let snapshot = playback(on: remote)
        let provider = MockMediaProvider(snapshot: snapshot, devices: [remote, local])
        let model = presentation()
        let media = MediaSessionController(provider: provider, coordinator: model.activityCoordinator,
                                            localDeviceNames: ["test mac"])
        defer { media.stop(); model.reset() }
        media.start()
        await waitUntil { media.homeMediaConnected }
        model.setExpanded(true)
        XCTAssertEqual(model.pageModel.selectedPage, .home)
        media.refreshDevices()
        await waitUntil { !media.devicesLoading }
        XCTAssertEqual(media.connectTarget?.id, local.id)
        media.transferPlayback(to: local)
        XCTAssertEqual(media.state.activeDeviceID, remote.id, "No optimistic active device")
        await waitUntil { !media.devicesLoading }
        XCTAssertEqual(media.state.activeDeviceID, local.id)
        XCTAssertEqual(media.connectTarget?.id, remote.id)
        XCTAssertEqual(model.pageModel.selectedPage, .home)
        XCTAssertTrue(media.state.isPlaying)
        model.pageModel.selectedPage = .shelf
        media.transferPlayback(to: remote)
        await waitUntil { !media.devicesLoading }
        XCTAssertEqual(media.state.activeDeviceID, remote.id)
        XCTAssertEqual(model.pageModel.selectedPage, .shelf)
        XCTAssertTrue(media.state.isPlaying)
    }

    func testDisappearedRemoteTargetDoesNotChooseAnotherPhone() async {
        let phone = device("phone", "Previous iPhone", "Smartphone", active: true)
        let local = device("mac", "Test Mac", "Computer", active: true)
        let unrelated = device("other", "Other Phone", "Smartphone")
        let provider = MockMediaProvider(snapshot: playback(on: local), devices: [local, unrelated])
        let model = presentation()
        let media = MediaSessionController(provider: provider, coordinator: model.activityCoordinator,
                                            localDeviceNames: ["test mac"])
        defer { media.stop(); model.reset() }
        media.receive(playback(on: phone))
        media.receive(playback(on: local))
        media.refreshDevices()
        await waitUntil { !media.devicesLoading }
        XCTAssertNil(media.connectTarget)
        XCTAssertEqual(media.connectTargetName, phone.name)
        media.transferPlayback(to: phone)
        await waitUntil { !media.devicesLoading }
        XCTAssertEqual(media.state.activeDeviceID, local.id)
        XCTAssertNotNil(media.deviceIssue)
    }

    private func temporaryFile() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("polish-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: url)
        return url
    }

    private func musicActivity() -> NotchActivity {
        .init(id: UUID(), key: .media, kind: .media, title: "Music", subtitle: nil, priority: .low, presentationStyle: .mediaSides,
              lifetime: .persistent, isDismissible: false, destination: .music, duration: nil,
              payload: .mediaPlayback(isPlaying: true), minimal: .artwork)
    }

    private func device(_ id: String, _ name: String, _ type: String, active: Bool = false) -> SpotifyDevice {
        .init(id: id, name: name, type: type, isActive: active, isRestricted: false, volumePercent: 60, supportsVolume: true)
    }

    private func playback(on device: SpotifyDevice) -> MediaState {
        .init(connectionState: .authenticated, playbackState: .playing, title: "Song", duration: 240,
              trackID: "song", activeDeviceID: device.id, activeDeviceName: device.name,
              activeDeviceType: device.type, source: .spotify)
    }
}

@MainActor private final class RejectingShelf: ShelfService {
    func loadRecords() -> [ShelfRecord] { [] }
    func saveRecords(_ records: [ShelfRecord]) {}
    func reference(for url: URL) -> Data? { nil }
    func resolve(_ reference: Data) -> ResolvedShelfReference? { nil }
    func fileExists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func startAccessing(_ url: URL) -> Bool { false }
    func stopAccessing(_ url: URL) {}
}
