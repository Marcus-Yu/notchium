import AppKit
import Foundation
import NotchiumCore
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature
@testable import NotchiumServices
@testable import NotchiumShelfFeature

/// Targeted Stage 14/15 fixes: real drop ingestion, drag-out consumption, interruption
/// re-ranking, collapse presentation, startup access, and the Spotify Connect handoff.
@MainActor
final class ShelfFixPassTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let musicID = UUID()
    private func clock() -> TestAppClock { TestAppClock(now: base, automaticallyAdvances: false) }
    private func drain() async { for _ in 0..<200 { await Task.yield() } }

    private func music() -> NotchActivity {
        NotchActivity(id: musicID, key: .media, kind: .media, title: "Media", subtitle: nil,
                      priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
                      isDismissible: false, destination: .music, duration: nil,
                      payload: .mediaPlayback(isPlaying: true), minimal: .artwork)
    }
    private func download(_ fraction: Double) -> TransferSnapshot {
        TransferSnapshot(id: "d", displayName: "Xcode.dmg", operation: .downloading, phase: .active,
                         fraction: fraction, startedAt: base, updatedAt: base)
    }
    private func files(_ activities: ActivityCoordinator, shelf: MockShelfService = MockShelfService()) -> FilesFeatureModel {
        FilesFeatureModel(transfers: MockFileTransferService(), screenshots: MockScreenshotService(),
                          shelf: shelf, actions: NoFileActions(), activities: activities, now: { [base] in base })
    }

    // MARK: Transfer > Music after an interruption

    func testCalendarInterruptionReRanksToTheTransferNotMusic() async {
        let clock = clock()
        let presentation = DynamicIslandPresentationModel(clock: clock)
        presentation.mediaRenderer = VisibleMedia()
        let activities = presentation.activityCoordinator
        let model = files(activities)
        defer { presentation.reset() }
        activities.present(music())
        model.transfers.receive(download(0.4))
        // The reported path: the user had brought Music forward from the chip.
        presentation.activateSecondaryActivity()
        XCTAssertEqual(activities.primary?.id, musicID)

        activities.notifications.present(.init(kind: .reminder5, coalescingKey: "calendar.e", action: .calendar,
            presentationStyle: .calendar, content: .calendar(title: "Sync", status: "5 min")))
        XCTAssertEqual(activities.activeTransient?.kind, .calendar)
        await drain()
        await clock.waitForPendingSleeps()
        await clock.advance(by: .seconds(5))
        await waitUntil { activities.activeTransient == nil }

        XCTAssertEqual(activities.primary?.key, NotchActivityKey("transfer"), "Re-ranked from current activities")
        XCTAssertEqual(presentation.presentedNotification?.kind, .transferActive)
        XCTAssertTrue(activities.contains(id: musicID), "Music still alive underneath")
        XCTAssertEqual(presentation.presentedSecondary?.id, musicID)
    }

    // MARK: Collapse during an active transfer

    func testCollapsingWithATransferUsesTheMainBlackCloseNotANotificationReveal() {
        typealias Surface = NotchTransitionSurface<EmptyView>
        XCTAssertFalse(Surface.revealsContent(expanded: false, notificationVisible: true, wasExpanded: true),
                       "Expanded → compact transfer: closing black gate, no early content")
        XCTAssertTrue(Surface.revealsContent(expanded: false, notificationVisible: true, wasExpanded: false),
                      "A notification on the collapsed notch still reveals as before")
        XCTAssertTrue(Surface.revealsContent(expanded: true, notificationVisible: false, wasExpanded: false))
        XCTAssertFalse(Surface.revealsContent(expanded: false, notificationVisible: false, wasExpanded: true))

        // Geometry-driven handoff: hidden while the shell is still closing, revealed once it has
        // landed at the compact height (no wait for the spring's removal callback). The Music
        // path (no compact target) keeps its existing gate.
        let passive = NotchShape(width: 200, height: 32, centerX: 300, topCornerRadius: 0, bottomCornerRadius: 8)
        func closing(height: CGFloat, compact: Bool) -> NotchSurfaceFrame<EmptyView> {
            NotchSurfaceFrame(shape: .init(width: 400, height: height, centerX: 300, bottomRadius: 12,
                                           passiveShape: passive),
                              phase: .closingBlack, expandedHeight: 32, notificationVisible: compact) { _ in EmptyView() }
        }
        XCTAssertEqual(closing(height: 140, compact: true).contentPhase, .closingBlack, "No early flash")
        XCTAssertEqual(closing(height: 32.5, compact: true).contentPhase, .collapsed, "Revealed as it lands")
        XCTAssertEqual(closing(height: 31, compact: true).contentPhase, .collapsed, "Overshoot never flickers")
        XCTAssertEqual(closing(height: 32, compact: false).contentPhase, .closingBlack, "Music gate unchanged")
    }

    // MARK: Real drop ingestion

    func testFinderStyleDropThroughThePanelAddsFilesMultipleAndFolders() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notchium-drop-\(UUID())")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("a.pdf"), b = folder.appendingPathComponent("b.png")
        [a, b].forEach { FileManager.default.createFile(atPath: $0.path, contents: Data("x".utf8)) }
        let dir = folder.appendingPathComponent("Folder")

        let presentation = DynamicIslandPresentationModel(clock: clock())
        let shelfService = RealShelfService(defaults: UserDefaults(suiteName: "notchium.test.shelf.\(UUID())")!)
        let model = FilesFeatureModel(transfers: MockFileTransferService(), screenshots: MockScreenshotService(),
                                      shelf: shelfService, actions: NoFileActions(),
                                      activities: presentation.activityCoordinator)
        presentation.shelfRenderer = model
        let controller = NotchiumPanelController(model: presentation)
        defer { controller.hide(); presentation.reset() }
        let placement = NotchShellPlacement(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch)
        let layout = NotchGeometryResolver.layout(for: placement, state: .collapsed)
        controller.reconcile(placement: placement, layout: layout, renderConfiguration: .automatic, animated: false)
        let inside = controller.windowPoint(forScreenPoint: CGPoint(x: layout.collapsedVisibleFrame.midX,
                                                                    y: layout.collapsedVisibleFrame.minY - 20))
        let outside = controller.windowPoint(forScreenPoint: CGPoint(x: layout.collapsedVisibleFrame.midX,
                                                                     y: layout.collapsedVisibleFrame.minY - 200))

        // Exactly what Finder puts on the drag pasteboard: file URLs.
        let drag = FakeDrag(urls: [a, b, dir], location: inside)
        XCTAssertEqual(controller.fileDragOperation(for: drag), .copy)
        XCTAssertEqual(presentation.fileDrag, .targeted)
        XCTAssertEqual(controller.fileDragOperation(for: FakeDrag(urls: [a], location: outside)), [],
                       "Only near the notch")
        XCTAssertTrue(controller.performFileDrop(drag))
        XCTAssertEqual(model.shelf.items.map(\.displayName), ["a.pdf", "b.png", "Folder"])
        XCTAssertEqual(presentation.notificationCoordinator.active?.content.compactActivity?.trailing, .text("3 Added"))

        // Duplicate moves to front; a file persisted by reference survives a relaunch.
        presentation.setFileDragNearby(true)
        XCTAssertTrue(controller.performFileDrop(FakeDrag(urls: [b], location: inside)))
        XCTAssertEqual(model.shelf.items.map(\.displayName), ["b.png", "a.pdf", "Folder"])
        let relaunched = ShelfModel(service: shelfService)
        relaunched.restore()
        XCTAssertEqual(relaunched.items.map(\.displayName), ["b.png", "a.pdf", "Folder"])

        // Non-file drags are refused; a drag from inside Notchium is never re-ingested.
        XCTAssertEqual(controller.fileDragOperation(for: FakeDrag(urls: [], location: inside)), [])
        XCTAssertEqual(controller.fileDragOperation(for: FakeDrag(urls: [a], location: inside, isInternal: true)), [])
    }

    func testDropOfUnavailableFilesShowsAConciseFailure() {
        let presentation = DynamicIslandPresentationModel(clock: clock())
        let model = files(presentation.activityCoordinator)
        presentation.shelfRenderer = model
        defer { presentation.reset() }
        presentation.setFileDragNearby(true)
        XCTAssertFalse(presentation.acceptDroppedFiles([URL(fileURLWithPath: "/nonexistent/x.pdf")]))
        XCTAssertEqual(presentation.notificationCoordinator.active?.content.compactActivity?.trailing,
                       .text("Couldn’t Add"))
        XCTAssertTrue(model.shelf.items.isEmpty)
    }

    func testCancelledDragChangesNothing() {
        let presentation = DynamicIslandPresentationModel(clock: clock())
        let model = files(presentation.activityCoordinator)
        presentation.shelfRenderer = model
        defer { presentation.reset() }
        presentation.setFileDragNearby(true)
        presentation.setFileDropTargeted(true)
        presentation.endFileDrag()
        XCTAssertEqual(presentation.fileDrag, .idle)
        XCTAssertTrue(model.shelf.items.isEmpty)
        XCTAssertNil(presentation.notificationCoordinator.active)
    }

    // MARK: Drag-out consumption

    func testOnlyASuccessfulExternalDropConsumesTheShelfItem() {
        XCTAssertTrue(ShelfDragOutcome.consumesItem(.copy))
        XCTAssertFalse(ShelfDragOutcome.consumesItem(.link))
        XCTAssertFalse(ShelfDragOutcome.consumesItem(.generic))
        XCTAssertTrue(ShelfDragOutcome.consumesItem(.move))
        XCTAssertFalse(ShelfDragOutcome.consumesItem([]), "Cancelled or refused drops keep the item")

        let view = ShelfDragSource.DragSourceView()
        XCTAssertEqual(view.draggingSession(NSDraggingSessionStub.make(), sourceOperationMaskFor: .outsideApplication),
                       [.move, .copy], "Real file operations only; AppKit modifiers negotiate copy")
        XCTAssertEqual(view.draggingSession(NSDraggingSessionStub.make(), sourceOperationMaskFor: .withinApplication), [])
        var delivered = 0
        view.onDelivered = { _ in delivered += 1 }
        view.draggingSession(NSDraggingSessionStub.make(), endedAt: .zero, operation: [])
        XCTAssertEqual(delivered, 0)
        view.draggingSession(NSDraggingSessionStub.make(), endedAt: .zero, operation: .copy)
        XCTAssertEqual(delivered, 1)
        XCTAssertNil(view.hitTest(.zero), "Clicks and context menus still reach the tile")
    }

    // MARK: Spotify Connect handoff

    /// Phone → Mac: the provider reports a new active device (and a brief stale/no-device
    /// sample). Notchium must observe only; it sends no playback-changing command.
    func testExternalConnectHandoffSendsNoCommands() async throws {
        let provider = MockMediaProvider()
        let presentation = DynamicIslandPresentationModel(clock: clock())
        let media = MediaSessionController(provider: provider, coordinator: presentation.activityCoordinator)
        defer { media.stop(); presentation.reset() }
        media.start()
        await drain()
        func state(device: String?, elapsed: Double, playing: Bool = true) -> MediaState {
            var value = MediaState(connectionState: .authenticated, playbackState: playing ? .playing : .paused,
                                   title: "Song", trackID: "track-1", activeDeviceID: device, source: .spotify)
            value.elapsed = elapsed
            value.duration = 200
            return value
        }
        for sample in [state(device: "phone", elapsed: 42), state(device: nil, elapsed: 42, playing: false),
                       state(device: "mac", elapsed: 43), state(device: "mac", elapsed: 44)] {
            await provider.publish(sample)
            await drain()
        }
        let commands = await provider.commands
        let seek = await provider.requestedSeekPosition
        let queued = await provider.queuedURIs
        XCTAssertTrue(commands.isEmpty, "No play/pause/next/previous/seek: \(commands)")
        XCTAssertNil(seek)
        XCTAssertTrue(queued.isEmpty)
        XCTAssertEqual(media.state.trackID, "track-1")
        XCTAssertEqual(media.state.activeDeviceID, "mac")
    }
}

// MARK: Test doubles

@MainActor private final class NoFileActions: FileActionPerforming {
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

/// A Finder-like drag: a private pasteboard holding file URLs, at a panel location.
private final class FakeDrag: NSObject, NSDraggingInfo {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("notchium.test.drag.\(UUID())"))
    let location: NSPoint
    let isInternal: Bool
    init(urls: [URL], location: NSPoint, isInternal: Bool = false) {
        self.location = location
        self.isInternal = isInternal
        super.init()
        pasteboard.clearContents()
        if urls.isEmpty { pasteboard.setString("text", forType: .string) } else { pasteboard.writeObjects(urls as [NSURL]) }
    }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .link, .generic, .move] }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { isInternal ? self : nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation { get { .default } set {} }
    var animatesToDestination: Bool { get { false } set {} }
    var numberOfValidItemsForDrop: Int { get { 1 } set {} }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

private enum NSDraggingSessionStub {
    /// NSDraggingSession has no public initializer; the source callbacks only need an instance.
    static func make() -> NSDraggingSession { unsafeBitCast(NSObject(), to: NSDraggingSession.self) }
}
