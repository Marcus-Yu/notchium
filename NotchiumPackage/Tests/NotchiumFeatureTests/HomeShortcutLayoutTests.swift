import AppKit
import SwiftUI
import XCTest
import NotchiumCore
import NotchiumPersistence
import NotchiumServices
@testable import NotchiumDynamicIsland
@testable import NotchiumQuickActionsFeature

@MainActor final class HomeShortcutLayoutTests: XCTestCase {
    func testAdaptiveShortcutSegmentsFillTheBarAndCenterTheirContents() async throws {
        for count in 1...4 {
            let suite = "Home.ShortcutLayout.\(UUID())"
            let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { preferences.removePersistentDomain(forName: suite) }
            let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
            let presentation = DynamicIslandPresentationModel(clock: clock)
            let store = QuickActionStore(preferences: preferences)
            let workspace = Stage20Workspace()
            let runner = QuickActionRunner(store: store, workspace: workspace, shortcuts: CountingStage20Shortcuts(),
                                           notifications: presentation.notificationCoordinator, clock: clock)
            let reminder = QuickReminderModel(service: MockReminderService(), workspace: workspace, store: store,
                                              notifications: presentation.notificationCoordinator, clock: clock)
            let model = QuickActionsModel(store: store, runner: runner, reminder: reminder)
            defer { runner.stop(); presentation.reset() }
            for name in ["Calendar", "Projects", "Learn", "Downloads"].prefix(count) {
                try store.save(.init(kind: .url, displayName: name, target: "https://example.com",
                                     symbol: "star", pinnedToHome: true))
            }
            let width: CGFloat = 464
            let view = HomeQuickActionsView(model: model)
                .frame(width: width, height: 38).background(.black).environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: width, height: 38),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderBack(nil)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / width
            XCTAssertEqual(CGFloat(bitmap.pixelsHigh) / scale, 38)
            let segmentWidth = (460 - CGFloat(count - 1) * 6) / CGFloat(count)
            for index in 0..<count {
                let start = 2 + CGFloat(index) * (segmentWidth + 6)
                let end = start + segmentWidth
                let left = Int((start + 1) * scale)
                let right = Int((end - 1) * scale)
                // Both edges have a filled surface; gaps remain black.
                XCTAssertGreaterThan(try brightness(bitmap, x: left, y: Int(19 * scale)), 0.03)
                XCTAssertGreaterThan(try brightness(bitmap, x: right, y: Int(19 * scale)), 0.03)
                if index + 1 < count {
                    XCTAssertLessThan(try brightness(bitmap, x: Int((end + 3) * scale), y: Int(19 * scale)), 0.01)
                }
                var ink: [Int] = []
                for x in left...right {
                    for y in Int(8 * scale)..<Int(30 * scale) where try brightness(bitmap, x: x, y: y) > 0.4 {
                        ink.append(x)
                        break
                    }
                }
                let inkCenter = CGFloat(try XCTUnwrap(ink.first) + XCTUnwrap(ink.last)) / 2
                XCTAssertEqual(inkCenter, (start + segmentWidth / 2) * scale, accuracy: 2 * scale,
                               "Shortcut contents must be centered within their own segment")
            }
            if ProcessInfo.processInfo.environment["NOTCHIUM_STAGE20_QA"] == "1" {
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: "/private/tmp/notchium-home-adaptive-\(count).png"))
            }
        }
    }

    private func brightness(_ bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> CGFloat {
        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        return max(color.redComponent, color.greenComponent, color.blueComponent)
    }
}
