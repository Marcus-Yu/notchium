@testable import NotchiumDynamicIsland
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

        XCTAssertEqual(layout.surfaceSize, CGSize(width: 240, height: 48))
        XCTAssertEqual(layout.panelFrame.midX, display.frame.midX, accuracy: 0.001)
        XCTAssertEqual(layout.panelFrame.maxY, display.frame.maxY, accuracy: 0.001)
        XCTAssertEqual(layout.physicalBridgeSize, CGSize(width: 212, height: 38))
    }

    func testMissingAuxiliaryAreasUseClampedPercentageBridge() {
        let display = builtInDisplay(includeAuxiliaryAreas: false)
        let placement = NotchShellPlacement(display: display, mode: .physicalNotch)
        let layout = NotchGeometryResolver.layout(for: placement, state: .collapsed)

        XCTAssertEqual(layout.physicalBridgeSize?.width, 200)
        XCTAssertEqual(layout.surfaceSize.width, 240)
    }

    func testVirtualPillUsesAbsoluteTopEdge() {
        let display = externalDisplay()
        let placement = NotchShellPlacement(display: display, mode: .virtualPill)
        let layout = NotchGeometryResolver.layout(for: placement, state: .collapsed)

        XCTAssertEqual(layout.surfaceSize, CGSize(width: 220, height: 44))
        XCTAssertEqual(layout.panelFrame.midX, display.frame.midX, accuracy: 0.001)
        XCTAssertEqual(layout.panelFrame.maxY, display.frame.maxY, accuracy: 0.001)
        XCTAssertEqual(layout.topInset, 0)
        XCTAssertNil(layout.physicalBridgeSize)
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
            for state in NotchStableState.allCases {
                let layout = NotchGeometryResolver.layout(for: placement, state: state)
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
            CGSize(width: 272, height: 56)
        )
        XCTAssertEqual(
            NotchGeometryResolver.layout(for: virtual, state: .hovered).surfaceSize,
            CGSize(width: 272, height: 56)
        )
        XCTAssertEqual(
            NotchGeometryResolver.layout(for: physical, state: .expanded).surfaceSize,
            CGSize(width: 420, height: 260)
        )
        XCTAssertEqual(
            NotchGeometryResolver.layout(for: virtual, state: .expanded).surfaceSize,
            CGSize(width: 420, height: 260)
        )
    }

    func testSmallDisplaysClampExpandedPanelInsideMargins() {
        let display = externalDisplay(
            frame: CGRect(x: 0, y: 0, width: 300, height: 180)
        )
        let placement = NotchShellPlacement(display: display, mode: .virtualPill)
        let layout = NotchGeometryResolver.layout(for: placement, state: .expanded)

        XCTAssertGreaterThan(layout.panelFrame.width, 0)
        XCTAssertGreaterThan(layout.panelFrame.height, 0)
        XCTAssertGreaterThanOrEqual(layout.panelFrame.minX, display.frame.minX + 16)
        XCTAssertLessThanOrEqual(layout.panelFrame.maxX, display.frame.maxX - 16)
        XCTAssertGreaterThanOrEqual(layout.panelFrame.minY, display.frame.minY + 32)
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
        XCTAssertGreaterThanOrEqual(layout.panelFrame.minX, display.frame.minX)
        XCTAssertLessThanOrEqual(layout.panelFrame.maxX, display.frame.maxX)
        XCTAssertGreaterThanOrEqual(layout.panelFrame.minY, display.frame.minY)
        XCTAssertLessThanOrEqual(layout.panelFrame.maxY, display.frame.maxY)
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
