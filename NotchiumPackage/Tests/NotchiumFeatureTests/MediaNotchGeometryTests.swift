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
            for x in stride(from: hardware.minX + 0.5, through: hardware.maxX - 0.5, by: 1) {
                XCTAssertTrue(path.contains(CGPoint(x: x, y: hardware.maxY - 0.5)))
            }
        }
    }

    func testNarrowMediaExitKeepsCornersOutsideHardware() {
        // Media stopping retracts its flanks at the hardware height. Overshooting
        // corner radii must not carve wallpaper gaps beside the physical notch.
        for extraWidth: CGFloat in [0.01, 0.1, 1, 4, 12, 40, 80] {
            let shape = NotchShellSurface(width: hardware.width + extraWidth,
                                         height: hardware.height, centerX: hardware.midX,
                                         bottomRadius: 8, passiveShape: passive, shoulderRadius: 0.5)
            let path = shape.path(in: host)
            XCTAssertTrue(path.contains(CGPoint(x: hardware.minX + 0.01, y: hardware.maxY - 0.01)))
            XCTAssertTrue(path.contains(CGPoint(x: hardware.maxX - 0.01, y: hardware.maxY - 0.01)))
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
