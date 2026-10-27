import AppKit
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class AirPodsRetractionTests: XCTestCase {
    func testRetractionStartsAtTheExistingPoseAndStaysBoundedAcrossEveryAirPodsWidth() {
        for activity in activities {
            for restoresMedia in [false, true] {
                let full = NotchAirPodsReveal(reveal: 1, sideWidth: activity.sideWidth,
                                                  restoresMedia: restoresMedia)
                XCTAssertEqual(full.leadingInset, 0)
                XCTAssertEqual(full.scale, 1)
                XCTAssertEqual(full.opacity, 1)

                var previous = full
                for step in 0...1_000 {
                    let sample = NotchAirPodsReveal(reveal: 1 - CGFloat(step) / 1_000,
                        sideWidth: activity.sideWidth, restoresMedia: restoresMedia)
                    XCTAssertGreaterThanOrEqual(sample.leadingInset, previous.leadingInset)
                    XCTAssertLessThanOrEqual(sample.leadingInset, activity.sideWidth)
                    XCTAssertLessThanOrEqual(sample.scale, previous.scale)
                    XCTAssertGreaterThan(sample.scale, 0)
                    XCTAssertLessThanOrEqual(sample.opacity, previous.opacity)
                    XCTAssertGreaterThanOrEqual(sample.opacity, 0)
                    // Dense neighboring samples catch a discontinuity before the content's
                    // removal boundary, rather than asserting the choreography's formula.
                    XCTAssertLessThan(abs(sample.leadingInset - previous.leadingInset), 0.25)
                    XCTAssertLessThan(abs(sample.scale - previous.scale), 0.01)
                    XCTAssertLessThan(abs(sample.opacity - previous.opacity), 0.01)
                    previous = sample
                }

                for reveal: CGFloat in [-1, 1.2] {
                    let sample = NotchAirPodsReveal(reveal: reveal, sideWidth: activity.sideWidth,
                                                       restoresMedia: restoresMedia)
                    XCTAssertTrue((0...activity.sideWidth).contains(sample.leadingInset))
                    XCTAssertTrue((0...1).contains(sample.scale))
                    XCTAssertTrue((0...1).contains(sample.opacity))
                }
            }
        }
    }

    func testArtworkIsAlreadyInvisibleWhileItsSlotIsStillRetained() {
        for activity in activities {
            for restoresMedia in [false, true] {
                // Both samples precede the established row-removal boundaries. Music
                // must reclaim its artwork slot without cutting off a visible product.
                let reveal: CGFloat = restoresMedia ? 0.35 : 0.01
                XCTAssertTrue(NotchCompactActivitySlot.retainsContent(reveal: reveal,
                                                                     restoresMedia: restoresMedia))
                let sample = NotchAirPodsReveal(reveal: reveal, sideWidth: activity.sideWidth,
                                                   restoresMedia: restoresMedia)
                XCTAssertEqual(sample.opacity, 0)
            }
        }
    }

    func testReduceMotionFadesTheRenderedProductWithoutMovingOrResizingIt() throws {
        for activity in activities {
            for restoresMedia in [false, true] {
                let baseline = try productPixels(activity, reveal: 1, restoresMedia: restoresMedia,
                                                 retracting: false)
                let full = try productPixels(activity, reveal: 1, restoresMedia: restoresMedia)
                let middle = try productPixels(activity, reveal: restoresMedia ? 0.7 : 0.6,
                                               restoresMedia: restoresMedia)
                let hidden = try productPixels(activity, reveal: restoresMedia ? 0.35 : 0.01,
                                               restoresMedia: restoresMedia)
                XCTAssertGreaterThan(full.alpha, 5, "The real product resource must be visible")
                XCTAssertEqual(full.alpha, baseline.alpha, accuracy: 0.01,
                               "Starting retraction must preserve the product's current appearance")
                XCTAssertEqual(full.centerX, baseline.centerX, accuracy: 0.01)
                XCTAssertEqual(full.spread, baseline.spread, accuracy: 0.01)
                XCTAssertGreaterThan(full.alpha, middle.alpha)
                XCTAssertGreaterThan(middle.alpha, 0)
                XCTAssertEqual(middle.centerX, full.centerX, accuracy: 0.15)
                XCTAssertEqual(middle.spread, full.spread, accuracy: 0.15)
                XCTAssertEqual(hidden.alpha, 0, accuracy: 0.01)
            }
        }
    }

    private var activities: [NotchCompactActivity] {
        [NotchDeviceStyle.airPods, .airPodsPro, .airPodsMax].flatMap { style in
            [NotchCompactActivity(.init(kind: .outputChanged, deviceName: "AirPods", volume: nil,
                isMuted: false, deviceStyle: style, battery: .init(level: 0.82, isCharging: false))),
             NotchCompactActivity(.init(kind: .outputChanged, deviceName: "AirPods", volume: nil,
                isMuted: false, deviceStyle: style)),
             NotchCompactActivity(.init(kind: .deviceDisconnected, deviceName: "AirPods", volume: nil,
                isMuted: false, deviceStyle: style))]
        }
    }

    private struct ProductPixels {
        let alpha: Double
        let centerX: Double
        let spread: Double
    }

    private func productPixels(_ activity: NotchCompactActivity, reveal: CGFloat, restoresMedia: Bool,
                               retracting: Bool = true) throws -> ProductPixels {
        let layout = NotchGeometryResolver.layout(for:
            .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
        let geometry = NotchCompactGeometry(layout: layout, activity: activity)
        let content = NotchCompactActivityView(activity: activity, geometry: geometry, reveal: reveal,
            entryID: UUID(), reduceMotion: true, action: {}, restoresMedia: restoresMedia)
            .environment(\.notchCompactRetracting, retracting)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        var alpha = 0.0
        var firstMoment = 0.0
        var secondMoment = 0.0
        // The product travels into the leading half of the physical notch. The
        // trailing status/battery readout never enters this region.
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<(bitmap.pixelsWide / 2) {
                let value = Double(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent)
                let pointX = Double(x) / 2
                alpha += value
                firstMoment += value * pointX
                secondMoment += value * pointX * pointX
            }
        }
        let center = alpha > 0 ? firstMoment / alpha : 0
        let variance = alpha > 0 ? max(0, secondMoment / alpha - center * center) : 0
        return ProductPixels(alpha: alpha, centerX: center, spread: sqrt(variance))
    }
}
