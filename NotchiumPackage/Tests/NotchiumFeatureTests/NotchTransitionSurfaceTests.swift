import AppKit
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland
import NotchiumDesignSystem

@MainActor
final class NotchTransitionSurfaceTests: XCTestCase {
    func testSystemSettleInvalidatesOpeningAndClosingCompletions() {
        var state = NotchVisualTransition(expanded: false)
        let opening = state.begin(expanded: true)
        let closing = state.begin(expanded: false)
        state.settle(expanded: false)
        for generation in [opening, closing] {
            state.complete(generation: generation)
            XCTAssertEqual(state.phase, .collapsed)
        }
        let reopening = state.begin(expanded: true)
        state.complete(generation: closing)
        XCTAssertEqual(state.phase, .openingBlack)
        state.complete(generation: reopening)
        XCTAssertEqual(state.phase, .expanded)
    }

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

    func testGatedContentStaysBlackBeforeLandingAcrossAllPageSizes() throws {
        // Sample at 60 Hz over a 0.4 s nominal morph. This is a raster invariant
        // test, not a live 60 fps recording or a frame-pacing measurement.
        for size in [CGSize(width: 524, height: 266), CGSize(width: 560, height: 302)] {
            for reverse in [false, true] {
                for frame in 0...24 {
                    let progress = CGFloat(reverse ? 24 - frame : frame) / 24
                    // Landing now restores the collapsed row; its raster is checked separately.
                    guard progress > 0 else { continue }
                    let shape = NotchShellSurface(
                        width: 292 + (size.width - 292) * progress,
                        height: 38 + (size.height - 38) * progress,
                        centerX: 300, bottomRadius: 8 + 20 * progress,
                        passiveShape: NotchShape(width: 212, height: 38, centerX: 300,
                                                 topCornerRadius: 0, bottomCornerRadius: 8))
                    let image = try render(NotchSurfaceFrame(shape: shape, phase: .closingBlack, expandedHeight: 38,
                                                             openHeight: size.height) { _ in
                        // Bright content covering the entire host catches any leak from the
                        // collapsed row, compact activities or indicators (everything gated).
                        Rectangle().fill(.red).modifier(NotchSurfaceGate())
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

    func testGatedContentOpensAt75PercentWithFullSizeClippedContent() throws {
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
                    // Gated content keeps the binary 75% reveal; the page itself blooms instead.
                    .modifier(NotchSurfaceGate())
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

    func testBloomStagesAreMonotonicAndClosingDissolvesEarly() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.05).map { CGFloat($0) }
        for closing in [false, true] {
            for stage in 0...2 {
                let amounts = samples.map { NotchBloomProgress(progress: $0, closing: closing).amount(stage: stage) }
                XCTAssertEqual(amounts.first, 0)
                XCTAssertEqual(amounts.last, 1)
                XCTAssertEqual(amounts, amounts.sorted(), "Stage \(stage) must never flicker backwards")
            }
        }
        // The header leads the page while opening; nothing lingers through the second half of a close.
        let opening = NotchBloomProgress(progress: 0.5, closing: false)
        XCTAssertGreaterThan(opening.amount(stage: 0), opening.amount(stage: 1))
        XCTAssertEqual(NotchBloomProgress(progress: 0.49, closing: true).amount(stage: 0), 0)
        XCTAssertEqual(NotchBloomProgress.settled.amount(stage: 2), 1)
    }

    func testExpandedContentBloomsWithTheShellAndDissolvesWhileClosing() throws {
        let passive = NotchShape(width: 212, height: 38, centerX: 200, topCornerRadius: 0, bottomCornerRadius: 8)
        func surface(_ progress: CGFloat, closing: Bool) -> NotchSurfaceFrame<some View> {
            NotchSurfaceFrame(
                shape: NotchShellSurface(width: 400, height: 38 + (266 - 38) * progress, centerX: 200,
                                         bottomRadius: 20, passiveShape: passive),
                phase: closing ? .closingBlack : .openingBlack,
                expandedHeight: closing ? 38 : 266, openHeight: 266
            ) { _ in
                Rectangle().fill(.red).frame(width: 120, height: 60)
                    .frame(width: 400, height: 266).notchBloom(stage: 1)
            }
        }
        func red(_ progress: CGFloat, closing: Bool) throws -> UInt8 {
            let frame = surface(progress, closing: closing)
            XCTAssertEqual(frame.bloom.progress, progress, accuracy: 0.001)
            XCTAssertEqual(frame.bloom.closing, closing)
            let image = try render(frame)
            return pixels(image)[(133 * image.width + 200) * 4]
        }
        // Opening: absent at the notch, partially bloomed mid-spring, fully present near the end.
        XCTAssertEqual(try red(0.3, closing: false), 0)
        let midway = try red(0.62, closing: false)
        XCTAssertGreaterThan(midway, 0)
        XCTAssertLessThan(midway, 255)
        XCTAssertEqual(try red(0.95, closing: false), 255)
        // Interaction still waits for the established 75% threshold.
        XCTAssertEqual(surface(0.62, closing: false).contentPhase, .openingBlack)
        // Closing: still present as the shell starts to contract, gone before it is half way down.
        XCTAssertEqual(try red(1, closing: true), 255)
        let dissolving = try red(0.7, closing: true)
        XCTAssertGreaterThan(dissolving, 0)
        XCTAssertLessThan(dissolving, 255)
        XCTAssertEqual(try red(0.45, closing: true), 0)
        // A notification reveal never shows the expanded page.
        var notification = surface(0.8, closing: false)
        notification.notificationVisible = true
        XCTAssertEqual(notification.bloom, .hidden)
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

    func testCollapsedMusicReturnsAtLandingBeforeSpringCompletion() throws {
        let passive = NotchShape(width: 180, height: 32, centerX: 200,
                                 topCornerRadius: 0, bottomCornerRadius: 8)
        for notificationVisible in [false, true] {
            // Include the first landing and subsequent spring-tail samples. Music
            // and compact activities must restore together without waiting for .removed.
            for height: CGFloat in [140, 33, 32.75, 32, 29, 32.1] {
                let surface = NotchSurfaceFrame(
                    shape: .init(width: 260, height: height, centerX: 200,
                                 bottomRadius: 8, passiveShape: passive),
                    phase: .closingBlack, expandedHeight: 32,
                    notificationVisible: notificationVisible) { phase in
                        ZStack(alignment: .top) {
                            Color.clear
                            HStack {
                                Color.red.frame(width: 24, height: 24)
                                Spacer()
                                Color.blue.frame(width: 24, height: 16)
                            }
                            .frame(width: 236, height: 32)
                            .modifier(CollapsedMediaPresentation(visible: phase == .collapsed))
                            Color.green.frame(width: 200, height: 100)
                                .padding(.top, 50)
                                .modifier(NotchPresentationClip(visible: phase == .expanded))
                        }
                        .frame(width: 400, height: 322)
                    }
                let landed = height <= 32.75
                XCTAssertEqual(surface.contentPhase, landed ? .collapsed : .closingBlack)
                let image = try render(surface)
                let data = pixels(image)
                XCTAssertEqual(data[(16 * image.width + 92) * 4], landed ? 255 : 0)
                XCTAssertEqual(data[(16 * image.width + 307) * 4 + 2], landed ? 255 : 0)
                XCTAssertEqual(data[(70 * image.width + 200) * 4 + 1], 0, "Expanded page never leaks")
                var reversing = surface
                reversing.hidesPendingTarget = true
                XCTAssertEqual(reversing.contentPhase, .closingBlack, "A reversal hides the previous target immediately")
            }
        }
    }

    func testWidthOnlyRetargetDoesNotBlankTheCollapsedRow() {
        let surface = NotchSurfaceFrame(
            shape: .init(width: 280, height: 32, centerX: 200, bottomRadius: 8,
                         passiveShape: .init(width: 180, height: 32, centerX: 200,
                                             topCornerRadius: 0, bottomCornerRadius: 8)),
            phase: .closingBlack, expandedHeight: 32) { _ in EmptyView() }
        XCTAssertEqual(surface.contentPhase, .collapsed)
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
