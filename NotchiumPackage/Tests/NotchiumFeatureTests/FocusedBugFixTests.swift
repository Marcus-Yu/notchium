import AppKit
import SwiftUI
import XCTest
import NotchiumCore
@testable import NotchiumDynamicIsland
@testable import NotchiumServices
@testable import NotchiumShelfFeature

@MainActor
final class FocusedBugFixTests: XCTestCase {
    func testAirDropUsesStandaloneWindowAndShareKeepsSourceWindow() throws {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.applyNotchWindowBehavior()
        let model = DynamicIslandPresentationModel(phase: .expanded)
        defer { model.reset() }
        let sharing = NativeFileSharing()
        sharing.begin(window: panel, interaction: model.auxiliaryInteractionHandler)
        let airDrop = try XCTUnwrap(NSSharingService(named: .sendViaAirDrop))
        let share = NSSharingService(title: "Test Share", image: NSImage(), alternateImage: nil) {}
        var scope = NSSharingService.SharingContentScope.item
        XCTAssertNil(sharing.sharingService(airDrop, sourceWindowForShareItems: [], sharingContentScope: &scope))
        XCTAssertTrue(sharing.sharingService(share, sourceWindowForShareItems: [], sharingContentScope: &scope) === panel)
        sharing.sharingService(share, didShareItems: [])
        XCTAssertEqual(panel.level, NotchPanel.restingLevel)
    }

    func testAirDropCancelAndCompletionReturnToSameHoveredPage() async throws {
        for completed in [false, true] {
            let clock = ControlledAppClock()
            let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
            defer { model.reset() }
            model.pageModel.selectedPage = .shelf
            let sharing = NativeFileSharing()
            sharing.begin(window: nil, interaction: model.auxiliaryInteractionHandler, returnsToOpenSession: true)
            model.setHovered(true)
            model.setHovered(false)
            // A native Cancel click is consumed synchronously before its delegate runs.
            XCTAssertTrue(model.consumePointerClickForAuxiliaryInteraction())
            let service = try XCTUnwrap(NSSharingService(named: .sendViaAirDrop))
            if completed { sharing.sharingService(service, didShareItems: []) }
            else { sharing.sharingService(service, didFailToShareItems: [], error: CocoaError(.userCancelled)) }
            await drainMainActorTasks()
            XCTAssertFalse(model.isAuxiliaryInteractionPresented)
            XCTAssertEqual(model.visualState, .hovered)
            XCTAssertEqual(model.pageModel.selectedPage, .shelf)
            let sleepers = await clock.pendingCount()
            XCTAssertEqual(sleepers, 0, "Lease dismissal is not a new hover exit")
            // A fresh pointer boundary resumes the ordinary hover lifecycle.
            model.setHovered(true)
            model.setHovered(false)
            await waitForPendingSleep(clock)
            await clock.releaseAll()
            await waitUntil { model.visualState == .collapsed }
            XCTAssertEqual(model.visualState, .collapsed)
        }
    }

    func testAirDropReturnPolicySurvivesAnotherOverlappingLease() async {
        let clock = ControlledAppClock()
        let model = DynamicIslandPresentationModel(phase: .hovered, clock: clock)
        defer { model.reset() }
        let interaction = model.auxiliaryInteractionHandler
        interaction.begin(source: "other")
        interaction.beginNativeSharing(in: nil, source: "airdrop")
        interaction.endNativeSharing(in: nil, source: "airdrop", returnsToOpenSession: true)
        XCTAssertTrue(model.isAuxiliaryInteractionPresented)
        interaction.end(actionSelected: false, source: "other")
        await drainMainActorTasks()
        XCTAssertEqual(model.visualState, .hovered)
        let sleepers = await clock.pendingCount()
        XCTAssertEqual(sleepers, 0)
    }

    func testExpandedMinorEventsKeepPagesAndCoalesceIdentity() {
        for page: NotchPage in [.home, .music, .shelf, .calendar] {
            let model = DynamicIslandPresentationModel(phase: .expanded,
                clock: TestAppClock(now: .now, automaticallyAdvances: false))
            defer { model.reset() }
            model.pageModel.selectedPage = page
            model.showAudioHUD(.init(kind: .volume, deviceName: "Speakers", volume: 0.3, isMuted: false))
            let id = model.expandedMinorActivity?.id
            XCTAssertNotNil(id)
            for value in [0.4, 0.5, 0.7, 0.9] {
                model.showAudioHUD(.init(kind: .volume, deviceName: "Speakers", volume: value, isMuted: false))
                XCTAssertEqual(model.expandedMinorActivity?.id, id)
                XCTAssertEqual(model.pageModel.selectedPage, page)
                XCTAssertEqual(model.visualState, .expanded)
            }
            XCTAssertEqual(model.activityCoordinator.liveActivities.count, 1)
            XCTAssertNil(model.presentedNotification, "Collapsed HUD remains separate from the expanded projection")
            model.notificationCoordinator.dismiss()
            XCTAssertNil(model.expandedMinorActivity)
            XCTAssertEqual(model.pageModel.selectedPage, page)
            model.activityCoordinator.present(.init(id: UUID(), key: .init("system.brightness"), kind: .systemHUD,
                title: "Brightness 50%", subtitle: nil, duration: .milliseconds(1750)))
            XCTAssertEqual(model.expandedMinorActivity?.title, "Brightness 50%")
            XCTAssertEqual(model.pageModel.selectedPage, page)
        }
    }

    func testMinorExtensionIsOneOutlineAndPreservesOpenPageGate() {
        let layout = NotchGeometryResolver.layout(for: .init(display: builtInDisplay(), mode: .physicalNotch), state: .expanded)
        let passive = NotchShape(width: 212, height: 38, centerX: 370, topCornerRadius: 0, bottomCornerRadius: 8)
        let host = CGRect(origin: .zero, size: layout.panelFrame.size)
        for progress: CGFloat in [0, 0.1, 0.5, 1] {
            let shape = NotchShellSurface(width: 544, height: 266, centerX: 370, bottomRadius: 28,
                passiveShape: passive, shoulderRadius: 10, extensionHeight: 56 * progress)
            let path = shape.path(in: host)
            XCTAssertTrue(path.contains(CGPoint(x: 370, y: 240)))
            if progress > 0 {
                for y in stride(from: CGFloat(260), through: 266 + 56 * progress - 1, by: 1) {
                    XCTAssertTrue(path.contains(CGPoint(x: 370, y: y)), "Continuous page-to-extension fill")
                }
                XCTAssertFalse(path.contains(CGPoint(x: 180, y: 266 + 56 * progress / 2)))
            }
            let frame = NotchSurfaceFrame(shape: shape, phase: .expanded, expandedHeight: 266) { _ in Color.clear }
            XCTAssertEqual(frame.contentPhase, .expanded)
        }
        XCTAssertTrue(NotchTransitionSurface<Color>.preservesExpandedPage(expanded: true, wasExpanded: true))
        XCTAssertFalse(NotchTransitionSurface<Color>.preservesExpandedPage(expanded: true, wasExpanded: false))
        XCTAssertFalse(NotchTransitionSurface<Color>.preservesExpandedPage(expanded: false, wasExpanded: true))
        XCTAssertEqual(NotchExpandedMinorGeometry.frame(layout: layout).maxY, layout.visibleSurfaceFrame.minY)
    }

    func testMinorExpiryKeepsExpandedPageAndCollapsedBehavior() async {
        let clock = TestAppClock(now: .now, automaticallyAdvances: false)
        let model = DynamicIslandPresentationModel(phase: .expanded, clock: clock)
        defer { model.reset() }
        model.pageModel.selectedPage = .shelf
        model.showAudioHUD(.init(kind: .volume, deviceName: "Speakers", volume: 0.5, isMuted: false))
        await waitUntil { model.notificationCoordinator.expiresAt != nil }
        await clock.advance(by: .seconds(2))
        await waitUntil { model.expandedMinorActivity == nil }
        XCTAssertNil(model.expandedMinorActivity)
        XCTAssertEqual(model.pageModel.selectedPage, .shelf)
        XCTAssertEqual(model.visualState, .expanded)
        model.present(.collapsed, animated: false)
        model.showAudioHUD(.init(kind: .volume, deviceName: "Speakers", volume: 0.7, isMuted: false))
        XCTAssertNotNil(model.presentedNotification)
        XCTAssertNil(model.expandedMinorActivity)
    }

    func testRealKVOCompletionSurvivesImmediateCounterResetAndUnpublish() async {
        let service = RealFileTransferService(folders: [])
        let stream = await service.updates()
        var received: [TransferSnapshot] = []
        let collector = Task { @MainActor in
            for await snapshot in stream { received.append(snapshot) }
        }
        defer { collector.cancel() }
        let progresses = (0..<3).map { _ in progress() }
        let ids = progresses.map { service.published($0) }
        for (index, progress) in progresses.enumerated() {
            progress.completedUnitCount = 100
            // The publisher tears down counters before a queued KVO delivery/throttle runs.
            progress.completedUnitCount = 0
            progress.fileURL = URL(fileURLWithPath: "/tmp/same-name-final.zip")
            service.unpublished(progress, id: ids[index])
        }
        await waitUntil { received.filter { $0.phase.isTerminal }.count == 3 }
        XCTAssertEqual(Set(ids).count, 3, "Same filename and URL still have separate publication identities")
        for id in ids {
            let values = received.filter { $0.id == id }
            XCTAssertEqual(values.last?.phase, .completed)
            XCTAssertEqual(values.last?.fraction, 1)
            XCTAssertEqual(values.last?.fileURL?.lastPathComponent, "same-name-final.zip", "Final metadata is read after the browser rename")
            XCTAssertEqual(values.filter { $0.phase.isTerminal }.count, 1)
        }
    }

    func testRealKVOOneCancellationAndRepublishRejectOldGeneration() async {
        let service = RealFileTransferService(folders: [])
        let stream = await service.updates()
        var received: [TransferSnapshot] = []
        let collector = Task { @MainActor in
            for await snapshot in stream { received.append(snapshot) }
        }
        defer { collector.cancel() }
        let first = progress()
        let cancelled = progress()
        let firstID = service.published(first)
        XCTAssertEqual(service.published(first), firstID, "Repeated subscription callback is not a new transfer")
        let cancelledID = service.published(cancelled)
        first.completedUnitCount = 100
        cancelled.cancel()
        await drainMainActorTasks()
        XCTAssertFalse(received.contains { $0.phase.isTerminal }, "Completion/cancellation remains at the authoritative unpublish event")
        service.unpublished(first, id: firstID)
        service.unpublished(cancelled, id: cancelledID)
        first.completedUnitCount = 0
        let nextID = service.published(first)
        XCTAssertNotEqual(nextID, firstID)
        // A stale unpublishing callback must not tear down the new publication.
        service.unpublished(first, id: firstID)
        first.completedUnitCount = 100
        service.unpublished(first, id: nextID)
        await waitUntil { received.filter { $0.phase.isTerminal }.count == 3 }
        XCTAssertEqual(received.last { $0.id == firstID }?.phase, .completed)
        XCTAssertEqual(received.last { $0.id == cancelledID }?.phase, .stopped)
        XCTAssertEqual(received.last { $0.id == nextID }?.phase, .completed)
    }

    func testTransferReducerRejectsStaleAndCrossIdentityCallbacks() {
        let model = DynamicIslandPresentationModel(clock: TestAppClock(now: .now, automaticallyAdvances: false))
        defer { model.reset() }
        let transfers = TransferActivityModel(notifications: model.notificationCoordinator)
        for id in ["A", "B", "C"] { transfers.receive(snapshot(id, .active, at: 1)) }
        let activityID = model.activityCoordinator.primary?.id
        transfers.receive(snapshot("A", .active, at: 4, fraction: 0.7))
        transfers.receive(snapshot("A", .stopped, at: 2))
        XCTAssertEqual(transfers.active.first { $0.id == "A" }?.fraction, 0.7)
        for id in ["B", "A", "C"] { transfers.receive(snapshot(id, .completed, at: 5, fraction: 1)) }
        for id in ["A", "B", "C"] {
            transfers.receive(snapshot(id, .stopped, at: 6))
            transfers.receive(snapshot(id, .active, at: 7))
        }
        XCTAssertTrue(transfers.active.isEmpty)
        XCTAssertEqual(transfers.recent.count, 3)
        XCTAssertTrue(transfers.recent.allSatisfy { $0.phase == .completed })
        XCTAssertEqual(model.activityCoordinator.primary?.id, activityID)
        XCTAssertEqual(model.notificationCoordinator.active?.content.compactActivity?.trailing, .text("Done"))
        transfers.receive(snapshot("cancelled", .active, at: 1))
        transfers.receive(snapshot("cancelled", .stopped, at: 2))
        transfers.receive(snapshot("cancelled", .completed, at: 3, fraction: 1))
        XCTAssertEqual(transfers.recent.first?.phase, .stopped)
        XCTAssertEqual(model.notificationCoordinator.active?.content.compactActivity?.trailing, .text("Stopped"))
    }

    private func progress() -> Progress {
        let result = Progress(totalUnitCount: 100)
        result.kind = .file
        result.fileOperationKind = .downloading
        result.fileURL = URL(fileURLWithPath: "/tmp/same-name.zip")
        return result
    }

    private func snapshot(_ id: String, _ phase: TransferPhase, at time: TimeInterval, fraction: Double = 0.2) -> TransferSnapshot {
        .init(id: id, displayName: "same-name.zip", operation: .downloading, phase: phase, fraction: fraction,
              startedAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: time))
    }
}
