import AppKit
import NotchiumCore
import SwiftUI
import XCTest
@testable import NotchiumCameraFeature
@testable import NotchiumDynamicIsland
@testable import NotchiumServices

/// Camera dismissal and shell collapse mutate the same mounted SwiftUI tree. A
/// presentation-enum assertion alone cannot catch a shell stranded behind its black gate.
@MainActor
final class CameraExitRenderingTests: XCTestCase {
    func testHoveredCameraExitCollapsesAndReopensWithVisibleContent() async throws {
        for reduced in [false, true] {
            let fixture = try CameraExitRenderingFixture(reduced: reduced)
            defer { fixture.stop() }
            try await fixture.open(.hovered)
            try await fixture.openCamera()

            fixture.model.setHovered(false)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertTrue(fixture.camera.isPreviewPresented, "The hover exit grace retains the preview")
            XCTAssertTrue(fixture.service.isRunning)
            try await Task.sleep(for: .milliseconds(400))
            fixture.assertCameraStopped()
            try await fixture.finishTransition()
            try fixture.assertCollapsed()

            try await fixture.open(.hovered)
            try fixture.assertExpandedContent()
        }
    }

    func testPinnedCameraCollapseCanReopenAndCloseAgain() async throws {
        for reduced in [false, true] {
            let fixture = try CameraExitRenderingFixture(reduced: reduced)
            defer { fixture.stop() }
            try await fixture.open(.expanded)
            try await fixture.openCamera()

            fixture.model.collapse()
            fixture.assertCameraStopped()
            try await fixture.finishTransition()
            try fixture.assertCollapsed()
            try await fixture.open(.expanded)
            try fixture.assertExpandedContent()

            // A recovered-looking page must still respond to the next close.
            fixture.model.collapse()
            try await fixture.finishTransition()
            try fixture.assertCollapsed()
        }
    }

    func testClosingCameraIndependentlyRestoresTheMountedPage() async throws {
        for reduced in [false, true] {
            let fixture = try CameraExitRenderingFixture(reduced: reduced)
            defer { fixture.stop() }
            try await fixture.open(.expanded)
            try await fixture.openCamera()
            fixture.camera.closePreview()
            fixture.assertCameraStopped()
            try await fixture.finishTransition()
            try fixture.assertExpandedContent()

            // Repeat the utility interaction before leaving the shell altogether.
            try await fixture.openCamera()
            fixture.camera.togglePreview(source: fixture.model.cameraPresentationSource)
            fixture.assertCameraStopped()
            try await fixture.finishTransition()
            try fixture.assertExpandedContent()
            fixture.model.collapse()
            try await fixture.finishTransition()
            try fixture.assertCollapsed()
        }
    }

    func testRapidCameraCollapseReversalRestoresContentAndRemainsDismissible() async throws {
        for reduced in [false, true] {
            let fixture = try CameraExitRenderingFixture(reduced: reduced)
            defer { fixture.stop() }
            try await fixture.open(.expanded)
            try await fixture.openCamera()

            fixture.model.collapse()
            fixture.assertCameraStopped()
            // Let the persistent native host receive the closing target before reversal.
            try await Task.sleep(for: .milliseconds(32))
            fixture.model.setExpanded(true)
            fixture.model.pageModel.selectedPage = .music
            try await fixture.finishTransition()
            try fixture.assertExpandedContent()

            fixture.model.collapse()
            try await fixture.finishTransition()
            try fixture.assertCollapsed()
        }
    }
}

@MainActor
private final class CameraExitRenderingFixture {
    let service = MockCameraService(authorization: .authorized)
    let model: DynamicIslandPresentationModel
    let camera: CameraModel
    private let layout: NotchPanelLayout
    private let host: NSHostingView<AnyView>
    private let window: NSWindow
    private let preferences: UserDefaults
    private let suite = "notchium.camera.exit-rendering.\(UUID())"
    private var prepared = false

    init(reduced: Bool) throws {
        preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        camera = CameraModel(service: service, preferences: preferences)
        model = DynamicIslandPresentationModel()
        model.setReduceMotion(reduced)
        model.cameraController = camera
        model.mediaRenderer = CameraExitMusicRenderer()
        model.pageModel.defaultPage = .music
        let display = NotchiumDisplaySnapshot(
            id: .init(rawValue: 1), name: "Camera exit rendering fixture",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            isBuiltIn: false, isPrimary: true, statusBarThickness: 38)
        layout = NotchGeometryResolver.layout(
            for: .init(display: display, mode: .virtualPill), state: .collapsed)
        let size = layout.panelFrame.size
        host = NSHostingView(rootView: AnyView(NotchiumShellView(
            model: model, layout: layout,
            renderConfiguration: .init(appearance: .dark, reduceMotion: reduced ? .on : .off))
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.3))))
        host.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = host
        window.orderBack(nil)
    }

    func open(_ state: NotchStableState) async throws {
        if !prepared {
            // Mount the collapsed production tree before its first target change.
            // Otherwise an offscreen host can defer its initial body until the sample.
            _ = try pixels()
            try await Task.sleep(for: .milliseconds(100))
            prepared = true
        }
        if state == .hovered {
            model.setHovered(true)
            try await Task.sleep(for: .milliseconds(180))
        } else {
            model.setExpanded(true)
        }
        model.pageModel.selectedPage = .music
        try await finishTransition()
        XCTAssertEqual(model.visualState, state)
        try assertExpandedContent()
    }

    func openCamera() async throws {
        camera.togglePreview(source: model.cameraPresentationSource)
        await drainTasks()
        _ = try pixels()
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(camera.isPreviewPresented)
        XCTAssertEqual(camera.status, .live)
        XCTAssertTrue(service.isRunning)
        XCTAssertLessThan(try pixels().red, 10,
                          "The real Camera preview must replace the selected Music page before exit")
    }

    func finishTransition() async throws {
        await drainTasks()
        // Force the target update through this offscreen native host before waiting
        // for the production model and SwiftUI springs, both using real time.
        _ = try pixels()
        try await Task.sleep(for: .milliseconds(650))
    }

    func drainTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func assertCameraStopped(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(camera.isPreviewPresented, file: file, line: line)
        XCTAssertFalse(service.isRunning, "Capture must stop when closing begins", file: file, line: line)
        XCTAssertEqual(camera.status, .idle, file: file, line: line)
    }

    func assertCollapsed(file: StaticString = #filePath, line: UInt = #line) throws {
        let sample = try pixels()
        XCTAssertEqual(model.surfaceState, .collapsed, file: file, line: line)
        XCTAssertEqual(sample.height, layout.collapsedVisibleFrame.height, accuracy: 2,
                       "The mounted shell must actually retract, even after Camera removal", file: file, line: line)
        XCTAssertLessThan(sample.red, 10, file: file, line: line)
    }

    func assertExpandedContent(file: StaticString = #filePath, line: UInt = #line) throws {
        let sample = try pixels()
        XCTAssertNotEqual(model.surfaceState, .collapsed, file: file, line: line)
        XCTAssertEqual(model.pageModel.selectedPage, .music, file: file, line: line)
        XCTAssertEqual(sample.height, layout.expandedSize.height, accuracy: 2,
                       "The mounted shell must reach its expanded geometry", file: file, line: line)
        XCTAssertGreaterThan(sample.red, 5_000,
                             "The page must return visibly; an expanded black shell is unusable", file: file, line: line)
    }

    private func pixels() throws -> (height: CGFloat, red: Int) {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsHigh) / host.bounds.height
        let image = try XCTUnwrap(bitmap.cgImage)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let bytesPerRow = bitmap.pixelsWide * 4
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * bitmap.pixelsHigh)
        return try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
            let channels = bytes.bindMemory(to: UInt8.self)
            var bottom = 0
            var red = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let offset = y * bytesPerRow + x * 4
                    if channels[offset] > 191, channels[offset + 1] < 102, channels[offset + 2] < 102 {
                        red += 1
                    }
                }
                // Read only the center pixel to find the silhouette's lower edge.
                // One CGContext conversion avoids hundreds of thousands of NSColor calls.
                let center = y * bytesPerRow + bitmap.pixelsWide / 2 * 4
                if max(abs(Int(channels[center]) - 77), abs(Int(channels[center + 1]) - 77),
                       abs(Int(channels[center + 2]) - 77)) > 21 {
                    bottom = y + 1
                }
            }
            return (CGFloat(bottom) / scale, red)
        }
    }

    func stop() {
        model.reset()
        camera.stop()
        window.close()
        preferences.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class CameraExitMusicRenderer: NotchMediaRendering {
    var collapsedMediaVisible: Bool { false }
    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView { AnyView(EmptyView()) }
    func expandedMedia() -> AnyView { AnyView(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(EmptyView()) }
}
