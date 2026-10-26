import AppKit
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class AirPodsConnectionAnimationTests: XCTestCase {
    func testProductTurnIsMonotonicAndSettlesWithoutOvershoot() {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            NotchAirPodsMotion.turn(from: 0, connected: true)
        }
        XCTAssertEqual(timeline.duration, 1.2, accuracy: 0.001)
        XCTAssertEqual(timeline.value(time: 0), 0, accuracy: 0.001)
        XCTAssertEqual(timeline.value(time: timeline.duration), 1, accuracy: 0.001)
        var previous = 0.0
        for step in 0...240 {
            let progress = timeline.value(time: timeline.duration * Double(step) / 240)
            XCTAssertGreaterThanOrEqual(progress, previous - 0.000_001)
            XCTAssertGreaterThanOrEqual(progress, 0)
            XCTAssertLessThanOrEqual(progress, 1)
            previous = progress
        }
        let lastStep = timeline.value(time: 1.2) - timeline.value(time: 1.18)
        let middleStep = timeline.value(time: 0.6) - timeline.value(time: 0.58)
        XCTAssertLessThan(lastStep, middleStep / 4, "The turn must ease into the final pose")
    }

    func testDisconnectTurnsInReverseAndSettlesAtTheFrontPose() {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            NotchAirPodsMotion.turn(from: 0, connected: false)
        }
        XCTAssertEqual(timeline.duration, 1.2, accuracy: 0.001)
        var previous = 0.0
        for step in 0...240 {
            let phase = timeline.value(time: timeline.duration * Double(step) / 240)
            XCTAssertLessThanOrEqual(phase, previous + 0.000_001)
            XCTAssertGreaterThanOrEqual(phase, -1)
            XCTAssertLessThanOrEqual(phase, 0)
            previous = phase
        }
        XCTAssertEqual(previous, -1, accuracy: 0.001)
        XCTAssertEqual(NotchAirPodsMotion.pose(at: previous), 0, accuracy: 0.001)
    }

    func testReversingAnInterruptedTurnStartsAtItsCurrentOrientation() {
        for phase in [-1.65, -0.4, 0.2, 0.7, 1.35] {
            for connected in [false, true] {
                let timeline = KeyframeTimeline(initialValue: phase) {
                    NotchAirPodsMotion.turn(from: phase, connected: connected)
                }
                XCTAssertEqual(timeline.value(time: 0), phase, accuracy: 0.000_001,
                               "A new event must not reset the artwork to the front")
                let end = timeline.value(time: timeline.duration)
                XCTAssertEqual(end, end.rounded(), accuracy: 0.000_001)
                XCTAssertEqual(NotchAirPodsMotion.pose(at: end), 0, accuracy: 0.000_001)
                XCTAssertLessThan(abs(end - phase), 1)
                if connected { XCTAssertGreaterThan(end, phase) }
                else { XCTAssertLessThan(end, phase) }
            }
        }
    }

    func testUnwrappedYawSelectsTheSamePoseAcrossFullTurnsInBothDirections() {
        for phase in [0.0, 0.25, 0.5, 0.75] {
            for turns in -3...3 {
                XCTAssertEqual(NotchAirPodsMotion.pose(at: phase + Double(turns)), phase, accuracy: 0.000_001)
            }
        }
    }

    func testEndpointRoundingCannotSwallowTheNextConnectionOrDisconnectTurn() {
        for phase in [-2.0, -1, 0, 1, 2] {
            for residue in [-1e-12, 0, 1e-12] {
                XCTAssertEqual(NotchAirPodsMotion.pose(at: phase + residue), 0)
                XCTAssertEqual(NotchAirPodsMotion.destination(from: phase + residue, connected: true), phase + 1)
                XCTAssertEqual(NotchAirPodsMotion.destination(from: phase + residue, connected: false), phase - 1)
            }
        }
    }

    func testProductArtworkDoesNotChangeGenericWearableClassification() {
        for style in [NotchDeviceStyle.airPods, .airPodsPro, .airPodsMax] {
            XCTAssertNotNil(NotchAirPodsArtwork(style: style))
            XCTAssertTrue(style.spinsOnConnect)
        }
        for style in [NotchDeviceStyle.beats, .headphones, .speaker, .display, .airPlay, .builtIn] {
            XCTAssertNil(NotchAirPodsArtwork(style: style))
        }
        XCTAssertTrue(NotchDeviceStyle.headphones.spinsOnConnect,
                      "This flag also drives audio connection policy")
    }

    func testEveryBundledTurnHasTransparentUnclippedFramesAndAnIdenticalRestPose() throws {
        let edge = NotchAirPodsArtwork.framePixels
        for artwork in NotchAirPodsArtwork.allCases {
            let url = try XCTUnwrap(artwork.resourceURL)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
            XCTAssertEqual(bitmap.pixelsWide, edge * NotchAirPodsArtwork.frameCount)
            XCTAssertEqual(bitmap.pixelsHigh, edge)
            XCTAssertTrue(bitmap.hasAlpha)

            for frame in 0..<NotchAirPodsArtwork.frameCount {
                var visible = 0
                for y in 0..<edge {
                    for x in 0..<edge {
                        let alpha = try XCTUnwrap(bitmap.colorAt(x: frame * edge + x, y: y)).alphaComponent
                        if alpha > 0.1 { visible += 1 }
                        if x == 0 || y == 0 || x == edge - 1 || y == edge - 1 {
                            XCTAssertLessThan(alpha, 0.01, "\(artwork) frame \(frame) clips its silhouette")
                        }
                    }
                }
                XCTAssertGreaterThan(visible, 100, "\(artwork) frame \(frame) must retain real volume")
            }

            for y in stride(from: 0, to: edge, by: 3) {
                for x in stride(from: 0, to: edge, by: 3) {
                    let first = try XCTUnwrap(bitmap.colorAt(x: x, y: y))
                    let last = try XCTUnwrap(bitmap.colorAt(x: (NotchAirPodsArtwork.frameCount - 1) * edge + x, y: y))
                    XCTAssertEqual(first.alphaComponent, last.alphaComponent, accuracy: 0.01)
                    XCTAssertEqual(first.redComponent, last.redComponent, accuracy: 0.01)
                    XCTAssertEqual(first.greenComponent, last.greenComponent, accuracy: 0.01)
                    XCTAssertEqual(first.blueComponent, last.blueComponent, accuracy: 0.01)
                }
            }
        }
    }

    func testFrameSelectionClampsToValidFrames() {
        XCTAssertEqual(NotchAirPodsArtwork.frame(at: -0.1), 0)
        XCTAssertEqual(NotchAirPodsArtwork.frame(at: 0.5), 30)
        XCTAssertEqual(NotchAirPodsArtwork.frame(at: 1.1), 60)
        XCTAssertEqual(NotchAirPodsArtwork.frame(at: .nan), 60)
        XCTAssertEqual(NotchAirPodsArtwork.frame(at: .infinity), 60)
    }

    func testProductFrameRendersVisibleArtworkAtEveryQuarterTurn() throws {
        for artwork in NotchAirPodsArtwork.allCases {
            for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
                XCTAssertNotNil(artwork.image(at: progress))
                let renderer = ImageRenderer(content: NotchAirPodsProductFrame(artwork: artwork, progress: progress)
                    .frame(width: 96, height: 96))
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                var visible = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { visible += 1 }
                    }
                }
                XCTAssertGreaterThan(visible, 100, "\(artwork) at \(progress) must actually render")
                if let directory = ProcessInfo.processInfo.environment["NOTCHIUM_AIRPODS_CAPTURE_DIR"] {
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    let url = URL(fileURLWithPath: directory).appendingPathComponent("pose-\(artwork.rawValue)-\(progress).png")
                    try bitmap.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
        }
    }
}
