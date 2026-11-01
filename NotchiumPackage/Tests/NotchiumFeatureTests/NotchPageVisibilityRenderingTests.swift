import AppKit
import NotchiumDesignSystem
import Observation
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland

@MainActor
final class NotchPageVisibilityRenderingTests: XCTestCase {
    func testPageChangesNeverShowTwoLayoutsAndKeepAllPagesMounted() async throws {
        for reduced in [false, true] {
            let fixture = PageVisibilityFixture(reduced: reduced)
            defer { fixture.window.close() }
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertGreaterThan(try fixture.sample().levels[0], 0.95)

            fixture.state.selection = 1
            let samples = try await fixture.record(for: .milliseconds(300))
            for sample in samples { XCTAssertLessThanOrEqual(sample.visiblePages, 1) }
            try XCTSkipIf(!samples.contains(where: \.isIntermediate),
                          "Native hosting did not expose an intermediate page fade")
            XCTAssertGreaterThan(try fixture.sample().levels[1], 0.95)
            XCTAssertEqual(fixture.state.mounts, [1, 1, 1])
        }
    }

    func testRapidSelectionAndReversalNeverRevealAnObsoletePage() async throws {
        for reduced in [false, true] {
            let fixture = PageVisibilityFixture(reduced: reduced)
            defer { fixture.window.close() }
            try await Task.sleep(for: .milliseconds(80))
            fixture.state.selection = 1
            for selection in [2, 0, 1, 2] {
                let samples = try await fixture.record(for: .milliseconds(25))
                for sample in samples { XCTAssertLessThanOrEqual(sample.visiblePages, 1) }
                fixture.state.selection = selection
            }
            let samples = try await fixture.record(for: .milliseconds(300))
            for sample in samples { XCTAssertLessThanOrEqual(sample.visiblePages, 1) }
            XCTAssertGreaterThan(try fixture.sample().levels[2], 0.95)
            XCTAssertEqual(fixture.state.mounts, [1, 1, 1])
        }
    }
}

private struct PageVisibilitySample {
    let levels: [CGFloat]

    var visiblePages: Int { levels.filter { $0 > 0.04 }.count }
    var isIntermediate: Bool { levels.contains { $0 > 0.05 && $0 < 0.95 } }
}

@MainActor
private final class PageVisibilityFixture {
    let state = PageVisibilityState()
    let host: NSHostingView<AnyView>
    let window: NSWindow
    private let size = CGSize(width: 80, height: 80)

    init(reduced: Bool) {
        let state = state
        host = NSHostingView(rootView: AnyView(PageVisibilitySurface(state: state)
            .environment(\.notchReduceMotionOverride, reduced)))
        host.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = host
        window.orderBack(nil)
    }

    func record(for duration: Duration) async throws -> [PageVisibilitySample] {
        let end = ContinuousClock.now + duration
        var samples: [PageVisibilitySample] = []
        repeat {
            samples.append(try sample())
            try await Task.sleep(for: .milliseconds(8))
        } while ContinuousClock.now < end
        return samples
    }

    func sample() throws -> PageVisibilitySample {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        func brightness(at x: Int) throws -> CGFloat {
            let color = try XCTUnwrap(bitmap.colorAt(x: x * bitmap.pixelsWide / 80,
                                                   y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            return color.redComponent
        }
        return try .init(levels: [brightness(at: 14), brightness(at: 40), brightness(at: 66)])
    }
}

@MainActor
@Observable
private final class PageVisibilityState {
    var selection = 0
    @ObservationIgnored var mounts = [0, 0, 0]
}

private struct PageVisibilitySurface: View {
    let state: PageVisibilityState

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                ZStack(alignment: .leading) {
                    Color.clear
                    Color.white.frame(width: 16, height: 16).offset(x: CGFloat(index * 26 + 6))
                }
                    .overlay(alignment: .topLeading) {
                        PageMountProbe(state: state, index: index).frame(width: 1, height: 1)
                    }
                    .modifier(NotchPageVisibility(isVisible: state.selection == index))
            }
        }
        .frame(width: 80, height: 80)
        .background(.black)
    }
}

private struct PageMountProbe: NSViewRepresentable {
    let state: PageVisibilityState
    let index: Int

    func makeNSView(context: Context) -> NSView {
        state.mounts[index] += 1
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
