import AppKit
import SwiftUI
@testable import NotchiumMediaFeature
import NotchiumServices
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class NotchTransitionSurfaceTests: XCTestCase {
    func testComponentsTranslateWithoutChangingSizeAndConvergeSymmetrically() {
        let left = CGRect(x: 28, y: 96, width: 84, height: 84)
        let right = CGRect(x: 412, y: 96, width: 84, height: 84)
        for progress: CGFloat in [1, 0.75, 0.5, 0.25, 0] {
            let motion = NotchContentMotion(progress: progress, expandedWidth: 524)
            let lhs = motion.offset(for: left)
            let rhs = motion.offset(for: right)
            XCTAssertEqual(lhs.width, -rhs.width, accuracy: 0.0001)
            XCTAssertEqual(lhs.height, rhs.height)
            XCTAssertEqual(left.offsetBy(dx: lhs.width, dy: lhs.height).size, left.size)
            XCTAssertEqual(left.maxY + lhs.height, (left.maxY + 1) * progress - 1, accuracy: 0.0001)
        }
    }

    func testLayoutSwapOccursOnlyNearCollapsedGeometry() {
        XCTAssertFalse(NotchContentMotion(progress: 0, expandedWidth: 524).showsExpanded)
        XCTAssertFalse(NotchContentMotion(progress: 0.025, expandedWidth: 524).showsExpanded)
        XCTAssertTrue(NotchContentMotion(progress: 0.026, expandedWidth: 524).showsExpanded)
        // The expanded artwork's remaining bottom edge is within the hardware notch
        // at the handover, rather than occupying a collapsed artwork slot.
        let artwork = CGRect(x: 28, y: 96, width: 84, height: 84)
        let motion = NotchContentMotion(progress: 0.025, expandedWidth: 524)
        XCTAssertLessThan(artwork.maxY + motion.offset(for: artwork).height, 38)
    }

    func testRasterizedTranslationKeepsArtworkAndItsDetailsFullSizeAndOpaque() throws {
        for progress: CGFloat in [1, 0.75, 0.5] {
            for artworkVersion in [false, true] {
                let motion = NotchContentMotion(progress: progress, expandedWidth: 524)
                let frame = CGRect(x: 28, y: 96, width: 84, height: 84)
                let offset = motion.offset(for: frame)
                let fixture = ZStack(alignment: .topLeading) {
                    Color.clear
                    ZStack {
                        Rectangle().fill(artworkVersion ? Color.red : Color.orange)
                        Rectangle().fill(.white).frame(width: 8, height: 8)
                    }
                        .frame(width: frame.width, height: frame.height)
                        .notchRetractingContent()
                        .offset(x: frame.minX, y: frame.minY)
                }
                .frame(width: 524, height: 266)
                .coordinateSpace(.named("notch.expandedContent"))
                .environment(\.notchContentMotion, motion)
                let image = try render(fixture)
                let x = Int((frame.minX + offset.width).rounded(.up))
                let y = Int((frame.minY + offset.height).rounded(.up))
                XCTAssertEqual(alpha(image, x: x + 1, y: y + 1), 255)
                XCTAssertEqual(alpha(image, x: x + 81, y: y + 81), 255)
                XCTAssertEqual(alpha(image, x: x - 2, y: y + 1), 0)
                XCTAssertEqual(alpha(image, x: x + 85, y: y + 1), 0)
                // The 8-point artwork detail retains its size at every progress value.
                let rgba = pixels(image)
                for markerX in (x + 38)..<(x + 46) {
                    let index = ((y + 41) * image.width + markerX) * 4
                    XCTAssertEqual(Array(rgba[index..<(index + 4)]), [255, 255, 255, 255])
                }
            }
        }
    }

    func testClipSwitchNeverCrossfadesOrDuplicatesPresentations() throws {
        for progress: CGFloat in [1, 0.6, 0.025, 0, 0.02, 0.5, 1, 0] {
            let motion = NotchContentMotion(progress: progress, expandedWidth: 524)
            let image = try render(ZStack {
                Rectangle().fill(Color(.sRGB, red: 1, green: 0, blue: 0)).modifier(NotchPresentationClip(visible: motion.showsExpanded))
                Rectangle().fill(Color(.sRGB, red: 0, green: 0, blue: 1)).modifier(NotchPresentationClip(visible: !motion.showsExpanded))
            }.frame(width: 20, height: 20))
            XCTAssertEqual(alpha(image, x: 10, y: 10), 255)
            let pixels = pixels(image)
            let offset = (10 * image.width + 10) * 4
            XCTAssertEqual(pixels[offset], motion.showsExpanded ? 255 : 0)
            XCTAssertEqual(pixels[offset + 2], motion.showsExpanded ? 0 : 255)
        }
    }

    func testSharedSurfaceClipsSolidTranslatedContentAtEverySample() throws {
        let passive = NotchShape(width: 212, height: 38, centerX: 262,
                                 topCornerRadius: 0, bottomCornerRadius: 8)
        let openShape = NotchShellSurface(width: 524, height: 266, centerX: 262,
                                         bottomRadius: 28, passiveShape: passive)
        let closedShape = NotchShellSurface(width: 292, height: 38, centerX: 262,
                                           bottomRadius: 8, passiveShape: passive)
        var surface = NotchTransitionSurface(progress: 1, shape: openShape,
            expandedSize: CGSize(width: 524, height: 266), isTransitioning: true) { motion in
            ZStack(alignment: .topLeading) {
                Color.clear
                Rectangle().fill(Color(.sRGB, red: 1, green: 0, blue: 0))
                    .frame(width: 84, height: 84)
                    .notchRetractingContent()
                    .offset(x: 28, y: 96)
                    .modifier(NotchPresentationClip(visible: motion.showsExpanded))
            }
            .frame(width: 524, height: 266)
            .coordinateSpace(.named("notch.expandedContent"))
        }
        let open = surface.animatableData
        surface.progress = 0
        surface.shape = closedShape
        let closed = surface.animatableData
        // A non-monotonic sequence also verifies that no endpoint or handover is latched.
        for progress in [1.0, 0.75, 0.5, 0.1, 0.02, 0.6, 0.0, 1.0] {
            var delta = open - closed
            delta.scale(by: progress)
            surface.animatableData = closed + delta
            XCTAssertEqual(surface.shape.width, 292 + 232 * progress, accuracy: 0.001)
            XCTAssertEqual(surface.shape.height, 38 + 228 * progress, accuracy: 0.001)
            let image = try render(surface)
            let y = Int(surface.shape.height) + 1
            XCTAssertEqual(alpha(image, x: 262, y: min(265, y)), progress == 1 ? 255 : 0)
            // Equal distances outside both edges remain clipped at every intermediate size.
            let outside = Int((524 - surface.shape.width) / 2) - 2
            if outside >= 0 {
                XCTAssertEqual(alpha(image, x: outside, y: 10), 0)
                XCTAssertEqual(alpha(image, x: 523 - outside, y: 10), 0)
            }
        }
    }

    func testRealMediaLayoutAcrossMotionSamples() async throws {
        let presentation = DynamicIslandPresentationModel()
        let provider = MockMediaProvider()
        try await provider.apply(.play)
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true })
        let model = MediaFeatureModel(provider: provider, coordinator: presentation.activityCoordinator,
                                      audioMeter: meter)
        model.receive(await provider.snapshot)
        let passive = NotchShape(width: 212, height: 38, centerX: 262,
                                 topCornerRadius: 0, bottomCornerRadius: 8)
        let samples: [CGFloat] = [1, 0.75, 0.5, 0.25, 0.025, 0]
        let board = VStack(spacing: 8) {
            ForEach(samples, id: \.self) { progress in
                NotchTransitionSurface(progress: progress,
                    shape: NotchShellSurface(width: 292 + 232 * progress, height: 38 + 228 * progress,
                        centerX: 262, bottomRadius: 8 + 20 * progress, passiveShape: passive),
                    expandedSize: CGSize(width: 524, height: 266), isTransitioning: true) { motion in
                    ZStack(alignment: .top) {
                        CollapsedMediaView(model: model, hardwareWidth: 212, hardwareHeight: 38)
                            .modifier(NotchPresentationClip(visible: !motion.showsExpanded))
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 32) // Navigation; omit its AppKit swipe overlay in ImageRenderer.
                            MediaPageView(model: model)
                        }
                            .padding(.top, 38)
                            .frame(width: 524, height: 266)
                            .notchRetractingContent()
                            .coordinateSpace(.named("notch.expandedContent"))
                            .modifier(NotchPresentationClip(visible: motion.showsExpanded))
                    }
                    .frame(width: 524, height: 266, alignment: .top)
                }
                .frame(width: 524, height: 266)
                .background(Color(white: 0.25))
            }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        let image = try render(board)
        XCTAssertEqual(image.width, 524)
        XCTAssertEqual(image.height, 1636)
        if let output = ProcessInfo.processInfo.environment["NOTCH_MOTION_SNAPSHOT"] {
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: output))
        }
    }

    private func render(_ view: some View) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return 0 }
        return pixels(image)[(y * image.width + x) * 4 + 3]
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &pixels, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
}
