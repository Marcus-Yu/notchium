import AppKit
import SwiftUI
import XCTest
import NotchiumCore
import NotchiumPersistence
import NotchiumServices
@testable import NotchiumDynamicIsland
@testable import NotchiumQuickActionsFeature
@testable import NotchiumMediaFeature
@testable import NotchiumCalendarFeature

@MainActor final class Stage11PresentationTests: XCTestCase {
    func testHomeAndNativeComposerFixtures() async throws {
        let suite = "Stage11Visual.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let store = QuickActionStore(preferences: preferences)
        let workspace = NativeQuickActionWorkspace()
        let runner = QuickActionRunner(store: store, workspace: workspace, shortcuts: MockShortcutService(),
            notifications: presentation.notificationCoordinator, clock: clock)
        let reminder = QuickReminderModel(service: MockReminderService(), workspace: workspace, store: store,
            notifications: presentation.notificationCoordinator, clock: clock)
        let actions = QuickActionsModel(store: store, runner: runner, reminder: reminder)
        for label in ["Safari", "Morning", "Projects", "Website"] {
            try store.save(QuickAction(kind: .url, displayName: label, target: "https://example.com", pinnedToHome: true))
        }
        store.showOnHome = true
        let media = MediaSessionController(provider: MockMediaProvider(), coordinator: presentation.activityCoordinator)
        media.receive(.init(connectionState: .authenticated, playbackState: .paused,
            title: "Midnight City", artist: "M83", elapsed: 81, duration: 244, trackID: "midnight",
            artwork: URL(string: "notchium-fixture://artwork/midnight"), source: .spotify,
            capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true)))
        let calendar = CalendarActivityModel(service: MockCalendarService(), coordinator: presentation.activityCoordinator)
        calendar.receive(.init(availability: .available, upcomingEvents: [
            .init(id: UUID(), title: "Design review with the product team", startDate: Date().addingTimeInterval(3600),
                  endDate: Date().addingTimeInterval(7200))
        ], permission: .granted))
        defer { runner.stop(); media.stop(); calendar.stop(); presentation.reset() }
        let home = HomeDashboardView(pages: presentation.pageModel, media: media, calendar: calendar, quickActions: actions)
            .frame(width: 524, height: 196).foregroundStyle(.white).background(.black)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: home)
        host.frame = CGRect(x: 0, y: 0, width: 524, height: 196)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(containsScrollView(host), "Stage 20 bounds shortcut scrolling inside Home")
        XCTAssertEqual(host.frame.height, 196)
        try await render(home, name: "home-four-actions", size: CGSize(width: 524, height: 196))
        await reminder.prepare()
        reminder.draft.title = "Call dentist"
        try await render(QuickReminderComposer(model: reminder, close: {}), name: "reminder", size: CGSize(width: 352, height: 160))
        reminder.draft.includesTime = true
        try await render(QuickReminderComposer(model: reminder, close: {}), name: "reminder-timed", size: CGSize(width: 352, height: 190))
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            try await render(QuickReminderComposer(model: reminder, close: {})
                .foregroundStyle(.white).environment(\.colorScheme, scheme),
                name: "reminder-\(name)", size: CGSize(width: 352, height: 190))
            try await render(HStack {
                NotchUtilityLabel(symbol: "cup.and.saucer.fill", isHovered: false)
                NotchUtilityLabel(symbol: "checklist", isHovered: false)
                NotchUtilityLabel(symbol: "gearshape.fill", isHovered: false)
                NotchUtilityLabel(symbol: "xmark", isHovered: false)
                NotchUtilityLabel(symbol: "checklist", isHovered: true, isSelected: true)
            }.padding().background(.black).environment(\.colorScheme, scheme),
                name: "utilities-\(name)", size: CGSize(width: 220, height: 64))
        }
        try await render(Form { QuickActionsSettings(model: actions) }.formStyle(.grouped),
                   name: "settings", size: CGSize(width: 520, height: 540))
    }
    private func containsScrollView(_ view: NSView) -> Bool {
        view is NSScrollView || view.subviews.contains { containsScrollView($0) }
    }
    private func render(_ view: some View, name: String, size: CGSize) async throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.backgroundColor = .windowBackgroundColor
        window.orderBack(nil)
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/notchium-stage11-\(name).png"))
    }
}
