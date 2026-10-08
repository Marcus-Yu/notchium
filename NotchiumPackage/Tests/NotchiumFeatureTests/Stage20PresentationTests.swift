import AppKit
import SwiftUI
import XCTest
import NotchiumCore
import NotchiumDesignSystem
import NotchiumServices
import NotchiumPersistence
@testable import NotchiumDynamicIsland
@testable import NotchiumQuickActionsFeature
@testable import NotchiumMediaFeature
@testable import NotchiumCalendarFeature

@MainActor final class Stage20PresentationTests: XCTestCase {
    func testBoundedHomeAndEditorFixtures() async throws {
        let suite = "Stage20.Rendering.\(UUID())"
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
        let actions = QuickActionsModel(store: store, runner: runner, reminder: reminder)
        let media = MediaSessionController(provider: MockMediaProvider(), coordinator: presentation.activityCoordinator)
        media.receive(.init(connectionState: .authenticated, playbackState: .paused,
            title: "Midnight City", artist: "M83", elapsed: 81, duration: 244, trackID: "midnight",
            artwork: URL(string: "notchium-fixture://artwork/midnight"), source: .spotify,
            capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true)))
        let calendar = CalendarActivityModel(service: MockCalendarService(), coordinator: presentation.activityCoordinator)
        calendar.receive(.init(availability: .available, upcomingEvents: [
            .init(id: UUID(), title: "Design review with the product team", startDate: Date().addingTimeInterval(3600),
                  endDate: Date().addingTimeInterval(7200)),
            .init(id: UUID(), title: "Weekly planning", startDate: Date().addingTimeInterval(10800),
                  endDate: Date().addingTimeInterval(14400))
        ], permission: .granted))
        defer { runner.stop(); media.stop(); calendar.stop(); presentation.reset() }
        presentation.pageModel.selectedPage = .home
        let homeSize = CGSize(width: 524, height: 228) // 266 pt shell minus the 38 pt hardware region.
        func home() -> some View {
            NotchPagesView(model: presentation.pageModel, mediaRenderer: media, calendarRenderer: calendar,
                           audioRenderer: nil, isExpanded: true, quickActions: actions)
                .frame(width: homeSize.width, height: homeSize.height).foregroundStyle(.white).background(.black)
                .environment(\.colorScheme, .dark)
        }
        try await render(home(), name: "default", size: homeSize)
        XCTAssertEqual(store.configuration.primarySections, [.media, .calendar])
        try store.setSectionEnabled(.shortcuts, enabled: true)
        XCTAssertFalse(actions.showsHomeActions)
        try store.save(.init(kind: .url, displayName: "Calendar", target: "https://example.com", pinnedToHome: true))
        try await render(home(), name: "one", size: homeSize)
        XCTAssertEqual(actions.homeSections, [.media, .calendar])
        for name in ["Projects", "Learn", "Downloads", "Morning"] {
            try store.save(.init(kind: .url, displayName: name, target: "https://example.com", pinnedToHome: true))
        }
        try store.setSectionEnabled(.shortcuts, enabled: true)
        try await render(home(), name: "several", size: homeSize)
        try await render(Form { HomeSettingsSections(model: actions) }.formStyle(.grouped), name: "customization", size: CGSize(width: 570, height: 620))
        try await render(QuickActionEditor(action: .init(kind: .url, displayName: "Course", target: "https://learn.uwaterloo.ca", pinnedToHome: true), model: actions),
                         name: "add", size: CGSize(width: 420, height: 360))
        workspace.failure = .unavailable
        await runner.validate(try XCTUnwrap(store.actions.first))
        workspace.failure = nil
        try await render(home(), name: "unavailable", size: homeSize)
        for index in 0..<30 {
            try store.save(.init(kind: .url, displayName: "Very long shortcut name \(index)", target: "https://example.com", pinnedToHome: true))
        }
        try store.move(from: IndexSet(integer: 4), to: 0)
        try await render(home(),
                         name: "dense", size: homeSize)
        XCTAssertEqual(store.pinned.count, 35)
        XCTAssertEqual(actions.homeSections, [.media, .calendar])
    }
    private func render(_ view: some View, name: String, size: CGSize) async throws {
        let capturesWindow = ProcessInfo.processInfo.environment["NOTCHIUM_STAGE20_QA"] == "1"
            && ["default", "one", "several"].contains(name)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let origin = capturesWindow ? CGPoint(x: 100, y: 100) : CGPoint(x: -10000, y: -10000)
        let window = NSWindow(contentRect: CGRect(origin: origin, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.backgroundColor = .windowBackgroundColor
        if capturesWindow { window.orderFrontRegardless() }
        else { window.orderBack(nil) }
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(host.frame.size, size)
        host.displayIfNeeded()
        if !capturesWindow {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertNotNil(bitmap.representation(using: .png, properties: [:]))
        }
        // Capture only the three requested Home states, including the existing navigation header.
        if capturesWindow {
            // Native controls use composited layers; capture an actual fixture window rather
            // than ImageRenderer's unsupported-control placeholders or offscreen cache gaps.
            try await Task.sleep(for: .milliseconds(600))
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber),
                                 "/private/tmp/notchium-stage20-\(name).png"]
            try capture.run()
            capture.waitUntilExit()
            XCTAssertEqual(capture.terminationStatus, 0)
        }
    }
}
