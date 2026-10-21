import AppKit
import Observation
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

/// Exercises one mounted SwiftUI surface. Static ImageRenderer samples cannot establish
/// whether a revision cancels a spring whose stored target is already collapsed.
@MainActor
final class SpaceTransitionRenderingTests: XCTestCase {
    func testSpaceSettleCancelsClosingSpringWithoutReplacingMountedContent() async throws {
        let fixture = SpaceRenderingFixture()
        let host = NSHostingView(rootView: SpaceRenderingSurface(fixture: fixture))
        let size = CGSize(width: 600, height: 322)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        window.orderBack(nil)
        defer { window.close() }

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertGreaterThan(try blackRows(in: host), 260)
        XCTAssertEqual(fixture.probe.mountCount, 1)

        fixture.expanded = false
        var intermediateRows: Int?
        for _ in 0..<15 {
            try await Task.sleep(for: .milliseconds(16))
            let rows = try blackRows(in: host)
            if rows > 45, rows < 260 {
                intermediateRows = rows
                break
            }
        }
        // Offscreen hosting does not animate on every runner. Without an observed
        // intermediate frame, this environment cannot verify live cancellation.
        try XCTSkipIf(intermediateRows == nil, "Offscreen native hosting did not expose an intermediate closing frame")

        // Only the revision changes here: renderedShape already stores the collapsed target.
        fixture.systemTransitionRevision += 1
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertLessThanOrEqual(try blackRows(in: host), 40, "The next frame must use collapsed geometry")
        XCTAssertEqual(fixture.probe.mountCount, 1, "The mounted child must survive the settle")
        XCTAssertEqual(fixture.probe.dismantleCount, 0)

        // A completion from the interrupted spring must not bring the old surface back.
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertLessThanOrEqual(try blackRows(in: host), 40)
        XCTAssertEqual(fixture.probe.mountCount, 1)
        XCTAssertEqual(fixture.probe.dismantleCount, 0)
    }

    private func blackRows(in host: NSView) throws -> Int {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let centerX = bitmap.pixelsWide / 2
        var rows = 0
        for y in 0..<bitmap.pixelsHigh {
            let color = try XCTUnwrap(bitmap.colorAt(x: centerX, y: y)?.usingColorSpace(.deviceRGB))
            if color.redComponent < 0.1, color.greenComponent < 0.1, color.blueComponent < 0.1 {
                rows += 1
            }
        }
        // Caching normally uses backing pixels; return logical-point rows on Retina hosts.
        return Int((CGFloat(rows) * host.bounds.height / CGFloat(bitmap.pixelsHigh)).rounded())
    }
}

@MainActor
@Observable
private final class SpaceRenderingFixture {
    var expanded = true
    var systemTransitionRevision = 0
    let probe = SpaceRenderingMountProbe()
}

@MainActor
private final class SpaceRenderingMountProbe {
    var mountCount = 0
    var dismantleCount = 0
}

private struct SpaceRenderingSurface: View {
    let fixture: SpaceRenderingFixture

    var body: some View {
        let passive = NotchShape(width: 212, height: 38, centerX: 300,
                                 topCornerRadius: 0, bottomCornerRadius: 8)
        NotchTransitionSurface(
            expanded: fixture.expanded,
            shape: NotchShellSurface(width: fixture.expanded ? 524 : 212,
                                     height: fixture.expanded ? 266 : 38,
                                     centerX: 300, bottomRadius: fixture.expanded ? 26 : 8,
                                     passiveShape: passive),
            reduceMotion: false,
            systemTransitionRevision: fixture.systemTransitionRevision
        ) { _ in
            SpaceRenderingProbeView(probe: fixture.probe).frame(width: 1, height: 1)
        }
        .frame(width: 600, height: 322)
        .background(.white)
    }
}

private struct SpaceRenderingProbeView: NSViewRepresentable {
    let probe: SpaceRenderingMountProbe

    func makeNSView(context: Context) -> NSView {
        probe.mountCount += 1
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> SpaceRenderingMountProbe { probe }

    static func dismantleNSView(_ nsView: NSView, coordinator: SpaceRenderingMountProbe) {
        coordinator.dismantleCount += 1
    }
}
