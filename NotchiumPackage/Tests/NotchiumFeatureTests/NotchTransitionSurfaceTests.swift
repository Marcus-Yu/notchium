import AppKit
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class NotchTransitionSurfaceTests: XCTestCase {
    func testContentStaysBlackUntilCurrentAnimationCompletes() {
        var state = NotchVisualTransition(expanded: false)
        XCTAssertEqual(state.phase, .collapsed)
        let opening = state.begin(expanded: true)
        XCTAssertEqual(state.phase, .openingBlack)
        let closing = state.begin(expanded: false)
        state.complete(generation: opening)
        XCTAssertEqual(state.phase, .closingBlack)
        let reopening = state.begin(expanded: true)
        state.complete(generation: closing)
        XCTAssertEqual(state.phase, .openingBlack)
        state.complete(generation: reopening)
        XCTAssertEqual(state.phase, .expanded)
        let finalClose = state.begin(expanded: false)
        XCTAssertTrue(state.isBlack)
        state.complete(generation: finalClose)
        XCTAssertEqual(state.phase, .collapsed)
    }

    func testRepeatedReversalsRejectEveryStaleCompletion() {
        for finalExpanded in [false, true] {
            var state = NotchVisualTransition(expanded: !finalExpanded)
            var generations = [Int]()
            for index in 0..<20 {
                generations.append(state.begin(expanded: index.isMultiple(of: 2)))
            }
            let current = state.begin(expanded: finalExpanded)
            for generation in generations.reversed() {
                state.complete(generation: generation)
                XCTAssertTrue(state.isBlack)
            }
            state.complete(generation: current)
            XCTAssertEqual(state.phase, finalExpanded ? .expanded : .collapsed)
        }
    }

    func testEverySampleIsBlackAcrossAllPageSizesAndBothDirections() throws {
        // Sample at 60 Hz over a 0.4 s nominal morph. This is a raster invariant
        // test, not a live 60 fps recording or a frame-pacing measurement.
        for size in [CGSize(width: 524, height: 266), CGSize(width: 560, height: 302)] {
            for reverse in [false, true] {
                for frame in 0...24 {
                    let progress = CGFloat(reverse ? 24 - frame : frame) / 24
                    let shape = NotchShellSurface(
                        width: 292 + (size.width - 292) * progress,
                        height: 38 + (size.height - 38) * progress,
                        centerX: 300, bottomRadius: 8 + 20 * progress,
                        passiveShape: NotchShape(width: 212, height: 38, centerX: 300,
                                                 topCornerRadius: 0, bottomCornerRadius: 8))
                    let image = try render(NotchSurfaceFrame(shape: shape, phase: .closingBlack, expandedHeight: size.height) { _ in
                        // Bright content covering the entire host catches any leak,
                        // regardless of which page, media or utility is mounted.
                        Rectangle().fill(.red)
                    }.frame(width: 600, height: 322))
                    let data = pixels(image)
                    XCTAssertEqual(data[(10 * image.width + 300) * 4 + 3], 255)
                    for index in stride(from: 0, to: data.count, by: 4) where data[index + 3] > 0 {
                        XCTAssertEqual(data[index], 0)
                        XCTAssertEqual(data[index + 1], 0)
                        XCTAssertEqual(data[index + 2], 0)
                    }
                }
            }
        }
    }

    func testOpeningRevealsAt75PercentWithFullSizeClippedContent() throws {
        for height: CGFloat in [266, 302] {
            for progress: CGFloat in [0, 0.74, 0.75, 0.85, 1] {
                let shape = NotchShellSurface(
                    width: 400, height: 38 + (height - 38) * progress,
                    centerX: 200, bottomRadius: 20,
                    passiveShape: NotchShape(width: 212, height: 38, centerX: 200,
                                             topCornerRadius: 0, bottomCornerRadius: 8))
                let surface = NotchSurfaceFrame(shape: shape, phase: .openingBlack,
                                                expandedHeight: height) { _ in
                    ZStack(alignment: .top) {
                        Color.clear
                        Rectangle().fill(.red).frame(width: 84, height: 84).padding(.top, 60)
                        Rectangle().fill(.blue).frame(width: 100, height: 10).offset(y: height - 12)
                    }
                    .frame(width: 400, height: height)
                }
                XCTAssertEqual(surface.contentPhase, progress >= 0.75 ? .expanded : .openingBlack)
                let image = try render(surface)
                let data = pixels(image)
                let artworkPixel = (100 * image.width + 200) * 4
                XCTAssertEqual(data[artworkPixel], progress >= 0.75 ? 255 : 0)
                if progress >= 0.75 {
                    // Artwork retains exactly 84 points of width while shell grows.
                    XCTAssertEqual(data[(100 * image.width + 158) * 4], 255)
                    XCTAssertEqual(data[(100 * image.width + 241) * 4], 255)
                    XCTAssertEqual(data[(100 * image.width + 157) * 4], 0)
                    XCTAssertEqual(data[(100 * image.width + 242) * 4], 0)
                }
                if progress < 1 {
                    XCTAssertEqual(data[((Int(height) - 8) * image.width + 200) * 4 + 3], 0)
                }
                var reversing = surface
                reversing.hidesPendingTarget = true
                XCTAssertEqual(reversing.contentPhase, .closingBlack)
            }
        }
    }

    func testEndpointContentAppearsAtNormalSizeWithoutFade() throws {
        let view = Rectangle().fill(.red).frame(width: 84, height: 84)
        let visible = try render(view.modifier(NotchPresentationClip(visible: true)))
        XCTAssertEqual(visible.width, 84)
        XCTAssertEqual(visible.height, 84)
        XCTAssertEqual(pixels(visible)[(42 * 84 + 42) * 4 + 3], 255)
        let hidden = try render(view.modifier(NotchPresentationClip(visible: false)))
        XCTAssertEqual(hidden.width, 84)
        XCTAssertEqual(hidden.height, 84)
        XCTAssertTrue(pixels(hidden).allSatisfy { $0 == 0 })
    }

    private func render(_ view: some View) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
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
