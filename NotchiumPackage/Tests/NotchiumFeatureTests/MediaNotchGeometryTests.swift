import AppKit
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

final class MediaNotchGeometryTests: XCTestCase {
    private let host = CGRect(x: 0, y: 0, width: 740, height: 322)
    private let hardware = CGRect(x: 280.5, y: 0, width: 179, height: 32)

    private var passive: NotchShape {
        NotchShape(width: hardware.width, height: hardware.height, centerX: hardware.midX,
                   topCornerRadius: 0, bottomCornerRadius: 8, hardwareExclusion: hardware)
    }

    func testClosingSpringNeverExposesHardwareBelowMediaSurface() {
        let media = CollapsedMediaGeometry(hardwareWidth: hardware.width, hardwareHeight: hardware.height)
        // A real underdamped spring passes its target. Include the tail on both sides
        // of the endpoint, rather than checking only linear samples between targets.
        for progress: CGFloat in [-0.04, -0.02, -0.001, 0, 0.001, 0.1, 0.75, 1, 1.02] {
            let shape = NotchShellSurface(
                width: media.width + (548 - media.width) * progress,
                height: hardware.height + (266 - hardware.height) * progress,
                centerX: hardware.midX, bottomRadius: 8 + 20 * progress,
                passiveShape: passive, shoulderRadius: 12 * progress)
            let path = shape.path(in: host)
            XCTAssertGreaterThanOrEqual(path.boundingRect.maxY, hardware.maxY,
                                        "The spring tail must stay flush with the hardware")
            let cornerExtent = passive.bottomCornerRadius * NotchShape.lowerCornerExtentMultiplier
            for x in stride(from: hardware.minX + cornerExtent, through: hardware.maxX - cornerExtent, by: 1) {
                XCTAssertTrue(path.contains(CGPoint(x: x, y: hardware.maxY - 0.5)))
            }
        }
    }

    func testNarrowMediaExitKeepsCurvedHardwareCovered() {
        // The hardware's bounding rectangle includes its transparent corner cutouts.
        // Keep the curved notch covered without turning those cutouts into a square.
        var hardwareShape = passive
        hardwareShape.hardwareExclusion = nil
        let hardwarePath = hardwareShape.path(in: host)
        for extraWidth: CGFloat in [0.01, 0.1, 1, 4, 12, 40, 80] {
            let shape = NotchShellSurface(width: hardware.width + extraWidth,
                                         height: hardware.height, centerX: hardware.midX,
                                         bottomRadius: 8, passiveShape: passive, shoulderRadius: 0.5)
            let path = shape.path(in: host)
            for y in stride(from: hardware.minY + 0.5, through: hardware.maxY - 0.5, by: 1) {
                for x in stride(from: hardware.minX + 0.5, through: hardware.maxX - 0.5, by: 1) {
                    let point = CGPoint(x: x, y: y)
                    if hardwarePath.contains(point) {
                        XCTAssertTrue(path.contains(point), "Retraction must not carve into the curved hardware notch")
                    }
                }
            }
        }
    }

    func testPassiveEndpointAndItsUndershootRemainInvisible() {
        for overshoot: CGFloat in [0, -0.01, -1, -8] {
            let shape = NotchShellSurface(width: hardware.width + overshoot,
                                         height: hardware.height + overshoot, centerX: hardware.midX,
                                         bottomRadius: 8, passiveShape: passive)
            XCTAssertTrue(shape.path(in: host).isEmpty)
        }
    }

    func testMediaExitAndPositiveSpringTailKeepPassiveCornersRounded() {
        // The spring can cross the empty endpoint and rebound by a fraction of a point.
        // That tiny rebound must approach the curved hardware notch, never a square overlay.
        for extraWidth: CGFloat in [0.000001, 0.01, 0.1, 0.5, 1] {
            let shape = NotchShellSurface(width: hardware.width + extraWidth,
                                         height: hardware.height, centerX: hardware.midX,
                                         bottomRadius: passive.bottomCornerRadius, passiveShape: passive)
            let path = shape.path(in: host)
            XCTAssertFalse(path.contains(CGPoint(x: hardware.minX + 0.5, y: hardware.maxY - 0.5)),
                           "A positive spring tail must not square off the left hardware corner")
            XCTAssertFalse(path.contains(CGPoint(x: hardware.maxX - 0.5, y: hardware.maxY - 0.5)),
                           "A positive spring tail must not square off the right hardware corner")
            XCTAssertTrue(path.contains(CGPoint(x: hardware.midX, y: hardware.maxY - 0.5)))
        }
    }

    @MainActor
    func testPositiveMediaSpringTailDoesNotRenderSquareCornerPixels() throws {
        for scale: CGFloat in [1, 2] {
            let shape = NotchShellSurface(width: hardware.width + 0.1,
                                         height: hardware.height, centerX: hardware.midX,
                                         bottomRadius: passive.bottomCornerRadius, passiveShape: passive)
            let renderer = ImageRenderer(content: NotchSurfaceFrame(
                shape: shape, phase: .closingBlack, expandedHeight: hardware.height) { _ in
                    Color.red // The fill and content mask must both preserve the cutouts.
                }.frame(width: host.width, height: host.height))
            renderer.scale = scale
            let image = try XCTUnwrap(renderer.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let y = Int((hardware.maxY - 0.5) * scale)
            for x in [hardware.minX + 0.5, hardware.maxX - 0.5] {
                XCTAssertEqual(pixels[(y * image.width + Int(x * scale)) * 4 + 3], 0,
                               "The spring tail must leave the hardware corner cutouts transparent")
            }
            XCTAssertEqual(pixels[(y * image.width + Int(hardware.midX * scale)) * 4 + 3], 255,
                           "The active surface stays solid inside the curved notch")
        }
    }

    @MainActor
    func testMusicAndTimerRenderMatchingTopShouldersWithoutChangingContentWidth() throws {
        let layout = NotchGeometryResolver.layout(for:
            .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
        let media = CollapsedMediaGeometry(hardwareWidth: layout.collapsedVisibleFrame.width,
                                            hardwareHeight: layout.collapsedVisibleFrame.height)
        XCTAssertEqual(media.width, media.hardwareWidth + 80, "Artwork and waveform retain their content width")
        let countdown = NotchCountdown.paused(total: 1500, remaining: 1440)
        for (name, music, timer) in [("music", true, false), ("timer", false, true), ("combined", true, true)] {
            for reduceMotion in [false, true] {
                let model = DynamicIslandPresentationModel(clock: ControlledAppClock())
                defer { model.reset() }
                if music {
                    model.mediaRenderer = GeometryMediaRenderer()
                    model.activityCoordinator.present(.init(
                        id: UUID(), key: .media, kind: .media, title: "Music", subtitle: nil,
                        priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
                        isDismissible: false, destination: .music, duration: nil,
                        payload: .mediaPlayback(isPlaying: true), minimal: .artwork))
                }
                if timer {
                    model.notificationCoordinator.present(.init(
                        kind: .focusTimer, dismissible: false, coalescingKey: "test.timer", action: .pomodoro,
                        presentationStyle: .compact,
                        content: .compact(.init(glyph: .symbol("timer"), title: "Focus", showsTitle: false,
                                                trailing: .countdown(countdown))),
                        lifetime: .persistent, minimal: .countdown(countdown)))
                }
                let bodyWidth = timer ? NotchCompactGeometry(layout: layout).bodyWidth : media.width
                let indicatorWidth: CGFloat = music && timer ? NotchSecondaryGeometry.bodyWidth * 2 : 0
                let center = layout.collapsedVisibleFrame.midX - layout.panelFrame.minX
                let wallOffset = (bodyWidth + indicatorWidth) / 2
                for scale: CGFloat in [1, 2] {
                    let content = NotchiumShellView(model: model, layout: layout,
                        renderConfiguration: .init(reduceMotion: reduceMotion ? .on : .off))
                        .frame(width: host.width, height: host.height)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = scale
                    let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                    for x in [center - wallOffset - 2, center + wallOffset + 2] {
                        let top = try XCTUnwrap(bitmap.colorAt(x: Int(x * scale), y: 0))
                        let below = try XCTUnwrap(bitmap.colorAt(x: Int(x * scale), y: Int(8 * scale)))
                        XCTAssertGreaterThan(top.alphaComponent, 0.5, "\(name) flares into the screen edge")
                        XCTAssertEqual(below.alphaComponent, 0, "\(name) curves inward below the top edge")
                    }
                    let belowNotch = try XCTUnwrap(bitmap.colorAt(x: Int(center * scale),
                        y: Int((layout.collapsedVisibleFrame.height + 1) * scale)))
                    XCTAssertEqual(belowNotch.alphaComponent, 0, "Compact shoulders must not add height")
                    if !reduceMotion && scale == 2 {
                        let preview = ImageRenderer(content: content.background(Color(white: 0.85)))
                        preview.scale = scale
                        let previewBitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(preview.cgImage))
                        let png = try XCTUnwrap(previewBitmap.representation(using: .png, properties: [:]))
                        try png.write(to: URL(fileURLWithPath: "/private/tmp/notchium-compact-shoulders-\(name).png"))
                    }
                }
            }
        }
    }

    @MainActor
    func testCollapsedContentUsesMeasuredHardwareCenter() throws {
        let display = NotchiumDisplaySnapshot(
            id: NotchiumDisplayID(rawValue: 77), name: "Asymmetric media fixture",
            frame: CGRect(x: 100, y: 50, width: 1600, height: 1000),
            safeAreaInsets: NotchiumDisplayInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 100, y: 1018, width: 680, height: 32),
            auxiliaryTopRightArea: CGRect(x: 960, y: 1018, width: 740, height: 32),
            isBuiltIn: true, isPrimary: true)
        let layout = NotchGeometryResolver.layout(for: .init(display: display, mode: .physicalNotch), state: .collapsed)
        let model = DynamicIslandPresentationModel(clock: ControlledAppClock())
        defer { model.reset() }
        model.mediaRenderer = GeometryMediaRenderer()
        model.activityCoordinator.present(.init(
            id: UUID(), key: .media, kind: .media, title: "Music", subtitle: nil,
            priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
            isDismissible: false, destination: .music, duration: nil,
            payload: .mediaPlayback(isPlaying: true), minimal: .artwork))
        let renderer = ImageRenderer(content: NotchiumShellView(model: model, layout: layout)
            .frame(width: host.width, height: host.height))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: host)
        let left = Int(layout.collapsedVisibleFrame.minX - layout.panelFrame.minX - 20)
        let right = Int(layout.collapsedVisibleFrame.maxX - layout.panelFrame.minX + 20)
        XCTAssertEqual(pixels[(16 * image.width + left) * 4], 255, "Artwork must sit beside the measured notch")
        XCTAssertEqual(pixels[(16 * image.width + right) * 4 + 2], 255, "Waveform must sit beside the measured notch")
    }
}

@MainActor
private final class GeometryMediaRenderer: NotchMediaRendering {
    var collapsedMediaVisible: Bool { true }
    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView {
        AnyView(HStack(spacing: 0) {
            Color.red.frame(width: 40)
            Color.clear.frame(width: hardwareWidth)
            Color.blue.frame(width: 40)
        }.frame(height: hardwareHeight))
    }
    func expandedMedia() -> AnyView { AnyView(EmptyView()) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(EmptyView()) }
}
