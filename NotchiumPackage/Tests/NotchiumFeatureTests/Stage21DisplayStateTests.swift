import Foundation
@testable import NotchiumDynamicIsland
import XCTest

final class Stage21DisplayStateTests: XCTestCase {
    func testTopologyDisconnectClamshellReturnAndGeometryInvalidation() {
        var state = DisplayPresentationState()
        let builtIn = builtInDisplay()
        let external = externalDisplay(id: 2, frame: CGRect(x: 1512, y: -100, width: 1920, height: 1080))
        var evidence = DisplayInteractionEvidence(pointerLocation: CGPoint(x: 100, y: 100))
        state.rebuild([builtIn], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, builtIn.id)
        XCTAssertNotNil(state.shellPlacement)
        state.rebuild([builtIn, external], evidence: evidence)
        evidence.pointerLocation = CGPoint(x: 2000, y: 100)
        state.resolve(evidence)
        XCTAssertEqual(state.ownedDisplayID, external.id)
        XCTAssertNil(state.shellPlacement)
        XCTAssertNil(state.geometry?.physicalNotchGap)
        state.interact(on: external.id, evidence: evidence)
        state.rebuild([builtIn], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, builtIn.id)
        state.rebuild([external], evidence: evidence) // Clamshell
        XCTAssertEqual(state.ownedDisplayID, external.id)
        state.rebuild([builtIn, external], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, external.id)
        let generation = state.topologyGeneration
        state.rebuild([builtIn, external], evidence: evidence)
        XCTAssertEqual(state.topologyGeneration, generation)
        let rearranged = externalDisplay(id: 2, frame: CGRect(x: -1080, y: 300, width: 1080, height: 1920))
        state.rebuild([builtIn, rearranged], evidence: evidence)
        XCTAssertEqual(state.topologyGeneration, generation + 1)
        XCTAssertEqual(state.geometry?.frame, rearranged.frame)
        let scaled = NotchiumDisplaySnapshot(id: rearranged.id, name: rearranged.name,
            frame: rearranged.frame, visibleFrame: rearranged.frame.insetBy(dx: 0, dy: 24),
            isBuiltIn: false, isPrimary: true, backingScaleFactor: 1)
        state.rebuild([builtIn, scaled], evidence: evidence)
        XCTAssertEqual(state.topologyGeneration, generation + 2)
        XCTAssertEqual(state.geometry?.backingScaleFactor, 1)
        XCTAssertEqual(state.geometry?.menuBarHeight, 24)
        XCTAssertEqual(state.geometry?.topCenterAnchor, CGPoint(x: scaled.frame.midX, y: scaled.frame.maxY))
        state.rebuild([], evidence: evidence)
        XCTAssertNil(state.ownedDisplayID)
        XCTAssertNil(state.geometry)
    }

    func testDirectOwnershipWinsUntilSessionEndsAndFallbackIsCentralized() {
        var state = DisplayPresentationState()
        let builtIn = builtInDisplay()
        let external = externalDisplay(id: 2, frame: CGRect(x: 1512, y: 0, width: 1440, height: 900))
        var evidence = DisplayInteractionEvidence(frontmostDisplayID: external.id)
        state.rebuild([builtIn, external], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, external.id)
        state.interact(on: builtIn.id, evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, builtIn.id)
        evidence.pointerLocation = CGPoint(x: external.frame.midX, y: external.frame.midY)
        state.resolve(evidence)
        XCTAssertEqual(state.ownedDisplayID, builtIn.id)
        state.releaseDirectOwnership()
        state.resolve(evidence)
        XCTAssertEqual(state.ownedDisplayID, external.id)
        state.rebuild([builtIn], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, builtIn.id)
    }

    func testRecycledOnlineIDCannotRetainAnotherMonitorsDirectLease() {
        var state = DisplayPresentationState()
        let first = NotchiumDisplaySnapshot(id: .init(rawValue: 1), name: "First", frame: builtInDisplay().frame,
            isBuiltIn: true, isPrimary: true, persistentID: UUID())
        let replacement = NotchiumDisplaySnapshot(id: first.id, name: "Replacement", frame: first.frame,
            isBuiltIn: false, isPrimary: true, persistentID: UUID())
        let external = externalDisplay(id: 2)
        let evidence = DisplayInteractionEvidence(frontmostDisplayID: external.id)
        state.rebuild([first, external], evidence: evidence)
        state.interact(on: first.id, evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, first.id)
        state.rebuild([replacement, external], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, external.id)
    }

    func testFullscreenIsDisplayScopedMaximizedIsNormalAndSleepInvalidates() {
        var state = DisplayPresentationState()
        let builtIn = builtInDisplay()
        let external = externalDisplay(id: 2, frame: CGRect(x: 1512, y: 0, width: 1440, height: 900))
        var evidence = DisplayInteractionEvidence(frontmostDisplayID: builtIn.id)
        state.rebuild([builtIn, external], evidence: evidence)
        XCTAssertEqual(state.presentationContext, .normal) // Geometry alone is not fullscreen.
        evidence.isFullscreen = true
        evidence.fullscreenDisplayID = builtIn.id
        state.resolve(evidence)
        XCTAssertEqual(state.presentationContext, .fullscreenApp)
        evidence.isPresentationLike = true
        state.resolve(evidence)
        XCTAssertEqual(state.presentationContext, .presentationLike)
        evidence.pointerLocation = CGPoint(x: external.frame.midX, y: external.frame.midY)
        state.resolve(evidence)
        XCTAssertEqual(state.presentationContext, .normal)
        let generation = state.topologyGeneration
        state.setSleeping(true, evidence: evidence)
        XCTAssertEqual(state.presentationContext, .sleeping)
        XCTAssertGreaterThan(state.topologyGeneration, generation)
        state.setSleeping(false, evidence: evidence)
        evidence.isFullscreen = false
        evidence.isPresentationLike = false
        state.resolve(evidence)
        XCTAssertEqual(state.presentationContext, .normal)
    }
}
