import AppKit
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation
import SwiftUI
import XCTest
@testable import NotchiumCalendarFeature

@MainActor
final class CalendarPermissionViewTests: XCTestCase {
    func testMountedHiddenPageRefreshesPermissionOnlyWhenShown() async throws {
        let service = PermissionViewCalendarService(permission: .denied)
        let model = makeModel(service: service)
        let visibility = CalendarPermissionPageVisibility()
        let (host, window) = makeHost(model: model, visibility: visibility)
        model.start()
        defer { window.close(); model.stop() }
        try await settle(host)

        XCTAssertEqual(model.snapshot.permission, .denied)
        XCTAssertEqual(service.refreshCount, 0, "Mounted hidden pages must not reload calendars")
        XCTAssertEqual(service.requestCount, 0)
        XCTAssertFalse(window.isKeyWindow)

        // Simulate access changing in System Settings without an app-activation event.
        service.snapshot = CalendarSnapshot(availability: .available, permission: .granted)
        visibility.visible = true
        try await settle(host)
        XCTAssertEqual(service.refreshCount, 1)
        XCTAssertEqual(model.snapshot.permission, .granted)
        XCTAssertEqual(service.requestCount, 0, "Showing Calendar checks access without prompting")
        XCTAssertFalse(window.isKeyWindow, "A nonactivating notch must recover permission too")

        visibility.visible = false
        try await settle(host)
        XCTAssertEqual(service.refreshCount, 1)
        visibility.visible = true
        try await settle(host)
        XCTAssertEqual(service.refreshCount, 2, "Each new visible presentation rechecks access")
        XCTAssertEqual(service.requestCount, 0)
    }

    func testPartialAndDeniedPermissionStatesRenderWithinCalendarPage() async throws {
        // Offscreen NSHostingView fixtures do not expose SwiftUI accessibility children.
        // These captures cover native layout; service tests cover permission actions.
        for (permission, name) in [(CalendarPermission.needsFullAccess, "full-access"), (.denied, "denied")] {
            let service = PermissionViewCalendarService(permission: permission)
            let model = makeModel(service: service)
            let visibility = CalendarPermissionPageVisibility(visible: true)
            let (host, window) = makeHost(model: model, visibility: visibility)
            model.start()
            defer { window.close(); model.stop() }
            try await settle(host)

            XCTAssertEqual(model.snapshot.permission, permission)
            XCTAssertEqual(service.requestCount, 0, "Rendering permission recovery must never prompt")
            try assertNativeRendering(host, name: name)
        }
    }

    private func makeModel(service: PermissionViewCalendarService) -> CalendarActivityModel {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 1_800_000_000),
                                 automaticallyAdvances: false)
        return CalendarActivityModel(service: service,
            coordinator: ActivityCoordinator(clock: clock), clock: clock, openMeeting: { _ in })
    }

    private func makeHost(model: CalendarActivityModel, visibility: CalendarPermissionPageVisibility)
        -> (NSHostingView<AnyView>, NSWindow) {
        let host = NSHostingView(rootView: AnyView(CalendarPermissionPageHarness(
            model: model, visibility: visibility)
            .frame(width: 524, height: 196)
            .background(.black)
            .environment(\.colorScheme, .dark)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }))
        host.frame = CGRect(x: 0, y: 0, width: 524, height: 196)
        host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 524, height: 196),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        return (host, window)
    }

    private func settle(_ host: NSView) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    private func assertNativeRendering(_ host: NSView, name: String) throws {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(bitmap.size, CGSize(width: 524, height: 196))
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        var contentBounds = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      min(color.redComponent, color.greenComponent, color.blueComponent) > 0.3 else { continue }
                contentBounds = contentBounds.union(CGRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale,
                                                           width: 1 / scale, height: 1 / scale))
            }
        }
        XCTAssertGreaterThan(contentBounds.width, 150, "Permission copy and controls must render")
        XCTAssertGreaterThan(contentBounds.height, 70)
        XCTAssertGreaterThan(contentBounds.minX, 20)
        XCTAssertLessThan(contentBounds.maxX, 504)
        XCTAssertGreaterThan(contentBounds.minY, 4)
        XCTAssertLessThan(contentBounds.maxY, 192, "Permission content must retain vertical breathing room")
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/notchium-calendar-permission-\(name).png"))
    }
}

@MainActor @Observable
private final class CalendarPermissionPageVisibility {
    var visible: Bool
    init(visible: Bool = false) { self.visible = visible }
}

private struct CalendarPermissionPageHarness: View {
    let model: CalendarActivityModel
    let visibility: CalendarPermissionPageVisibility
    var body: some View {
        CalendarActivityView(model: model)
            .environment(\.notchCalendarPageVisible, visibility.visible)
    }
}

@MainActor
private final class PermissionViewCalendarService: CalendarService {
    var snapshot: CalendarSnapshot
    private(set) var refreshCount = 0
    private(set) var requestCount = 0
    private var continuations: [AsyncStream<CalendarSnapshot>.Continuation] = []

    init(permission: CalendarPermission) {
        snapshot = CalendarSnapshot(availability: .unavailable(.permissionDenied), permission: permission)
    }

    func availability() async -> FeatureAvailability { snapshot.availability }
    func updates() async -> AsyncStream<CalendarSnapshot> {
        let pair = AsyncStream<CalendarSnapshot>.makeStream()
        continuations.append(pair.continuation)
        pair.continuation.yield(snapshot)
        return pair.stream
    }
    func refresh() async throws {
        refreshCount += 1
        continuations.forEach { $0.yield(snapshot) }
    }
    func requestAccess() async { requestCount += 1 }
    func setCalendarSelected(_ id: String, selected: Bool) async {}
    func stop() async {
        continuations.forEach { $0.finish() }
        continuations.removeAll()
    }
}
