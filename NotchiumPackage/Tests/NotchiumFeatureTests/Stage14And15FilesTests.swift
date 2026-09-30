import AppKit
import Foundation
import NotchiumCore
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumServices
@testable import NotchiumShelfFeature

/// Stages 14–15: Shelf by reference, native sharing, transfer and screenshot activities on
/// the Stage 12 coordinator.
@MainActor
final class Stage14And15FilesTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let musicID = UUID()
    private let transferKey = NotchActivityKey("transfer")
    private let screenshotKey = NotchActivityKey("screenshot")

    private func clock() -> TestAppClock { TestAppClock(now: base, automaticallyAdvances: false) }
    private func drain() async { for _ in 0..<200 { await Task.yield() } }
    private func settle(_ clock: TestAppClock) async {
        await drain()
        await clock.waitForPendingSleeps()
    }
    private func file(_ name: String) -> URL { URL(fileURLWithPath: "/Users/test/Desktop/\(name)") }

    private func music() -> NotchActivity {
        NotchActivity(id: musicID, key: .media, kind: .media, title: "Media", subtitle: nil,
                      priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
                      isDismissible: false, destination: .music, duration: nil,
                      payload: .mediaPlayback(isPlaying: true), minimal: .artwork)
    }

    private func transfer(_ id: String, _ fraction: Double?, phase: TransferPhase = .active,
                          name: String = "Xcode.dmg", started: TimeInterval = 0) -> TransferSnapshot {
        TransferSnapshot(id: id, displayName: name, operation: .downloading, phase: phase, fraction: fraction,
                         fileURL: URL(fileURLWithPath: "/Users/test/Downloads/\(name)"),
                         startedAt: base.addingTimeInterval(started), updatedAt: base)
    }

    private func features(_ activities: ActivityCoordinator, shelf: MockShelfService = MockShelfService(),
                          actions: RecordingFileActions = RecordingFileActions()) -> FilesFeatureModel {
        FilesFeatureModel(transfers: MockFileTransferService(), screenshots: MockScreenshotService(),
                          shelf: shelf, actions: actions, activities: activities, now: { [base] in base })
    }

    private func compact(_ activities: ActivityCoordinator) -> NotchCompactActivity? {
        activities.notifications.active?.content.compactActivity
    }

    // MARK: Shelf

    func testShelfAddsByReferenceDeduplicatesAndRemoves() {
        let shelfService = MockShelfService(existingPaths: [file("a.pdf").path, file("b.png").path, file("c.txt").path])
        let shelf = ShelfModel(service: shelfService, now: { [base] in base })
        XCTAssertEqual(shelf.add([file("a.pdf")]), 1)
        XCTAssertEqual(shelf.add([file("b.png"), file("c.txt")]), 2)
        XCTAssertEqual(shelf.items.map(\.displayName), ["b.png", "c.txt", "a.pdf"], "Newest drop first, order kept")
        // Re-adding moves to front instead of duplicating; no file is ever copied.
        XCTAssertEqual(shelf.add([file("a.pdf")]), 1)
        XCTAssertEqual(shelf.items.map(\.displayName), ["a.pdf", "b.png", "c.txt"])
        XCTAssertEqual(shelf.items.first?.url, file("a.pdf"))
        XCTAssertEqual(shelfService.records.count, 3)

        shelf.remove(shelf.items[1].id)
        XCTAssertEqual(shelf.items.map(\.displayName), ["a.pdf", "c.txt"])
        shelf.clear()
        XCTAssertTrue(shelf.items.isEmpty)
        XCTAssertTrue(shelfService.records.isEmpty)
    }

    func testShelfRejectsMissingFilesAndIsBounded() {
        let paths = (0..<30).map { file("f\($0).txt").path }
        let shelf = ShelfModel(service: MockShelfService(existingPaths: Set(paths)))
        XCTAssertEqual(shelf.add([file("missing.txt"), URL(string: "https://example.com")!]), 0)
        shelf.add(paths.map { URL(fileURLWithPath: $0) })
        XCTAssertEqual(shelf.items.count, ShelfModel.capacity)
        XCTAssertEqual(shelf.items.first?.displayName, "f0.txt")
    }

    func testMissingRenamedAndDeletedFilesAreDetectedOnDemand() {
        let service = MockShelfService(existingPaths: [file("a.pdf").path, file("b.pdf").path])
        let shelf = ShelfModel(service: service)
        shelf.add([file("a.pdf"), file("b.pdf")])
        // a.pdf renamed (bookmark follows it); b.pdf deleted / volume ejected.
        service.existingPaths = [file("renamed.pdf").path]
        service.movedPaths[file("a.pdf").path] = file("renamed.pdf").path
        shelf.refreshAvailability()
        XCTAssertEqual(shelf.items.first { $0.displayName == "renamed.pdf" }?.isAvailable, true)
        XCTAssertEqual(shelf.items.first { $0.displayName == "b.pdf" }?.isAvailable, false)
    }

    func testRelaunchRestoresValidReferencesAndDropsStaleOnes() {
        let service = MockShelfService(existingPaths: [file("keep.pdf").path, file("gone.pdf").path])
        let first = ShelfModel(service: service, now: { [base] in base })
        first.add([file("gone.pdf"), file("keep.pdf")])
        service.records.append(ShelfRecord(id: UUID(), reference: Data(file("keep.pdf").path.utf8),
                                           addedAt: base.addingTimeInterval(-8 * 24 * 3600)))
        service.existingPaths.remove(file("gone.pdf").path)

        let relaunched = ShelfModel(service: service, now: { [base] in base.addingTimeInterval(3600) })
        relaunched.restore()
        XCTAssertEqual(relaunched.items.map(\.displayName), ["keep.pdf"],
                       "Missing files, expired records and duplicates are not restored")
        XCTAssertEqual(service.records.count, 1, "Cleanup is persisted")
    }

    func testDragOutProvidesTheFileURLLikeFinder() {
        let provider = NSItemProvider(object: file("a.pdf") as NSURL)
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier("public.file-url"))
    }

    // MARK: Drop onto the notch

    func testFileDropFlowAcceptsByReferenceAndReturnsToIdle() {
        let presentation = DynamicIslandPresentationModel(clock: clock())
        let service = MockShelfService(existingPaths: [file("a.pdf").path, file("b.pdf").path])
        let files = features(presentation.activityCoordinator, shelf: service)
        presentation.shelfRenderer = files
        defer { presentation.reset() }

        presentation.setFileDragNearby(true)
        XCTAssertTrue(presentation.showsFileDropTarget)
        presentation.setFileDropTargeted(true)
        XCTAssertEqual(presentation.fileDrag, .targeted)
        XCTAssertTrue(presentation.acceptDroppedFiles([file("a.pdf"), file("b.pdf")]))
        XCTAssertEqual(presentation.fileDrag, .idle)
        XCTAssertEqual(files.shelf.items.count, 2)
        XCTAssertEqual(presentation.notificationCoordinator.active?.kind, .shelfAdded)
        XCTAssertEqual(presentation.pageModel.selectedPage, .home, "A drop never navigates")

        // A drag that leaves returns to the prior state without expanding.
        presentation.setFileDragNearby(true)
        presentation.setFileDragNearby(false)
        XCTAssertFalse(presentation.showsFileDropTarget)
        XCTAssertEqual(presentation.visualState, .collapsed)
        XCTAssertFalse(presentation.acceptDroppedFiles([URL(string: "https://example.com")!]))
    }

    func testDropTargetSuppressesCompactContentWhileDragging() {
        let presentation = DynamicIslandPresentationModel(clock: clock())
        defer { presentation.reset() }
        presentation.notificationCoordinator.present(.charging(level: 0.4))
        XCTAssertNotNil(presentation.presentedNotification)
        presentation.setFileDragNearby(true)
        XCTAssertNil(presentation.presentedNotification)
        XCTAssertNil(presentation.presentedSecondary)
        presentation.endFileDrag()
        XCTAssertNotNil(presentation.presentedNotification, "The activity was never destroyed")
    }

    // MARK: Sharing

    func testShareTargetsSelectionOrAllAvailableAndCancellationNeverChangesShelf() {
        let service = MockShelfService(existingPaths: [file("a.pdf").path, file("b.pdf").path])
        let actions = RecordingFileActions()
        let files = features(ActivityCoordinator(clock: clock()), shelf: service, actions: actions)
        files.shelf.add([file("a.pdf"), file("b.pdf")])
        let a = files.shelf.items.first { $0.displayName == "a.pdf" }!.id
        XCTAssertEqual(files.shareItems(selection: [a]), [file("a.pdf")])
        XCTAssertEqual(Set(files.shareItems(selection: [])), [file("a.pdf"), file("b.pdf")])

        files.airDrop(files.shareItems(selection: []))
        XCTAssertEqual(Set(actions.airDropped.flatMap { $0 }), [file("a.pdf"), file("b.pdf")])
        XCTAssertEqual(files.shelf.items.count, 2, "Sharing or cancelling never alters the Shelf")

        service.existingPaths.remove(file("b.pdf").path)
        files.shelf.refreshAvailability()
        XCTAssertEqual(files.shareItems(selection: []), [file("a.pdf")], "Missing files are never shared")
    }

    func testUnavailableAirDropFailsCleanlyWithANotice() {
        let actions = RecordingFileActions()
        actions.airDropAvailable = false
        let files = features(ActivityCoordinator(clock: clock()), actions: actions)
        files.airDrop([file("a.pdf")])
        XCTAssertEqual(files.notice, "AirDrop is unavailable")
    }

    // MARK: Transfers

    func testTransferStartProgressCoalescesThenCompletesInPlace() async {
        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        let files = features(activities)
        defer { activities.clearAll() }

        files.transfers.receive(transfer("t1", 0.1))
        let id = activities.notifications.active?.id
        XCTAssertEqual(activities.primary?.lifetime, .persistent)
        XCTAssertEqual(compact(activities)?.trailing, .progress(0.1, label: "10%"))
        XCTAssertEqual(compact(activities)?.glyph, .symbol("arrow.down.circle.fill"))
        for fraction in [0.25, 0.5, 0.72] { files.transfers.receive(transfer("t1", fraction)) }
        XCTAssertEqual(activities.notifications.active?.id, id, "Updates never replay entry")
        XCTAssertEqual(compact(activities)?.trailing, .progress(0.72, label: "72%"))
        XCTAssertEqual(activities.liveActivities.map(\.key), [transferKey])

        files.transfers.receive(transfer("t1", 1, phase: .completed))
        XCTAssertEqual(activities.notifications.active?.id, id, "Completion morphs the same activity")
        XCTAssertEqual(compact(activities)?.trailing, .text("Done"))
        XCTAssertEqual(compact(activities)?.glyph, .symbol("checkmark.circle.fill"))
        // A stale sample after completion is ignored.
        files.transfers.receive(transfer("t1", 0.9))
        XCTAssertEqual(compact(activities)?.trailing, .text("Done"))
        XCTAssertTrue(files.transfers.active.isEmpty)

        await settle(clock)
        await clock.advance(by: .milliseconds(2500))
        await waitUntil { activities.primary == nil }
        XCTAssertNil(activities.primary, "Short hold, then dismissed")
        XCTAssertEqual(files.transfers.recent.first?.phase, .completed)
    }

    func testTransferFailureAndStopNeverShowSuccess() {
        let activities = ActivityCoordinator(clock: clock())
        let files = features(activities)
        defer { activities.clearAll() }
        files.transfers.receive(transfer("t1", 0.4))
        files.transfers.receive(transfer("t1", 0.4, phase: .failed("Disk full")))
        XCTAssertEqual(compact(activities)?.trailing, .text("Failed"))
        XCTAssertEqual(activities.notifications.active?.kind, .transferFailed)

        files.transfers.receive(transfer("t2", 0.3))
        files.transfers.receive(transfer("t2", 0.3, phase: .stopped))
        XCTAssertEqual(compact(activities)?.trailing, .text("Stopped"), "Cancel / quit mid-transfer")
        XCTAssertEqual(compact(activities)?.tint, .muted)
    }

    func testMultipleTransfersShowOnePrimaryPlusCountAndNoInterruptingResults() {
        let activities = ActivityCoordinator(clock: clock())
        let files = features(activities)
        defer { activities.clearAll() }
        files.transfers.receive(transfer("a", 0.2, name: "Xcode.dmg", started: 0))
        files.transfers.receive(transfer("b", 0.5, name: "Photos.zip", started: 1))
        files.transfers.receive(transfer("c", nil, name: "Folder", started: 2))
        XCTAssertEqual(compact(activities)?.trailing, .progress(0.2, label: "20% +2"))
        XCTAssertEqual(activities.liveActivities.count, 1, "Never one tab per file")

        files.transfers.receive(transfer("b", 1, phase: .completed, name: "Photos.zip"))
        XCTAssertEqual(activities.notifications.active?.kind, .transferActive, "No result while others run")
        XCTAssertEqual(compact(activities)?.trailing, .progress(0.2, label: "20% +1"))
        files.transfers.receive(transfer("a", 1, phase: .completed))
        files.transfers.receive(transfer("c", nil, phase: .completed, name: "Folder"))
        XCTAssertEqual(compact(activities)?.trailing, .text("Done"))
    }

    func testIndeterminateTransferNeverFakesAPercentage() {
        let activities = ActivityCoordinator(clock: clock())
        let files = features(activities)
        defer { activities.clearAll() }
        let copy = TransferSnapshot(id: "x", displayName: "Project", operation: .copying, phase: .active,
                                    fraction: nil, startedAt: base, updatedAt: base)
        files.transfers.receive(copy)
        XCTAssertEqual(compact(activities)?.trailing, .progress(nil, label: "Copying…"))
        XCTAssertEqual(activities.primary?.minimal, .progress(nil))
    }

    func testBrowserDownloadBundleResolvesToFinishedFile() {
        let snapshot = TransferSnapshot(id: "s", displayName: "Xcode.dmg", operation: .downloading, phase: .completed,
                                        fraction: 1, fileURL: URL(fileURLWithPath: "/D/Xcode.dmg.download"),
                                        startedAt: base, updatedAt: base)
        XCTAssertEqual(snapshot.finishedFileURL, URL(fileURLWithPath: "/D/Xcode.dmg"))
    }

    // MARK: Stage 12 integration

    func testMusicTransferScreenshotSequenceRestoresInOrder() async {
        let clock = clock()
        let presentation = DynamicIslandPresentationModel(clock: clock)
        presentation.mediaRenderer = VisibleMediaStub()
        let files = features(presentation.activityCoordinator)
        let activities = presentation.activityCoordinator
        defer { presentation.reset() }
        activities.present(music())

        // 1. An active download outranks Music; Music waits as the secondary chip.
        files.transfers.receive(transfer("d", 0.65))
        XCTAssertEqual(activities.primary?.key, transferKey)
        XCTAssertEqual(presentation.presentedSecondary?.id, musicID)
        // 2. A screenshot briefly takes the notch, with no chip beside it.
        files.screenshots.receive(.captured(.init(fileURL: file("Shot 1.png"), createdAt: base)))
        XCTAssertEqual(activities.primary?.key, screenshotKey)
        XCTAssertNil(presentation.presentedSecondary)
        XCTAssertTrue(activities.contains(id: musicID))
        // 3. Screenshot expires → the download is visible again.
        await settle(clock)
        await clock.advance(by: .seconds(4))
        await waitUntil { activities.primary?.key == self.transferKey }
        XCTAssertEqual(compact(activities)?.trailing, .progress(0.65, label: "65%"))
        // 4. Download completes → brief completion → Music returns.
        files.transfers.receive(transfer("d", 1, phase: .completed))
        XCTAssertEqual(compact(activities)?.trailing, .text("Done"))
        await settle(clock)
        await clock.advance(by: .milliseconds(2500))
        await waitUntil { activities.primary?.id == self.musicID }
        XCTAssertTrue(presentation.showsCollapsedMedia)
    }

    func testCalendarAndVolumeInterruptATransferWhichThenRestores() {
        let presentation = DynamicIslandPresentationModel(clock: clock())
        presentation.mediaRenderer = VisibleMediaStub()
        let files = features(presentation.activityCoordinator)
        let activities = presentation.activityCoordinator
        defer { presentation.reset() }
        activities.present(music())
        files.transfers.receive(transfer("d", 0.3))

        let reminder = NotchNotification(kind: .reminder5, coalescingKey: "calendar.e", action: .calendar,
                                         presentationStyle: .calendar, content: .calendar(title: "Sync", status: "5 min"))
        activities.notifications.present(reminder)
        XCTAssertEqual(activities.activeTransient?.kind, .calendar)
        // A live transfer outranks Music as the visible secondary beside the Calendar banner.
        XCTAssertEqual(activities.presentationMode, .downwardBanner)
        XCTAssertEqual(presentation.presentedSecondary?.key, NotchActivityKey("transfer"))
        activities.notifications.dismiss()
        XCTAssertEqual(activities.primary?.key, transferKey)

        presentation.showAudioHUD(.init(kind: .volume, deviceName: "Speakers", volume: 0.4, isMuted: false))
        XCTAssertEqual(activities.activeTransient?.kind, .systemHUD)
        activities.notifications.dismiss()
        XCTAssertEqual(activities.primary?.key, transferKey, "The transfer was never recreated")
    }

    func testSecondaryTransferPromotionKeepsBothAlive() {
        let presentation = DynamicIslandPresentationModel(clock: clock())
        presentation.mediaRenderer = VisibleMediaStub()
        let files = features(presentation.activityCoordinator)
        let activities = presentation.activityCoordinator
        defer { presentation.reset() }
        activities.present(music())
        files.transfers.receive(transfer("d", 0.4))
        presentation.activateSecondaryActivity()
        XCTAssertEqual(activities.primary?.id, musicID)
        XCTAssertEqual(presentation.presentedSecondary?.key, transferKey)
        XCTAssertEqual(presentation.presentedSecondary?.minimal, .progress(0.4), "A live progress ring")
        files.transfers.receive(transfer("d", 0.6))
        XCTAssertEqual(presentation.presentedSecondary?.minimal, .progress(0.6))
        XCTAssertNil(presentation.notificationCoordinator.active, "Music draws its own flanks")
    }

    func testClickingATransferOpensShelfWithoutEndingIt() {
        let presentation = DynamicIslandPresentationModel(clock: clock())
        let files = features(presentation.activityCoordinator)
        defer { presentation.reset() }
        files.transfers.receive(transfer("d", 0.4))
        presentation.activateCurrentActivity()
        XCTAssertEqual(presentation.pageModel.selectedPage, .shelf)
        XCTAssertEqual(presentation.activityCoordinator.liveActivities.map(\.key), [transferKey])
    }

    // MARK: Screenshots

    func testScreenshotCaptureCoalescesDuplicatesAndRapidCaptures() {
        let activities = ActivityCoordinator(clock: clock())
        let files = features(activities)
        defer { activities.clearAll() }
        let first = ScreenshotCapture(fileURL: file("Shot 1.png"), createdAt: base)
        files.screenshots.receive(.captured(first))
        files.screenshots.receive(.captured(first))
        XCTAssertEqual(files.screenshots.recent.count, 1, "Repeated file events are one capture")
        let id = activities.notifications.active?.id
        XCTAssertEqual(compact(activities)?.glyph, .thumbnail(file("Shot 1.png")))
        XCTAssertEqual(compact(activities)?.trailing, .text("Screenshot"))

        for index in 2...3 {
            files.screenshots.receive(.captured(.init(fileURL: file("Shot \(index).png"),
                                                      createdAt: base.addingTimeInterval(Double(index)))))
        }
        XCTAssertEqual(activities.notifications.active?.id, id, "No repeated entrance animation")
        XCTAssertEqual(compact(activities)?.glyph, .thumbnail(file("Shot 3.png")), "Latest thumbnail")
        XCTAssertEqual(compact(activities)?.trailing, .text("3 Screenshots"))

        // Same filename reused later is a new capture.
        files.screenshots.receive(.captured(.init(fileURL: file("Shot 1.png"), createdAt: base.addingTimeInterval(60))))
        XCTAssertEqual(files.screenshots.recent.count, 4)
    }

    func testScreenshotExpiresAndDeletionUpdatesOrDismisses() async {
        let clock = clock()
        let activities = ActivityCoordinator(clock: clock)
        let files = features(activities)
        defer { activities.clearAll() }
        files.screenshots.receive(.captured(.init(fileURL: file("A.png"), createdAt: base)))
        files.screenshots.receive(.captured(.init(fileURL: file("B.png"), createdAt: base.addingTimeInterval(1))))
        files.screenshots.receive(.removed(file("B.png")))
        XCTAssertEqual(compact(activities)?.glyph, .thumbnail(file("A.png")))
        XCTAssertEqual(compact(activities)?.trailing, .text("Screenshot"))
        files.screenshots.receive(.removed(file("A.png")))
        XCTAssertNil(activities.primary, "Deleted before any action: no stale UI")
        XCTAssertTrue(files.screenshots.recent.isEmpty)

        files.screenshots.receive(.captured(.init(fileURL: file("C.png"), createdAt: base.addingTimeInterval(5))))
        await settle(clock)
        await clock.advance(by: .seconds(4))
        await waitUntil { activities.primary == nil }
        XCTAssertNil(activities.primary)
        XCTAssertEqual(files.screenshots.recent.count, 1, "Still available on the Shelf page")
    }

    func testScreenshotToShelfShareAndRevealUseTheCaptureFile() throws {
        let path = NSTemporaryDirectory() + "notchium-shot-\(UUID()).png"
        FileManager.default.createFile(atPath: path, contents: Data([0x89]))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let url = URL(fileURLWithPath: path)
        let actions = RecordingFileActions()
        let files = features(ActivityCoordinator(clock: clock()),
                             shelf: MockShelfService(existingPaths: [url.path]), actions: actions)
        files.screenshots.receive(.captured(.init(fileURL: url, createdAt: base)))
        files.addToShelf([files.screenshots.recent[0].fileURL])
        XCTAssertEqual(files.shelf.items.map(\.url), [url])
        files.airDrop([url])
        actions.reveal([url])
        XCTAssertEqual(actions.airDropped, [[url]])
        XCTAssertEqual(actions.revealed, [[url]])

        try FileManager.default.removeItem(atPath: path)
        files.addToShelf([URL(fileURLWithPath: path + "-gone")])
        XCTAssertEqual(files.notice, "File is no longer available")
    }

    func testThumbnailCacheIsBoundedAndSharesInFlightWork() async {
        let counter = Counter()
        let cache = NotchThumbnailCache(countLimit: 2) { _, _, _ in
            await counter.increment()
            return NSImage(size: CGSize(width: 8, height: 8))
        }
        let url = file("A.png")
        async let first = cache.image(for: url, size: CGSize(width: 30, height: 20))
        async let second = cache.image(for: url, size: CGSize(width: 30, height: 20))
        _ = await (first, second)
        _ = await cache.image(for: url, size: CGSize(width: 30, height: 20))
        let generated = await counter.value
        XCTAssertEqual(generated, 1, "One downsampled decode per file and size")
    }

    // MARK: Navigation

    func testBackgroundFileEventsNeverChangeTheSelectedPage() async {
        for page in NotchPage.allCases {
            let clock = clock()
            let presentation = DynamicIslandPresentationModel(clock: clock)
            let files = features(presentation.activityCoordinator)
            presentation.present(.expanded, animated: false)
            presentation.pageModel.selectedPage = page
            var selections: [NotchPage] = []
            let observation = presentation.pageModel.$selectedPage.dropFirst().sink { selections.append($0) }
            files.transfers.receive(transfer("d", 0.2))
            files.screenshots.receive(.captured(.init(fileURL: file("S.png"), createdAt: base)))
            files.transfers.receive(transfer("d", 1, phase: .completed))
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

@MainActor private final class RecordingFileActions: FileActionPerforming {
    var opened: [[URL]] = []
    var revealed: [[URL]] = []
    var airDropped: [[URL]] = []
    var airDropAvailable = true
    func open(_ urls: [URL]) { opened.append(urls) }
    func reveal(_ urls: [URL]) { revealed.append(urls) }
    func copyFiles(_ urls: [URL]) {}
    func copyPaths(_ urls: [URL]) {}
    func airDrop(_ urls: [URL]) -> ShareOutcome {
        guard airDropAvailable else { return .unavailable }
        airDropped.append(urls)
        return .presented
    }
    func chooseFiles() async -> [URL] { [] }
    func openPrivacySettings() {}
}

private actor Counter {
    var value = 0
    func increment() { value += 1 }
}

@MainActor private final class VisibleMediaStub: NotchMediaRendering {
    var collapsedMediaVisible: Bool { true }
    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView { AnyView(Color.clear) }
    func expandedMedia() -> AnyView { AnyView(Color.clear) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(Color.clear) }
}

/// The real service against a real published NSProgress (the same mechanism Finder, browsers
/// and AirDrop use; cross-process delivery was verified separately with two processes).
@MainActor
final class RealFileTransferServiceTests: XCTestCase {
    func testPublishedFileProgressBecomesThrottledSnapshotsThenCompletes() async throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notchium-progress-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = RealFileTransferService(folders: [folder])
        let stream = await service.updates()
        var received: [TransferSnapshot] = []
        let collector = Task { @MainActor in
            for await snapshot in stream {
                received.append(snapshot)
                if snapshot.phase.isTerminal { break }
            }
        }
        try await Task.sleep(for: .milliseconds(200))

        let file = folder.appendingPathComponent("Project.zip")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let progress = Progress(totalUnitCount: 100)
        progress.kind = .file
        progress.fileOperationKind = .copying
        progress.fileURL = file
        progress.publish()
        for step in stride(from: 10, through: 100, by: 10) {
            try await Task.sleep(for: .milliseconds(60))
            progress.completedUnitCount = Int64(step)
        }
        try await Task.sleep(for: .milliseconds(400))
        progress.unpublish()
        _ = await withTaskGroup(of: Void.self) { group in
            group.addTask { await collector.value }
            group.addTask { try? await Task.sleep(for: .seconds(3)) }
            await group.next()
            group.cancelAll()
        }
        collector.cancel()

        let first = try XCTUnwrap(received.first)
        XCTAssertEqual(first.displayName, "Project.zip")
        XCTAssertEqual(first.operation, .copying)
        XCTAssertEqual(first.phase, .active)
        XCTAssertLessThan(received.count, 10, "KVO bursts are throttled")
        XCTAssertEqual(received.last?.phase, .completed)
        XCTAssertEqual(Set(received.map(\.id)).count, 1, "One stable identity per published operation")
    }
}
