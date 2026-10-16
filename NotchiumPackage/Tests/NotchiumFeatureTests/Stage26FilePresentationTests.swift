import AppKit
import NotchiumCore
import NotchiumServices
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumShelfFeature

@MainActor
final class Stage26FilePresentationTests: XCTestCase {
    func testFirstClickPresentsWithoutReadingDownloadsAndCancelDoesNotReportFailure() async {
        let actions = PendingFileActions()
        let model = files(actions)
        defer { model.stop() }
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSView()
        window.contentView = view
        defer { window.close() }
        model.addChosenFiles(from: view)
        model.addChosenFiles(from: view)
        await waitUntil { actions.continuation != nil }
        XCTAssertEqual(actions.calls, 1)
        XCTAssertTrue(actions.origin === view)
        XCTAssertTrue(model.isChoosingFiles)
        actions.complete([])
        await waitUntil { !model.isChoosingFiles }
        XCTAssertTrue(model.shelf.items.isEmpty)
        XCTAssertNil(model.notice, "Cancel is not an unavailable-file error")
        model.addChosenFiles(from: view)
        await waitUntil { actions.continuation != nil }
        XCTAssertEqual(actions.calls, 2)
        actions.complete([])
        await waitUntil { !model.isChoosingFiles }
    }

    func testMultipleFilesAndFolderAreInsertedByReferenceAndStopRejectsLateSelection() async {
        let urls = ["a.txt", "b.png", "folder"].map { URL(fileURLWithPath: "/tmp/stage26/\($0)") }
        let service = MockShelfService(existingPaths: Set(urls.map(\.path)))
        let actions = PendingFileActions()
        let model = files(actions, service: service)
        model.addChosenFiles()
        await waitUntil { actions.continuation != nil }
        actions.complete(urls)
        await waitUntil { !model.isChoosingFiles }
        XCTAssertEqual(model.shelf.items.map(\.url), urls)
        model.addChosenFiles()
        await waitUntil { actions.continuation != nil }
        model.stop()
        actions.complete([urls[1]])
        await waitUntil { !model.isChoosingFiles }
        XCTAssertEqual(model.shelf.items.map(\.url), urls, "Stopped sessions cannot commit a late selection")
    }

    func testOpenPanelOwnsLeaseAndVisibilityConfigurationThroughEveryCancel() async {
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: ControlledAppClock())
        model.pageModel.selectedPage = .shelf
        defer { model.reset() }
        let chooser = NativeFilePanel()
        var presentations = 0
        chooser.present = { panel in
            presentations += 1
            XCTAssertTrue(model.isAuxiliaryInteractionPresented)
            XCTAssertTrue(panel.canChooseDirectories)
            XCTAssertTrue(panel.canChooseFiles)
            XCTAssertTrue(panel.allowsMultipleSelection)
            XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllApplications))
            XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
            XCTAssertEqual(panel.level, .modalPanel)
            return .cancel
        }
        for _ in 0..<20 {
            let urls = await chooser.choose(from: nil, interaction: model.auxiliaryInteractionHandler)
            XCTAssertTrue(urls.isEmpty)
            XCTAssertNil(chooser.panel)
            XCTAssertFalse(model.isAuxiliaryInteractionPresented)
            XCTAssertEqual(model.pageModel.selectedPage, .shelf)
        }
        XCTAssertEqual(presentations, 20)
    }

    func testPendingOpenPanelRejectsConcurrentPresentation() async {
        let chooser = NativeFilePanel()
        var completion: CheckedContinuation<NSApplication.ModalResponse, Never>?
        chooser.present = { _ in await withCheckedContinuation { completion = $0 } }
        let task = Task { await chooser.choose(from: nil, interaction: .init()) }
        await waitUntil { completion != nil }
        let duplicate = await chooser.choose(from: nil, interaction: .init())
        XCTAssertTrue(duplicate.isEmpty)
        completion?.resume(returning: .cancel)
        _ = await task.value
        XCTAssertNil(chooser.panel)
    }

    func testEachDisplayKeepsItsOwnAnchor() {
        let first = FileActionAnchor(), second = FileActionAnchor()
        let a = NSView(), b = NSView()
        first.view = a
        second.view = b
        XCTAssertTrue(first.view === a)
        XCTAssertTrue(second.view === b)
    }

    func testTransferObservationDoesNotRequireReadingTheWatchedFolder() async {
        let service = RealFileTransferService(folders: [URL(fileURLWithPath: "/private/tmp/stage26-absent-\(UUID())")])
        let availability = await service.availability()
        XCTAssertEqual(availability, .available, "Progress subscription availability is independent of file-read access")
        let stream = await service.updates()
        let task = Task { for await _ in stream { } }
        task.cancel()
        _ = await task.value
    }

    func testNonFiniteTransferProgressBecomesIndeterminateBeforeRendering() {
        for fraction in [Double.nan, .infinity, -.infinity] {
            let snapshot = TransferSnapshot(id: "fixture", displayName: "Fixture", operation: .downloading,
                phase: .active, fraction: fraction, startedAt: .distantPast, updatedAt: .distantPast)
            XCTAssertNil(snapshot.fraction, "Rendering a percent must never convert NaN to Int")
        }
    }

    private func files(_ actions: PendingFileActions, service: MockShelfService = MockShelfService()) -> FilesFeatureModel {
        FilesFeatureModel(transfers: MockFileTransferService(), screenshots: MockScreenshotService(),
                          shelf: service, actions: actions, activities: ActivityCoordinator(clock: ControlledAppClock()))
    }
}

@MainActor private final class PendingFileActions: FileActionPerforming {
    var calls = 0
    weak var origin: NSView?
    var continuation: CheckedContinuation<[URL], Never>?
    func open(_ urls: [URL]) {}
    func reveal(_ urls: [URL]) {}
    func copyFiles(_ urls: [URL]) {}
    func copyPaths(_ urls: [URL]) {}
    func airDrop(_ urls: [URL]) -> ShareOutcome { .unavailable }
    func openPrivacySettings() {}
    func chooseFiles() async -> [URL] { await chooseFiles(from: nil, interaction: .init()) }
    func chooseFiles(from view: NSView?, interaction: NotchAuxiliaryInteractionHandler) async -> [URL] {
        calls += 1
        origin = view
        return await withCheckedContinuation { continuation = $0 }
    }
    func complete(_ urls: [URL]) {
        let saved = continuation
        continuation = nil
        saved?.resume(returning: urls)
    }
}
