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
        state.rebuild([builtIn, external], evidence: evidence)
        evidence.pointerLocation = CGPoint(x: 2000, y: 100)
        state.resolve(evidence)
        XCTAssertEqual(state.ownedDisplayID, builtIn.id, "Pointer movement must never hide the MacBook notch")
        state.rebuild([external], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, external.id)
        XCTAssertEqual(state.shellPlacement?.mode, .virtualPill)
        state.rebuild([builtIn, external], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, builtIn.id, "Opening the lid restores the default")
        let generation = state.topologyGeneration
        state.rebuild([builtIn, external], evidence: evidence)
        XCTAssertEqual(state.topologyGeneration, generation)
        let rearranged = externalDisplay(id: 2, frame: CGRect(x: -1080, y: 300, width: 1080, height: 1920))
        state.preferences.selection = .selected
        state.preferences.selectedDisplayKey = external.selectionKey
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

    func testDefaultIgnoresPointerFrontmostAndPrimaryExternalDisplay() {
        var state = DisplayPresentationState()
        let builtIn = builtInDisplay(primary: false)
        let external = externalDisplay(id: 2, frame: CGRect(x: 1512, y: 0, width: 1440, height: 900))
        let evidence = DisplayInteractionEvidence(pointerLocation: CGPoint(x: 1800, y: 500),
                                                  frontmostDisplayID: external.id)
        state.rebuild([external, builtIn], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, builtIn.id)
        XCTAssertEqual(state.shellPlacement?.mode, .physicalNotch)
        state.preferences.selection = .selected
        state.preferences.selectedDisplayKey = external.selectionKey
        state.resolve(evidence)
        XCTAssertEqual(state.ownedDisplayID, external.id)
        state.rebuild([builtIn], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, builtIn.id)
        state.rebuild([external, builtIn], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, external.id)
    }

    func testPersistentSelectionSurvivesChangedOnlineIDAndRejectsRecycledID() {
        var state = DisplayPresentationState()
        let uuid = UUID()
        let first = NotchiumDisplaySnapshot(id: .init(rawValue: 2), name: "Monitor", frame: externalDisplay().frame,
            isBuiltIn: false, isPrimary: true, persistentID: uuid)
        let replacement = NotchiumDisplaySnapshot(id: first.id, name: "Different monitor", frame: first.frame,
            isBuiltIn: false, isPrimary: true, persistentID: UUID())
        let reconnected = NotchiumDisplaySnapshot(id: .init(rawValue: 9), name: first.name, frame: first.frame,
            isBuiltIn: false, isPrimary: false, persistentID: uuid)
        state.preferences.selection = .selected
        state.preferences.selectedDisplayKey = first.selectionKey
        let evidence = DisplayInteractionEvidence()
        state.rebuild([first, builtInDisplay()], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, first.id)
        state.rebuild([replacement, builtInDisplay()], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, builtInDisplay().id)
        state.rebuild([replacement, reconnected, builtInDisplay()], evidence: evidence)
        XCTAssertEqual(state.ownedDisplayID, reconnected.id)
    }

    func testFullscreenIsDisplayScopedMaximizedIsNormalAndSleepInvalidates() {
        var state = DisplayPresentationState()
        let builtIn = builtInDisplay()
        let external = externalDisplay(id: 2, frame: CGRect(x: 1512, y: 0, width: 1440, height: 900))
        var evidence = DisplayInteractionEvidence(frontmostDisplayID: builtIn.id)
        state.rebuild([builtIn, external], evidence: evidence)
        XCTAssertEqual(state.presentationContext, .normal)
        evidence.isFullscreen = true
        evidence.fullscreenDisplayID = builtIn.id
        state.resolve(evidence)
        XCTAssertEqual(state.presentationContext, .fullscreenApp)
        evidence.isPresentationLike = true
        state.resolve(evidence)
        XCTAssertEqual(state.presentationContext, .presentationLike)
        XCTAssertEqual(state.context(for: external.id, evidence: evidence), .normal)
        evidence.fullscreenDisplayID = external.id
        state.resolve(evidence)
        XCTAssertEqual(state.presentationContext, .normal)
        let generation = state.topologyGeneration
        state.setSleeping(true, evidence: evidence)
        XCTAssertEqual(state.presentationContext, .sleeping)
        XCTAssertGreaterThan(state.topologyGeneration, generation)
        state.setSleeping(false, evidence: evidence)
        XCTAssertEqual(state.presentationContext, .normal)
    }
}
