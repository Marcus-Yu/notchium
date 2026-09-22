@testable import NotchiumDynamicIsland
import SwiftUI
import XCTest

final class ExpandedTopSurfaceTests: XCTestCase {
    private let panel = CGRect(x: 0, y: 0, width: 640, height: 210)
    private let passive = NotchShape(
        width: 212, height: 38, centerX: 320,
        topCornerRadius: 0, bottomCornerRadius: 8,
        hardwareExclusion: CGRect(x: 214, y: 0, width: 212, height: 38)
    )

    func testExpandedSurfaceFillsFormerHardwareHoleAndShoulders() {
        let shape = NotchShellSurface(
            width: 450, height: 190, centerX: 320,
            bottomRadius: 28, passiveShape: passive
        )
        let path = shape.path(in: panel)
        XCTAssertEqual(path.boundingRect, CGRect(x: 95, y: 0, width: 450, height: 190))
        for x in stride(from: 95.5, through: 544.5, by: 1) {
            for y in stride(from: 0.5, through: 161.5, by: 1) {
                XCTAssertTrue(path.contains(CGPoint(x: x, y: y)))
            }
        }
        XCTAssertFalse(path.contains(CGPoint(x: 95.5, y: 189.5)))
        XCTAssertTrue(path.contains(CGPoint(x: 320, y: 189.5)))
    }

    func testPassiveEndpointAndClosingUndershootStayEmpty() {
        for delta in [CGFloat(0), -0.1] {
            let shape = NotchShellSurface(
                width: 212 + delta, height: 38 + delta, centerX: 320,
                bottomRadius: 8, passiveShape: passive
            )
            XCTAssertEqual(shape.path(in: panel), passive.path(in: panel))
            XCTAssertTrue(shape.path(in: panel).isEmpty)
        }
    }

    func testNativeInterpolationKeepsGrowingSurfaceSolidAndTopAttached() {
        var shape = NotchShellSurface(
            width: 212, height: 38, centerX: 320,
            bottomRadius: 8, passiveShape: passive
        )
        for step in (1...60).reversed() {
            let progress = CGFloat(step) / 60
            shape.animatableData = AnimatablePair(
                AnimatablePair(
                    AnimatablePair(212 + 238 * progress, 38 + 152 * progress),
                    AnimatablePair(320, 8 + 20 * progress)
                ),
                AnimatablePair(0, 0)
            )
            let path = shape.path(in: panel)
            XCTAssertEqual(path.boundingRect.minY, 0)
            XCTAssertTrue(path.contains(CGPoint(x: 320, y: 1)))
            XCTAssertTrue(path.contains(CGPoint(x: path.boundingRect.minX + 0.5, y: 1)))
            XCTAssertTrue(path.contains(CGPoint(x: path.boundingRect.maxX - 0.5, y: 1)))
        }
    }
}
