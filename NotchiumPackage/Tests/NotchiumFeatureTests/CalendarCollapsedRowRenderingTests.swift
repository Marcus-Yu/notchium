import AppKit
import NotchiumCore
import NotchiumFocusFeature
import NotchiumServices
import SwiftUI
import XCTest
@testable import NotchiumCalendarFeature
@testable import NotchiumDynamicIsland

@MainActor
final class CalendarCollapsedRowRenderingTests: XCTestCase {
    func testCalendarPreservesNormalTimerAndMusicDetailsAcrossMotionPreferences() async throws {
        for reduced in [false, true] {
            for (music, preference) in [(true, CollapsedTimerPreference.timer), (false, .timer), (true, .music)] {
                let fixture = try CalendarCollapsedRowFixture(music: music, preference: preference, reduced: reduced)
                defer { fixture.stop() }
                try await Task.sleep(for: .milliseconds(400))
                let before = try topRowInk(fixture.snapshot(), fixture: fixture)
                try fixture.saveSnapshot("before-\(music)-\(preference.rawValue)-\(reduced)")
                XCTAssertGreaterThan(fixture.layout.hardwareNotchGeometry?.frame.width ?? 0, 0)
                XCTAssertEqual(before.red.isEmpty, !music)
                XCTAssertEqual(before.blue.isEmpty, !music)
                if preference == .timer {
                    XCTAssertGreaterThan(before.white.count, 30, "The real timer must show its full countdown")
                }
                let rowID = fixture.model.collapsedRowNotification?.id
                let indicatorIDs = fixture.model.presentedIndicators.map(\.id)

                await fixture.showCalendar()
                try await Task.sleep(for: .milliseconds(500))
                XCTAssertEqual(fixture.model.presentedNotification?.presentationStyle, .calendar)
                XCTAssertEqual(fixture.model.collapsedRowNotification?.id, rowID)
                XCTAssertEqual(fixture.model.presentedIndicators.map(\.id), indicatorIDs)
                let after = try topRowInk(fixture.snapshot(), fixture: fixture)
                try fixture.saveSnapshot("calendar-\(music)-\(preference.rawValue)-\(reduced)")
                assertSameRow(before, after,
                              scenario: "music=\(music), preference=\(preference.rawValue), reduced=\(reduced)")

                fixture.calendar.reminders.dismiss()
                if music && !reduced {
                    for _ in 0..<6 {
                        try await Task.sleep(for: .milliseconds(16))
                        assertSameRow(before, try topRowInk(fixture.snapshot(), fixture: fixture),
                                      scenario: "Calendar dismissal with \(preference.rawValue) preference")
                    }
                }
                try await Task.sleep(for: .milliseconds(400))
                assertSameRow(before, try topRowInk(fixture.snapshot(), fixture: fixture),
                              scenario: "Restored row after Calendar dismissal")
            }
        }
    }

    func testTimerMusicRowRemainsVisibleDuringCalendarGrowth() async throws {
        let fixture = try CalendarCollapsedRowFixture(music: true, preference: .timer, reduced: false)
        defer { fixture.stop() }
        try await Task.sleep(for: .milliseconds(400))
        let before = try topRowInk(fixture.snapshot(), fixture: fixture)
        await fixture.showCalendar()

        let restingHeight = fixture.layout.collapsedVisibleFrame.height
        let expandedHeight = restingHeight + NotchReminderGeometry.minimumHeight
        var observedGrowingFrame = false
        for _ in 0..<16 {
            try await Task.sleep(for: .milliseconds(16))
            let bitmap = try fixture.snapshot()
            let height = try shellHeight(bitmap, fixture: fixture)
            if height > restingHeight + 2, height < expandedHeight - 2 {
                observedGrowingFrame = true
                assertSameRow(before, try topRowInk(bitmap, fixture: fixture),
                              scenario: "Calendar growth at height \(height)")
            }
            if height >= expandedHeight - 2 { break }
        }
        try XCTSkipIf(!observedGrowingFrame,
                      "Offscreen native hosting did not expose an intermediate Calendar growth frame")
    }

    private func topRowInk(_ bitmap: NSBitmapImageRep, fixture: CalendarCollapsedRowFixture) throws -> CalendarRowInk {
        var result = CalendarRowInk()
        let scale = CGFloat(bitmap.pixelsWide) / fixture.layout.panelFrame.width
        let height = min(bitmap.pixelsHigh, Int(fixture.layout.collapsedVisibleFrame.height * scale))
        for y in 0..<height {
            for x in 0..<bitmap.pixelsWide {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let index = y * bitmap.pixelsWide + x
                if color.redComponent > color.blueComponent + 0.4 {
                    result.red.insert(index)
                } else if color.blueComponent > color.redComponent + 0.4 {
                    result.blue.insert(index)
                } else if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.7 {
                    result.white.insert(index)
                    let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                    result.whiteBounds = result.whiteBounds.map { $0.union(pixel) } ?? pixel
                }
            }
        }
        return result
    }

    private func assertSameRow(_ expected: CalendarRowInk, _ actual: CalendarRowInk, scenario: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        // Compare foreground positions, not the banner's expanding black background.
        // Missing countdowns, moved artwork and duplicate rows all change these masks.
        for (name, before, after) in [("artwork", expected.red, actual.red),
                                      ("waveform", expected.blue, actual.blue)] {
            XCTAssertLessThanOrEqual(before.symmetricDifference(after).count, max(3, before.count / 100),
                                     "\(scenario): \(name) changed position, vanished, or overlapped another row",
                                     file: file, line: line)
        }
        // The real running countdown ticks between samples. Its size and bounds
        // remain stable even when individual digits change; missing countdowns,
        // replacement rings, and duplicated text violate these invariants.
        XCTAssertEqual(actual.white.count, expected.white.count,
                       accuracy: max(3, expected.white.count / 4),
                       "\(scenario): the timer's visible detail changed", file: file, line: line)
        if let before = expected.whiteBounds, let after = actual.whiteBounds {
            for (lhs, rhs) in [(before.minX, after.minX), (before.maxX, after.maxX),
                               (before.minY, after.minY), (before.maxY, after.maxY)] {
                XCTAssertEqual(lhs, rhs, accuracy: 2, "\(scenario): the timer moved", file: file, line: line)
            }
        }
    }

    private func shellHeight(_ bitmap: NSBitmapImageRep, fixture: CalendarCollapsedRowFixture) throws -> CGFloat {
        let scale = CGFloat(bitmap.pixelsWide) / fixture.layout.panelFrame.width
        let x = bitmap.pixelsWide / 2
        var bottom = 0
        for y in 0..<bitmap.pixelsHigh {
            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            if max(color.redComponent, color.greenComponent, color.blueComponent) < 0.1 { bottom = y + 1 }
        }
        return CGFloat(bottom) / scale
    }
}

private struct CalendarRowInk {
    var red = Set<Int>()
    var blue = Set<Int>()
    var white = Set<Int>()
    var whiteBounds: CGRect?
}

@MainActor
private final class CalendarCollapsedRowFixture {
    let model: DynamicIslandPresentationModel
    let calendar: CalendarActivityModel
    let layout: NotchPanelLayout
    private let timer: PomodoroModel
    private let host: NSHostingView<AnyView>
    private let window: NSWindow
    private let preferences: UserDefaults
    private let suite: String
    private let now: Date

    init(music: Bool, preference: CollapsedTimerPreference, reduced: Bool) throws {
        let now = Date()
        self.now = now
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        model = DynamicIslandPresentationModel(clock: clock)
        model.setReduceMotion(reduced)
        model.mediaRenderer = CalendarRowMediaRenderer()
        if music {
            model.activityCoordinator.present(.init(
                id: UUID(), key: .media, kind: .media, title: "Music", subtitle: nil,
                priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
                isDismissible: false, destination: .music, duration: nil,
                payload: .mediaPlayback(isPlaying: true, isLocal: true), minimal: .artwork))
        }
        suite = "notchium.calendar.collapsed-row.\(UUID())"
        preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        var state = PomodoroState()
        PomodoroEngine.start(&state, configuration: .standard, at: now.addingTimeInterval(-480))
        timer = PomodoroModel(store: InMemoryPomodoroStore(.init(state: state)), notifications: model.notificationCoordinator,
                              clock: clock, preferences: preferences, now: { now })
        timer.collapsedPreference = preference
        model.pomodoroRenderer = timer
        timer.start()
        calendar = CalendarActivityModel(service: MockCalendarService(), coordinator: model.activityCoordinator, clock: clock)
        model.calendarRenderer = calendar
        layout = NotchGeometryResolver.layout(
            for: .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
        let size = layout.panelFrame.size
        host = NSHostingView(rootView: AnyView(NotchiumShellView(model: model, layout: layout,
            renderConfiguration: .init(appearance: .dark, reduceMotion: reduced ? .on : .off))
            .frame(width: size.width, height: size.height).background(Color(white: 0.3))))
        host.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = host
        window.orderBack(nil)
    }

    func showCalendar() async {
        await calendar.reminders.update(events: [.init(
            id: UUID(), title: "Planning", startDate: now.addingTimeInterval(300),
            endDate: now.addingTimeInterval(3600))])
    }

    func snapshot() throws -> NSBitmapImageRep {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    func saveSnapshot(_ name: String) throws {
        let image = try snapshot()
        let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/notchium-calendar-row-\(name).png"))
    }

    func stop() {
        window.close()
        timer.stop()
        calendar.stop()
        model.reset()
        preferences.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class CalendarRowMediaRenderer: NotchMediaRendering {
    var collapsedMediaVisible: Bool { true }

    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView {
        AnyView(HStack(spacing: 0) {
            Color.red.frame(width: 24, height: 24).padding(.horizontal, 8)
            Color.clear.frame(width: hardwareWidth)
            Color.blue.frame(width: 22, height: 16).padding(.horizontal, 9)
        }.frame(height: hardwareHeight))
    }
    func expandedMedia() -> AnyView { AnyView(EmptyView()) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(Color.red.frame(width: size, height: size)) }
    func mediaWaveform() -> AnyView { AnyView(Color.blue.frame(width: 22, height: 16)) }
}
