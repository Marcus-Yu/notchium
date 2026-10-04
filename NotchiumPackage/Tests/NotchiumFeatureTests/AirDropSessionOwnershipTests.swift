import AppKit
import NotchiumCore
@testable import NotchiumDynamicIsland
import NotchiumServices
@testable import NotchiumShelfFeature
import XCTest

/// A sharing service whose start behavior is scripted; it never shows UI.
private final class ScriptedSharingService: NSSharingService {
    enum Start { case accepts, failsImmediately, silent }
    let start: Start
    let performable: Bool
    private(set) var performedItems: [[Any]] = []

    init(_ start: Start = .accepts, performable: Bool = true) {
        self.start = start
        self.performable = performable
        super.init(title: "Scripted", image: NSImage(), alternateImage: nil) {}
    }

    override func canPerform(withItems items: [Any]?) -> Bool { performable }

    override func perform(withItems items: [Any]) {
        performedItems.append(items)
        // Tests drive AppKit on the main thread, as ShareKit does.
        nonisolated(unsafe) let service = self, items = items
        MainActor.assumeIsolated {
            switch service.start {
            case .accepts: service.delegate?.sharingService?(service, willShareItems: items)
            case .failsImmediately:
                service.delegate?.sharingService?(service, willShareItems: items)
                service.delegate?.sharingService?(service, didFailToShareItems: items, error: CocoaError(.fileReadNoSuchFile))
            case .silent: break
            }
        }
    }

    @MainActor func complete() { delegate?.sharingService?(self, didShareItems: []) }
    @MainActor func cancel() { delegate?.sharingService?(self, didFailToShareItems: [], error: CocoaError(.userCancelled)) }
}

@MainActor
final class AirDropSessionOwnershipTests: XCTestCase {
    private let files = [URL(fileURLWithPath: "/tmp/notchium-a.txt"), URL(fileURLWithPath: "/tmp/notchium-b.txt")]

    private func makeModel() -> DynamicIslandPresentationModel {
        DynamicIslandPresentationModel(phase: .expanded, clock: ControlledAppClock())
    }

    private func sharing(_ services: [ScriptedSharingService]) -> NativeFileSharing {
        let sharing = NativeFileSharing()
        var queue = services
        sharing.makeAirDropService = { queue.isEmpty ? nil : queue.removeFirst() }
        return sharing
    }

    func testRapidActivationPresentsOnceAndTakesOneLease() {
        let model = makeModel()
        defer { model.reset() }
        let services = (0..<10).map { _ in ScriptedSharingService() }
        let sharing = sharing(services)
        let outcomes = (0..<10).map { _ in sharing.airDrop(files, from: nil, interaction: model.auxiliaryInteractionHandler) }
        XCTAssertEqual(outcomes, [.presented] + Array(repeating: .inProgress, count: 9))
        XCTAssertEqual(services.map(\.performedItems.count), [1] + Array(repeating: 0, count: 9))
        XCTAssertEqual(sharing.share(files, from: NSView(), interaction: model.auxiliaryInteractionHandler), .inProgress)
        XCTAssertTrue(sharing.isActive)
        services[0].complete()
        XCTAssertFalse(model.isAuxiliaryInteractionPresented, "Exactly one lease was taken and released")
        XCTAssertFalse(sharing.isActive)
        XCTAssertEqual(sharing.airDrop(files, from: nil, interaction: model.auxiliaryInteractionHandler), .presented,
                       "The gate reopens as soon as the session ends")
        services[1].cancel()
    }

    func testCompletionAndCancellationReleaseExactlyOnce() {
        for completes in [true, false] {
            let model = makeModel()
            defer { model.reset() }
            let probe = model.auxiliaryInteractionHandler
            probe.begin(source: "probe") // An unrelated lease must survive repeated terminals.
            let service = ScriptedSharingService()
            let sharing = sharing([service])
            XCTAssertEqual(sharing.airDrop(files, from: nil, interaction: model.auxiliaryInteractionHandler), .presented)
            for _ in 0..<3 { completes ? service.complete() : service.cancel() }
            XCTAssertFalse(sharing.isActive)
            XCTAssertTrue(model.isAuxiliaryInteractionPresented, "A repeated terminal callback cannot release another lease")
            probe.end(actionSelected: false, source: "probe")
            XCTAssertFalse(model.isAuxiliaryInteractionPresented)
        }
    }

    /// Observed with the real AirDrop service: ShareKit calls back with a different
    /// `NSSharingService` instance than the one `perform` was sent to.
    func testCallbackFromShareKitsOwnServiceInstanceStillEndsTheSession() throws {
        for completes in [true, false] {
            let model = makeModel()
            defer { model.reset() }
            let service = ScriptedSharingService()
            let sharing = sharing([service])
            XCTAssertEqual(sharing.airDrop(files, from: nil, interaction: model.auxiliaryInteractionHandler), .presented)
            let delegate = try XCTUnwrap(service.delegate)
            let reported = try XCTUnwrap(NSSharingService(named: .sendViaAirDrop))
            XCTAssertFalse(reported === service)
            if completes { delegate.sharingService?(reported, didShareItems: []) }
            else { delegate.sharingService?(reported, didFailToShareItems: [], error: CocoaError(.userCancelled)) }
            XCTAssertFalse(sharing.isActive)
            XCTAssertFalse(model.isAuxiliaryInteractionPresented)
        }
    }

    func testFailedOrSilentStartNeverLeavesOwnership() {
        for start in [ScriptedSharingService.Start.failsImmediately, .silent] {
            let model = makeModel()
            defer { model.reset() }
            let service = ScriptedSharingService(start)
            let sharing = sharing([service])
            XCTAssertEqual(sharing.airDrop(files, from: nil, interaction: model.auxiliaryInteractionHandler), .unavailable)
            XCTAssertEqual(service.performedItems.count, 1)
            XCTAssertFalse(sharing.isActive)
            XCTAssertFalse(model.isAuxiliaryInteractionPresented)
            service.complete() // A callback after the failed start changes nothing.
            XCTAssertFalse(model.isAuxiliaryInteractionPresented)
        }
    }

    func testInvalidRequestsAreRejectedBeforeAnyOwnership() throws {
        let model = makeModel()
        defer { model.reset() }
        let unperformable = ScriptedSharingService(performable: false)
        for (services, urls) in [([ScriptedSharingService()], [URL]()), ([], files), ([unperformable], files)] {
            let sharing = sharing(services)
            XCTAssertEqual(sharing.airDrop(urls, from: nil, interaction: model.auxiliaryInteractionHandler), .unavailable)
            XCTAssertFalse(sharing.isActive)
            XCTAssertFalse(model.isAuxiliaryInteractionPresented)
        }
        XCTAssertTrue(unperformable.performedItems.isEmpty)
        // A real AirDrop service refuses a missing file before any presentation.
        let missing = NativeFileSharing()
        guard NSSharingService(named: .sendViaAirDrop) != nil else { return }
        XCTAssertEqual(missing.airDrop([URL(fileURLWithPath: "/tmp/notchium-missing-\(UUID()).txt")], from: nil,
                                       interaction: model.auxiliaryInteractionHandler), .unavailable)
        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
    }

    func testShelfNeverOffersAnItemThatWentMissing() {
        let service = MockShelfService(existingPaths: Set(files.map(\.path)))
        let model = FilesFeatureModel(transfers: MockFileTransferService(), screenshots: MockScreenshotService(),
                                      shelf: service, actions: NativeFileActions(),
                                      activities: ActivityCoordinator(clock: TestAppClock(now: Date(), automaticallyAdvances: false)))
        model.shelf.add(files)
        service.existingPaths.remove(files[1].path)
        model.shelf.refreshAvailability()
        XCTAssertEqual(model.shareItems(selection: []), [files[0]])
        XCTAssertEqual(model.shareItems(selection: [model.shelf.items[1].id]), [], "A stale selection offers nothing")
        XCTAssertFalse(model.isSharing)
    }

    func testMultipleItemsShareInOneSession() {
        let model = makeModel()
        defer { model.reset() }
        let service = ScriptedSharingService()
        let sharing = sharing([service, ScriptedSharingService()])
        XCTAssertEqual(sharing.airDrop(files + files, from: nil, interaction: model.auxiliaryInteractionHandler), .presented)
        XCTAssertEqual(service.performedItems.map(\.count), [4])
        service.cancel()
        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
    }

    func testSheetTornDownWithoutACallbackStillReleasesOwnership() {
        let model = makeModel()
        defer { model.reset() }
        let service = ScriptedSharingService()
        let sharing = sharing([service])
        XCTAssertEqual(sharing.airDrop(files, from: nil, interaction: model.auxiliaryInteractionHandler), .presented)
        let center = NotificationCenter.default
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless],
                             backing: .buffered, defer: false)
        let companion = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless],
                                 backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        companion.isReleasedWhenClosed = false
        defer { sheet.orderOut(nil); companion.orderOut(nil) }
        [sheet, companion].forEach { $0.orderFrontRegardless() }
        center.post(name: NSWindow.didBecomeKeyNotification, object: sheet)
        center.post(name: NSWindow.didBecomeKeyNotification, object: companion)
        center.post(name: NSWindow.didResignKeyNotification, object: companion)
        XCTAssertTrue(sharing.isActive, "Focus moving between the sheet's own windows is not an ending")
        center.post(name: NSWindow.willCloseNotification, object: sheet)
        XCTAssertTrue(sharing.isActive, "One sheet window closing while a companion is still up")
        companion.orderOut(nil) // ShareKit orders companions out: no close notification.
        center.post(name: NSWindow.didChangeOcclusionStateNotification, object: companion)
        XCTAssertFalse(sharing.isActive)
        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
        service.complete() // The late callback, if it ever comes, is ignored.
        XCTAssertFalse(model.isAuxiliaryInteractionPresented)
    }

    func testHeldSessionAfterAirDropClosesOnOutsideClickAndHoverResumes() async throws {
        for exit in ["outsideClick", "hover"] {
            let clock = ControlledAppClock()
            let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
            defer { model.reset() }
            model.pageModel.selectedPage = .shelf
            let service = ScriptedSharingService()
            let sharing = sharing([service])
            XCTAssertEqual(sharing.airDrop(files, from: nil, interaction: model.auxiliaryInteractionHandler), .presented)
            service.cancel()
            XCTAssertTrue(model.isHeldAfterSystemPresentation)
            XCTAssertEqual(model.pageModel.selectedPage, .shelf)
            if exit == "outsideClick" {
                XCTAssertFalse(model.consumePointerClickForAuxiliaryInteraction())
                XCTAssertTrue(model.collapsesOnOutsideClick)
                model.collapse()
            } else {
                model.setHovered(true)
                model.setHovered(false)
                await waitForPendingSleep(clock)
                await clock.releaseAll()
            }
            await waitUntil { model.visualState == .collapsed }
            XCTAssertEqual(model.visualState, .collapsed)
            XCTAssertFalse(model.isHeldAfterSystemPresentation)
        }
    }

    /// Bounded deterministic mix of every terminal path, rapid re-entry and stale callbacks.
    func testStressEveryCycleReturnsToZeroOwnership() {
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: ControlledAppClock())
        defer { model.reset() }
        let interaction = model.auxiliaryInteractionHandler
        let sharing = NativeFileSharing()
        var next: ScriptedSharingService?
        sharing.makeAirDropService = { next }
        var earlier: [ScriptedSharingService] = []
        let iterations = 2_000
        for iteration in 0..<iterations {
            let path = iteration % 6
            next = ScriptedSharingService(path == 3 ? .failsImmediately : (path == 4 ? .silent : .accepts))
            let service = next!
            let outcome = sharing.airDrop(files, from: nil, interaction: interaction)
            next = nil // Re-entry is refused while active and finds no service once a failed start ended.
            for _ in 0..<3 { _ = sharing.airDrop(files, from: nil, interaction: interaction) } // rapid re-entry
            earlier.suffix(3).forEach { $0.complete(); $0.cancel() } // stale generations
            if outcome == .presented {
                XCTAssertTrue(model.isAuxiliaryInteractionPresented)
                switch path {
                case 0, 2: service.cancel()
                case 1: service.complete()
                default: sharing.begin(window: nil, interaction: .init()).finish() // unrelated, inert
                         service.cancel()
                }
            }
            earlier.append(service)
            XCTAssertFalse(sharing.isActive, "iteration \(iteration)")
            XCTAssertFalse(model.isAuxiliaryInteractionPresented, "iteration \(iteration)")
        }
        XCTAssertEqual(earlier.map(\.performedItems.count).reduce(0, +), iterations, "One perform per cycle")
        XCTAssertTrue(model.isHeldAfterSystemPresentation, "Pointer stayed outside: the valid held state")
        XCTAssertFalse(model.consumePointerClickForAuxiliaryInteraction())
        XCTAssertTrue(model.collapsesOnOutsideClick)
        model.collapse()
        XCTAssertFalse(model.isHeldAfterSystemPresentation)
    }
}
