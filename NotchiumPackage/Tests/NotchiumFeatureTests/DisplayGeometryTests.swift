@testable import NotchiumDynamicIsland
import AppKit
import SwiftUI
import XCTest

final class DisplaySelectionTests: XCTestCase {
    func testBuiltInPhysicalNotchWinsOverPrimaryExternalDisplay() {
        let placement = NotchiumDisplaySelectionPolicy.select(from: [
            externalDisplay(primary: true),
            builtInDisplay(primary: false),
        ])

        XCTAssertEqual(placement?.display.id, NotchiumDisplayID(rawValue: 1))
        XCTAssertEqual(placement?.mode, .physicalNotch)
    }

    func testExternalOnlyConfigurationUsesPrimaryVirtualPill() {
        let placement = NotchiumDisplaySelectionPolicy.select(from: [
            externalDisplay(id: 2, primary: false),
            externalDisplay(id: 3, primary: true),
        ])

        XCTAssertEqual(placement?.display.id, NotchiumDisplayID(rawValue: 3))
        XCTAssertEqual(placement?.mode, .virtualPill)
    }

    func testMouseDisplayWinsOverPrimaryForVirtualPill() {
        let placement = NotchiumDisplaySelectionPolicy.select(from: [
            externalDisplay(id: 2, primary: true),
            NotchiumDisplaySnapshot(
                id: NotchiumDisplayID(rawValue: 3),
                name: "Pointer display",
                frame: CGRect(x: 1920, y: 0, width: 1728, height: 1117),
                isBuiltIn: false,
                isPrimary: false,
                containsMousePointer: true
            ),
        ])

        XCTAssertEqual(placement?.display.id, NotchiumDisplayID(rawValue: 3))
        XCTAssertEqual(placement?.mode, .virtualPill)
    }

    func testFirstDisplayIsSafeFallbackWhenNoDisplayIsMarkedPrimary() {
        let placement = NotchiumDisplaySelectionPolicy.select(from: [
            externalDisplay(id: 8, primary: false),
            externalDisplay(id: 9, primary: false),
        ])

        XCTAssertEqual(placement?.display.id, NotchiumDisplayID(rawValue: 8))
    }

    func testDisplayIdentityIsStableAcrossGeometryChanges() {
        let first = externalDisplay(id: 42)
        let scaled = externalDisplay(
            id: 42,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertEqual(first.id, scaled.id)
        XCTAssertNotEqual(first.frame, scaled.frame)
    }

    func testNoDisplaysProducesMenuOnlyFallback() {
        XCTAssertNil(NotchiumDisplaySelectionPolicy.select(from: []))
    }
}

final class NotchGeometryResolverTests: XCTestCase {
    func testPhysicalGeometryUsesAuxiliaryNotchGapAndTopAnchor() {
        let display = builtInDisplay()
        let placement = NotchShellPlacement(display: display, mode: .physicalNotch)
        let layout = NotchGeometryResolver.layout(for: placement, state: .collapsed)

        XCTAssertEqual(layout.surfaceSize, CGSize(width: 212, height: 38))
        XCTAssertEqual(layout.panelFrame.midX, display.frame.midX, accuracy: 0.001)
        XCTAssertEqual(layout.panelFrame.maxY, display.frame.maxY, accuracy: 0.001)
        XCTAssertEqual(layout.hardwareNotchGeometry?.frame, layout.collapsedVisibleFrame)
        XCTAssertEqual(layout.visibleSurfaceFrame, layout.collapsedVisibleFrame)
        XCTAssertEqual(layout.panelFrame.size, CGSize(width: 640, height: 210))
        XCTAssertTrue(layout.hasHardwareNotch)
        XCTAssertEqual(layout.collapsedVisibleFrame.height, display.safeAreaInsets.top)
        XCTAssertEqual(layout.collapsedVisibleFrame.minX, display.auxiliaryTopLeftArea?.maxX)
        XCTAssertEqual(layout.collapsedVisibleFrame.maxX, display.auxiliaryTopRightArea?.minX)
        XCTAssertEqual(layout.collapsedVisibleFrame.maxY, display.frame.maxY, accuracy: 0.001)
    }

    func testMissingAuxiliaryAreasFallBackToVirtualNotchGeometry() {
        let display = builtInDisplay(includeAuxiliaryAreas: false)
        let placement = NotchShellPlacement(display: display, mode: .physicalNotch)
        let layout = NotchGeometryResolver.layout(for: placement, state: .collapsed)

        XCTAssertNil(layout.hardwareNotchGeometry)
        XCTAssertFalse(layout.hasHardwareNotch)
        XCTAssertEqual(layout.surfaceSize, CGSize(width: 180, height: 24))
    }

    func testVirtualPillUsesAbsoluteTopEdge() {
        let display = externalDisplay()
        let placement = NotchShellPlacement(display: display, mode: .virtualPill)
        let layout = NotchGeometryResolver.layout(for: placement, state: .collapsed)

        XCTAssertEqual(layout.surfaceSize, CGSize(width: 180, height: 24))
        XCTAssertEqual(layout.panelFrame.midX, display.frame.midX, accuracy: 0.001)
        XCTAssertEqual(layout.panelFrame.maxY, display.frame.maxY, accuracy: 0.001)
        XCTAssertNil(layout.hardwareNotchGeometry)
        XCTAssertEqual(layout.panelFrame.size, CGSize(width: 640, height: 210))
        XCTAssertEqual(layout.visibleSurfaceFrame, layout.collapsedVisibleFrame)
    }

    func testPhysicalNotchUsesActualAuxiliaryGapCenterInsteadOfDisplayCenter() {
        let frame = CGRect(x: 100, y: 50, width: 1600, height: 1000)
        let display = NotchiumDisplaySnapshot(
            id: NotchiumDisplayID(rawValue: 77),
            name: "Asymmetric notch fixture",
            frame: frame,
            safeAreaInsets: NotchiumDisplayInsets(top: 36),
            auxiliaryTopLeftArea: CGRect(x: 100, y: 1014, width: 630, height: 36),
            auxiliaryTopRightArea: CGRect(x: 950, y: 1014, width: 750, height: 36),
            isBuiltIn: true,
            isPrimary: true
        )
        let layout = NotchGeometryResolver.layout(
            for: NotchShellPlacement(display: display, mode: .physicalNotch),
            state: .collapsed
        )

        XCTAssertEqual(layout.collapsedVisibleFrame, CGRect(x: 730, y: 1014, width: 220, height: 36))
        XCTAssertEqual(layout.visibleSurfaceFrame, layout.collapsedVisibleFrame)
        XCTAssertNotEqual(layout.collapsedVisibleFrame.midX, display.frame.midX)
    }

    func testCollapsedPhysicalSurfaceNeverExtendsBelowHardwareSafeArea() {
        let display = builtInDisplay()
        let layout = NotchGeometryResolver.layout(
            for: NotchShellPlacement(display: display, mode: .physicalNotch),
            state: .collapsed
        )

        XCTAssertEqual(layout.collapsedVisibleFrame.minY, display.frame.maxY - display.safeAreaInsets.top)
        XCTAssertEqual(layout.collapsedVisibleFrame.height, display.safeAreaInsets.top)
    }

    func testExpandedSurfaceGrowsDownwardAndOutwardFromCollapsedOrigin() {
        let placement = NotchShellPlacement(display: builtInDisplay(), mode: .physicalNotch)
        let collapsed = NotchGeometryResolver.layout(for: placement, state: .collapsed)
        let expanded = NotchGeometryResolver.layout(for: placement, state: .expanded)

        XCTAssertEqual(expanded.panelFrame.maxY, collapsed.panelFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(expanded.panelFrame.midX, collapsed.panelFrame.midX, accuracy: 0.001)
        XCTAssertGreaterThan(expanded.visibleSurfaceFrame.width, collapsed.visibleSurfaceFrame.width)
        XCTAssertGreaterThan(expanded.visibleSurfaceFrame.height, collapsed.visibleSurfaceFrame.height)
    }

    func testVirtualNotchHeightUsesAvailableMenuBarRegion() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let display = NotchiumDisplaySnapshot(
            id: NotchiumDisplayID(rawValue: 88),
            name: "Menu bar fixture",
            frame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1054),
            isBuiltIn: false,
            isPrimary: true
        )
        let layout = NotchGeometryResolver.layout(
            for: NotchShellPlacement(display: display, mode: .virtualPill),
            state: .collapsed
        )

        XCTAssertEqual(layout.collapsedVisibleFrame.height, 26)
        XCTAssertEqual(layout.collapsedVisibleFrame.maxY, frame.maxY)
        XCTAssertGreaterThanOrEqual(layout.collapsedVisibleFrame.minY, display.visibleFrame.maxY)
    }

    func testVirtualNotchHeightUsesStatusBarThicknessAsMinimum() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let display = NotchiumDisplaySnapshot(
            id: NotchiumDisplayID(rawValue: 89),
            name: "Auto-hidden menu bar fixture",
            frame: frame,
            visibleFrame: frame,
            isBuiltIn: false,
            isPrimary: true,
            statusBarThickness: 25
        )
        let layout = NotchGeometryResolver.layout(
            for: NotchShellPlacement(display: display, mode: .virtualPill),
            state: .collapsed
        )

        XCTAssertEqual(layout.collapsedVisibleFrame, CGRect(x: 870, y: 1055, width: 180, height: 25))
    }

    func testCollapsedHoverFrameAddsFivePointsAtSidesAndBottom() {
        let layout = NotchGeometryResolver.layout(
            for: NotchShellPlacement(display: builtInDisplay(), mode: .physicalNotch),
            state: .collapsed
        )

        XCTAssertEqual(
            layout.collapsedHoverFrame,
            CGRect(
                x: layout.collapsedVisibleFrame.minX - 5,
                y: layout.collapsedVisibleFrame.minY - 5,
                width: layout.collapsedVisibleFrame.width + 10,
                height: layout.collapsedVisibleFrame.height + 5
            )
        )
        XCTAssertTrue(
            NotchHoverRegion.contains(
                CGPoint(x: layout.collapsedHoverFrame.maxX, y: layout.collapsedHoverFrame.maxY),
                in: layout.collapsedHoverFrame
            )
        )
        XCTAssertFalse(
            NotchHoverRegion.contains(
                CGPoint(x: layout.collapsedHoverFrame.maxX + 0.001, y: layout.collapsedHoverFrame.maxY),
                in: layout.collapsedHoverFrame
            )
        )
    }

    func testEveryModeAndPresentationStateSharesDisplayTopAndHorizontalCenter() {
        let displays = [
            builtInDisplay(frame: CGRect(x: -1512, y: 144, width: 1512, height: 982)),
            externalDisplay(frame: CGRect(x: 384, y: -120, width: 1728, height: 1117)),
        ]
        let placements = [
            NotchShellPlacement(display: displays[0], mode: .physicalNotch),
            NotchShellPlacement(display: displays[1], mode: .virtualPill),
        ]

        for placement in placements {
            let collapsedPanelFrame = NotchGeometryResolver.layout(
                for: placement,
                state: .collapsed
            ).panelFrame
            for state in NotchStableState.allCases {
                let layout = NotchGeometryResolver.layout(for: placement, state: state)
                XCTAssertEqual(layout.panelFrame, collapsedPanelFrame)
                XCTAssertEqual(
                    layout.panelFrame.maxY,
                    placement.display.frame.maxY,
                    accuracy: 0.001,
                    "\(placement.mode) \(state) must remain top anchored"
                )
                XCTAssertEqual(
                    layout.panelFrame.midX,
                    placement.display.frame.midX,
                    accuracy: 0.001,
                    "\(placement.mode) \(state) must remain centered"
                )
            }
        }
    }

    func testBackingScaleDoesNotChangePointBasedTopAnchor() {
        let frame = CGRect(x: 90, y: 220, width: 1440, height: 900)
        let standard = NotchiumDisplaySnapshot(
            id: NotchiumDisplayID(rawValue: 10),
            name: "Standard scale",
            frame: frame,
            isBuiltIn: false,
            isPrimary: true,
            backingScaleFactor: 1
        )
        let retina = NotchiumDisplaySnapshot(
            id: NotchiumDisplayID(rawValue: 11),
            name: "Retina scale",
            frame: frame,
            isBuiltIn: false,
            isPrimary: true,
            backingScaleFactor: 2
        )

        let standardLayout = NotchGeometryResolver.layout(
            for: NotchShellPlacement(display: standard, mode: .virtualPill),
            state: .expanded
        )
        let retinaLayout = NotchGeometryResolver.layout(
            for: NotchShellPlacement(display: retina, mode: .virtualPill),
            state: .expanded
        )

        XCTAssertEqual(standardLayout.panelFrame, retinaLayout.panelFrame)
        XCTAssertEqual(retinaLayout.panelFrame.maxY, frame.maxY, accuracy: 0.001)
    }

    func testEveryPresentationStateUsesContractDimensions() {
        let physical = NotchShellPlacement(display: builtInDisplay(), mode: .physicalNotch)
        let virtual = NotchShellPlacement(display: externalDisplay(), mode: .virtualPill)

        XCTAssertEqual(
            NotchGeometryResolver.layout(for: physical, state: .hovered).surfaceSize,
            CGSize(width: 450, height: 190)
        )
        XCTAssertEqual(
            NotchGeometryResolver.layout(for: virtual, state: .hovered).surfaceSize,
            CGSize(width: 450, height: 190)
        )
        XCTAssertEqual(
            NotchGeometryResolver.layout(for: physical, state: .expanded).surfaceSize,
            CGSize(width: 450, height: 190)
        )
        XCTAssertEqual(
            NotchGeometryResolver.layout(for: virtual, state: .expanded).surfaceSize,
            CGSize(width: 450, height: 190)
        )
    }

    func testStageTwoReferenceDisplayUsesExactFixedPanelFrame() {
        let display = externalDisplay(
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956)
        )
        let layout = NotchGeometryResolver.layout(
            for: NotchShellPlacement(display: display, mode: .virtualPill),
            state: .expanded
        )

        XCTAssertEqual(layout.panelFrame, CGRect(x: 415, y: 746, width: 640, height: 210))
        XCTAssertEqual(layout.panelFrame.maxY, 956)
    }

    func testSmallDisplaysRetainTheFixedHostPanelContract() {
        let display = externalDisplay(
            frame: CGRect(x: 0, y: 0, width: 300, height: 180)
        )
        let placement = NotchShellPlacement(display: display, mode: .virtualPill)
        let layout = NotchGeometryResolver.layout(for: placement, state: .expanded)

        XCTAssertEqual(layout.panelFrame.size, CGSize(width: 640, height: 210))
        XCTAssertEqual(layout.panelFrame.midX, display.frame.midX, accuracy: 0.001)
        XCTAssertEqual(layout.panelFrame.maxY, display.frame.maxY, accuracy: 0.001)
    }

    func testExtremelySmallDisplayNeverProducesNegativeDimensions() {
        let display = externalDisplay(
            frame: CGRect(x: 0, y: 0, width: 20, height: 20)
        )
        let placement = NotchShellPlacement(display: display, mode: .virtualPill)
        let layout = NotchGeometryResolver.layout(for: placement, state: .expanded)

        XCTAssertGreaterThan(layout.panelFrame.width, 0)
        XCTAssertGreaterThan(layout.panelFrame.height, 0)
        XCTAssertEqual(layout.panelFrame.size, CGSize(width: 640, height: 210))
        XCTAssertEqual(layout.panelFrame.midX, display.frame.midX, accuracy: 0.001)
        XCTAssertEqual(layout.panelFrame.maxY, display.frame.maxY, accuracy: 0.001)
    }
}

final class NotchPanelTests: XCTestCase {
    @MainActor
    func testActualAppKitPanelFrameReachesSelectedScreenTop() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 210),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.applyNotchWindowBehavior()
        let controller = NotchiumPanelController(
            model: DynamicIslandPresentationModel(clock: ControlledAppClock())
        )

        controller.positionPanel(panel, on: screen)
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }

        XCTAssertEqual(panel.frame.size, CGSize(width: 640, height: 210))
        XCTAssertEqual(panel.frame.midX, screen.frame.midX, accuracy: 0.001)
        XCTAssertEqual(panel.frame.maxY, screen.frame.maxY, accuracy: 0.001)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(
            panel.collectionBehavior,
            [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        )
        XCTAssertEqual(panel.animationBehavior, .none)
    }
}

final class NotchShapeTests: XCTestCase {
    func testShapeOwnsCollapsedWidthHeightAndTopAnchorInsideFixedPanel() {
        let shape = NotchShape(
            width: 212,
            height: 38,
            centerX: 320,
            topCornerRadius: 0,
            bottomCornerRadius: 8
        )

        XCTAssertEqual(
            shape.path(in: CGRect(x: 0, y: 0, width: 640, height: 210)).boundingRect,
            CGRect(x: 214, y: 0, width: 212, height: 38)
        )
    }

    func testAllShapeGeometryParticipatesInOneAnimationVector() {
        var shape = NotchShape(
            width: 212,
            height: 38,
            centerX: 300,
            topCornerRadius: 0,
            bottomCornerRadius: 8
        )

        shape.animatableData = AnimatablePair(
            AnimatablePair(450, 190),
            AnimatablePair(320, AnimatablePair(12, 26))
        )

        XCTAssertEqual(shape.width, 450)
        XCTAssertEqual(shape.height, 190)
        XCTAssertEqual(shape.centerX, 320)
        XCTAssertEqual(shape.topCornerRadius, 12)
        XCTAssertEqual(shape.bottomCornerRadius, 26)
    }
}

final class NotchShellConfigurationTests: XCTestCase {
    func testSystemAccessibilityValuesFlowThroughAutomaticConfiguration() {
        let resolved = NotchShellAccessibilityConfiguration.resolve(
            renderConfiguration: .automatic,
            systemReduceMotion: true,
            systemReduceTransparency: true,
            systemIncreaseContrast: true
        )

        XCTAssertEqual(
            resolved,
            NotchShellAccessibilityConfiguration(
                reduceMotion: true,
                reduceTransparency: true,
                increaseContrast: true
            )
        )
    }

    func testDebugOverridesCanForceMotionAndTransparencyEitherWay() {
        let forcedOn = NotchShellAccessibilityConfiguration.resolve(
            renderConfiguration: NotchShellRenderConfiguration(
                reduceMotion: .on,
                reduceTransparency: .on
            ),
            systemReduceMotion: false,
            systemReduceTransparency: false,
            systemIncreaseContrast: false
        )
        let forcedOff = NotchShellAccessibilityConfiguration.resolve(
            renderConfiguration: NotchShellRenderConfiguration(
                reduceMotion: .off,
                reduceTransparency: .off
            ),
            systemReduceMotion: true,
            systemReduceTransparency: true,
            systemIncreaseContrast: false
        )

        XCTAssertTrue(forcedOn.reduceMotion)
        XCTAssertTrue(forcedOn.reduceTransparency)
        XCTAssertFalse(forcedOff.reduceMotion)
        XCTAssertFalse(forcedOff.reduceTransparency)
    }
}
