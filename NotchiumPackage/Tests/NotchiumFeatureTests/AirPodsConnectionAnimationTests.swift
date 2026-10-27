import AppKit
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class AirPodsConnectionAnimationTests: XCTestCase {
    func testConnectionKeepsTurningBeyondTheFirstTurnAndBannerDuration() {
        let start = ContinuousClock.now
        let motion = NotchAirPodsMotion(connected: true, at: start)
        var previous = 0.0
        for step in 0...600 {
            let sample = motion.sample(at: start + .seconds(Double(step) / 60))
            XCTAssertGreaterThanOrEqual(sample.phase, previous)
            XCTAssertGreaterThanOrEqual(sample.velocity, 0)
            XCTAssertLessThanOrEqual(sample.velocity, 1 / NotchAirPodsMotion.turnDuration)
            previous = sample.phase
        }
        for time in [1.2, 2.5, 5.0, 8.0] {
            let first = motion.sample(at: start + .seconds(time))
            let next = motion.sample(at: start + .seconds(time + NotchAirPodsMotion.turnDuration))
            XCTAssertEqual(next.phase - first.phase, 1, accuracy: 1e-9,
                           "Renewing an active banner must never leave its artwork at rest")
            XCTAssertEqual(first.velocity, next.velocity, accuracy: 1e-9)
        }
    }

    func testDisconnectKeepsTurningInReverseForTheEntireBanner() {
        let start = ContinuousClock.now
        let connection = NotchAirPodsMotion(connected: true, at: start)
        let disconnection = NotchAirPodsMotion(connected: false, at: start)
        for step in 0...600 {
            let instant = start + .seconds(Double(step) / 60)
            let forward = connection.sample(at: instant)
            let reverse = disconnection.sample(at: instant)
            XCTAssertEqual(reverse.phase, -forward.phase, accuracy: 1e-9)
            XCTAssertEqual(reverse.velocity, -forward.velocity, accuracy: 1e-9)
        }
        XCTAssertLessThan(disconnection.sample(at: start + .seconds(2.5)).phase, -1.9)
    }

    func testReversingEvenDuringAccelerationPreservesTheLivePoseAndVelocity() {
        let start = ContinuousClock.now
        for time in [0.05, 0.2, 0.7, 1.35, 2.4] {
            for connected in [true, false] {
                var motion = NotchAirPodsMotion(connected: connected, at: start)
                let instant = start + .seconds(time)
                let before = motion.sample(at: instant)
                motion.setConnected(!connected, at: instant)
                let after = motion.sample(at: instant)
                XCTAssertEqual(after.phase, before.phase, accuracy: 1e-9)
                XCTAssertEqual(after.velocity, before.velocity, accuracy: 1e-9)
                let reversed = motion.sample(at: instant + .seconds(NotchAirPodsMotion.velocityTransitionDuration))
                XCTAssertEqual(reversed.velocity, (connected ? -1 : 1) / NotchAirPodsMotion.turnDuration,
                               accuracy: 1e-9)
            }
        }
    }

    func testRepeatedReversalsPreserveContinuityAndSameDirectionUpdatesDoNotRestart() {
        let start = ContinuousClock.now
        var motion = NotchAirPodsMotion(connected: true, at: start)
        var connected = true
        for time in [0.05, 0.1, 0.15, 0.3, 1.3, 2.0] {
            let instant = start + .seconds(time)
            let before = motion.sample(at: instant)
            connected.toggle()
            motion.setConnected(connected, at: instant)
            XCTAssertEqual(motion.sample(at: instant).phase, before.phase, accuracy: 1e-9)
            XCTAssertEqual(motion.sample(at: instant).velocity, before.velocity, accuracy: 1e-9)
        }

        let uninterrupted = motion
        for time in [2.01, 2.05, 2.1, 2.4, 4.0] {
            let instant = start + .seconds(time)
            motion.setConnected(connected, at: instant)
            XCTAssertEqual(motion.sample(at: instant).phase, uninterrupted.sample(at: instant).phase, accuracy: 1e-9)
            XCTAssertEqual(motion.sample(at: instant).velocity, uninterrupted.sample(at: instant).velocity, accuracy: 1e-9)
        }
    }

    func testUnwrappedYawSelectsTheSamePoseAcrossFullTurnsInBothDirections() {
        for phase in [0.0, 0.25, 0.5, 0.75] {
            for turns in -3...3 {
                XCTAssertEqual(NotchAirPodsMotion.pose(at: phase + Double(turns)), phase, accuracy: 0.000_001)
            }
        }
    }

    func testFullTurnSeamsHaveIdenticalPosesDespiteFloatingPointResidue() {
        for phase in [-2.0, -1, 0, 1, 2] {
            for residue in [-1e-12, 0, 1e-12] {
                XCTAssertEqual(NotchAirPodsMotion.pose(at: phase + residue), 0)
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
