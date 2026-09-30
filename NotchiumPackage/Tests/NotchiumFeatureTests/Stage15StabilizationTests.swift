import AppKit
import Foundation
import NotchiumCore
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature
@testable import NotchiumServices
@testable import NotchiumShelfFeature

@MainActor
final class Stage15StabilizationTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let musicID = UUID()
    private let transferKey = NotchActivityKey("transfer")
    private func clock() -> TestAppClock { TestAppClock(now: base, automaticallyAdvances: false) }
    private func drain() async { for _ in 0..<200 { await Task.yield() } }
    private func settle(_ clock: TestAppClock) async { await drain(); await clock.waitForPendingSleeps() }

    private func music() -> NotchActivity {
        NotchActivity(id: musicID, key: .media, kind: .media, title: "Media", subtitle: nil,
                      priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
                      isDismissible: false, destination: .music, duration: nil,
                      payload: .mediaPlayback(isPlaying: true), minimal: .artwork)
    }
    private func download(_ fraction: Double, _ phase: TransferPhase = .active) -> TransferSnapshot {
        TransferSnapshot(id: "d", displayName: "Xcode.dmg", operation: .downloading, phase: phase,
                         fraction: fraction, startedAt: base, updatedAt: base)
    }
    private let reminder = NotchNotification(kind: .reminder5, coalescingKey: "calendar.e", action: .calendar,
                                             presentationStyle: .calendar,
                                             content: .calendar(title: "Sync", status: "5 min"))

    // MARK: Multi-activity priority and continuity

    func testMusicDownloadCalendarSequenceKeepsTheRightPrimaryAndSecondary() async {
        let clock = clock()
        let presentation = DynamicIslandPresentationModel(clock: clock)
        presentation.mediaRenderer = VisibleMedia()
        let activities = presentation.activityCoordinator
        let files = FilesFeatureModel(transfers: MockFileTransferService(), screenshots: MockScreenshotService(),
                                      shelf: MockShelfService(), actions: NoActions(), activities: activities,
                                      now: { [base] in base })
        defer { presentation.reset() }
        activities.present(music())
        var musicChanges = 0
        let musicObservation = activities.$liveActivities
            .map { $0.first { $0.key == .media }?.id }.removeDuplicates().dropFirst()
            .sink { _ in musicChanges += 1 }
        defer { musicObservation.cancel() }

        // Music → Download: Download primary, Music secondary.
        files.transfers.receive(download(0.3))
        let transferID = presentation.notificationCoordinator.active?.id
        XCTAssertEqual(activities.primary?.key, transferKey)
        XCTAssertEqual(presentation.presentedSecondary?.id, musicID)
        XCTAssertEqual(activities.presentationMode, .combined, "Music stays mounted under the compact transfer")

        // Calendar arrives: Calendar primary, Download (not Music) the visible secondary.
        activities.notifications.present(reminder)
        XCTAssertEqual(activities.activeTransient?.kind, .calendar)
        XCTAssertEqual(presentation.presentedSecondary?.key, transferKey)
        XCTAssertEqual(activities.presentationMode, .downwardBanner, "Music is not shown in the banner row")
        XCTAssertTrue(activities.contains(id: musicID))
        files.transfers.receive(download(0.5))
        XCTAssertEqual(presentation.presentedSecondary?.minimal, .progress(0.5), "The chip stays live")

        // Calendar expires: Download primary again (same identity), Music secondary.
        await settle(clock)
        await clock.advance(by: .seconds(5))
        await waitUntil { activities.activeTransient == nil }
        XCTAssertEqual(activities.primary?.key, transferKey)
        XCTAssertEqual(presentation.notificationCoordinator.active?.id, transferID, "Never recreated")
        XCTAssertEqual(presentation.presentedSecondary?.id, musicID)

        // Download completes → brief result → Music primary.
        files.transfers.receive(download(1, .completed))
        await settle(clock)
        await clock.advance(by: .milliseconds(2500))
        await waitUntil { activities.primary?.id == self.musicID }
        XCTAssertNil(presentation.presentedSecondary)
        XCTAssertTrue(presentation.showsCollapsedMedia)
        XCTAssertEqual(musicChanges, 0, "Music was never removed or recreated")
    }

    func testCalendarWithOnlyMusicIsUnchanged() {
        let presentation = DynamicIslandPresentationModel(clock: clock())
        presentation.mediaRenderer = VisibleMedia()
        defer { presentation.reset() }
        presentation.activityCoordinator.present(music())
        presentation.notificationCoordinator.present(reminder)
        XCTAssertEqual(presentation.activityCoordinator.presentationMode, .combined)
        XCTAssertTrue(presentation.showsCollapsedMedia)
        XCTAssertNil(presentation.presentedSecondary, "Music lives in the banner row, never a chip")
    }

    func testSecondaryChipHitFrameFollowsTheDrawnPrimary() {
        let layout = NotchGeometryResolver.layout(for: .init(display: NotchShellDebugModel.builtInFixture,
                                                             mode: .physicalNotch), state: .collapsed)
        let media = NotchSecondaryGeometry.frame(layout: layout)
        let transfer = NotchSecondaryGeometry.frame(layout: layout, beside: TransferActivityModel.activeNotification(
            primary: download(0.4), others: 0))
        let calendar = NotchSecondaryGeometry.frame(layout: layout, beside: reminder)
        XCTAssertGreaterThan(transfer.minX, media.minX, "Beside the wider compact transfer, not the Music flanks")
        XCTAssertGreaterThan(calendar.minX, layout.collapsedVisibleFrame.midX
                             + NotchNotificationGeometry.size(for: .calendar, layout: layout).width / 2)
    }

    // MARK: Remote vs local Spotify default page

    private func media(_ presentation: DynamicIslandPresentationModel) -> MediaSessionController {
        MediaSessionController(provider: MockMediaProvider(), coordinator: presentation.activityCoordinator,
                               localDeviceNames: ["marcus’s macbook air"])
    }
    private func playing(on device: String, type: String) -> MediaState {
        MediaState(connectionState: .authenticated, playbackState: .playing, title: "Song", trackID: "t",
                   activeDeviceID: device, activeDeviceName: device, activeDeviceType: type, source: .spotify)
    }

    func testRemoteConnectPlaybackOpensHomeAndLocalOpensMusic() {
        let presentation = DynamicIslandPresentationModel(clock: clock())
        let controller = media(presentation)
        defer { controller.stop(); presentation.reset() }
        controller.receive(playing(on: "iPhone", type: "Smartphone"))
        XCTAssertFalse(controller.isPlaybackLocal)
        presentation.setExpanded(true)
        XCTAssertEqual(presentation.pageModel.selectedPage, .home, "Remote playback does not claim the notch")
        presentation.present(.collapsed, animated: false)

        controller.receive(playing(on: "Marcus’s MacBook Air", type: "Computer"))
        XCTAssertTrue(controller.isPlaybackLocal)
        presentation.setExpanded(true)
        XCTAssertEqual(presentation.pageModel.selectedPage, .music)
    }

    func testManualMusicChoiceAndHandoffsNeverMoveAnOpenPage() {
        let presentation = DynamicIslandPresentationModel(clock: clock())
        let controller = media(presentation)
        defer { controller.stop(); presentation.reset() }
        controller.receive(playing(on: "iPhone", type: "Smartphone"))
        presentation.setExpanded(true)
        presentation.pageModel.selectedPage = .music
        controller.receive(playing(on: "Marcus’s MacBook Air", type: "Computer"))
        controller.receive(playing(on: "iPhone", type: "Smartphone"))
        XCTAssertEqual(presentation.pageModel.selectedPage, .music, "Manual choice wins")

        presentation.pageModel.selectedPage = .calendar
        controller.receive(playing(on: "Marcus’s MacBook Air", type: "Computer"))
        XCTAssertEqual(presentation.pageModel.selectedPage, .calendar, "A handoff never switches an open page")
    }

    // MARK: Shelf drag-in / drag-out

    func testFileDragModeLowersThePanelBelowTheDragLayerAndRestoresIt() {
        XCTAssertLessThan(NotchPanel.fileDragLevel.rawValue, NSWindow.Level(Int(CGWindowLevelForKey(.draggingWindow))).rawValue,
                          "Below the window server's drag layer, where drops are delivered")
        XCTAssertGreaterThan(NotchPanel.fileDragLevel.rawValue, NSWindow.Level.mainMenu.rawValue, "Still above the menu bar")
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: true)
        panel.applyNotchWindowBehavior()
        XCTAssertEqual(panel.level, NotchPanel.restingLevel)
        panel.setAcceptsFileDrags(true)
        XCTAssertEqual(panel.level, NotchPanel.fileDragLevel)
        panel.setAcceptsFileDrags(false)
        XCTAssertEqual(panel.level, NotchPanel.restingLevel)
    }

    func testDroppedFilesAppearInTheSameShelfModelThePageRenders() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notchium-same-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Report.pdf")
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        let presentation = DynamicIslandPresentationModel(clock: clock())
        let files = FilesFeatureModel(transfers: MockFileTransferService(), screenshots: MockScreenshotService(),
                                      shelf: RealShelfService(defaults: UserDefaults(suiteName: "notchium.same.\(UUID())")!),
                                      actions: NoActions(), activities: presentation.activityCoordinator)
        presentation.shelfRenderer = files
        defer { presentation.reset() }
        // Finder's real pasteboard shape: file URLs.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("notchium.finder.\(UUID())"))
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        presentation.setFileDragNearby(true)
        XCTAssertTrue(presentation.acceptDroppedFiles(NotchFileDrop.fileURLs(from: pasteboard)))
        XCTAssertTrue((presentation.shelfRenderer as AnyObject) === files)
        XCTAssertEqual(files.shelf.items.map(\.url.standardizedFileURL), [file.standardizedFileURL])
    }
}

@MainActor private final class NoActions: FileActionPerforming {
    func open(_ urls: [URL]) {}
    func reveal(_ urls: [URL]) {}
    func copyFiles(_ urls: [URL]) {}
    func copyPaths(_ urls: [URL]) {}
    func airDrop(_ urls: [URL]) -> ShareOutcome { .presented }
    func chooseFiles() async -> [URL] { [] }
    func openPrivacySettings() {}
}

@MainActor private final class VisibleMedia: NotchMediaRendering {
    var collapsedMediaVisible: Bool { true }
    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView { AnyView(Color.clear) }
    func expandedMedia() -> AnyView { AnyView(Color.clear) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(Color.clear) }
}
