import AppKit
import NotchiumCore
@testable import NotchiumCalendarFeature
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature
import NotchiumServices
import SwiftUI
import XCTest

@MainActor
final class CalendarReminderRenderingTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    func testCollapsedReminderVisualMatrix() async throws {
        let layout = NotchGeometryResolver.layout(
            for: NotchShellPlacement(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch),
            state: .collapsed)
        let shellWidth = NotchReminderGeometry.width(for: layout)
        let left = Int((layout.panelFrame.width - shellWidth) / 2)
        let right = left + Int(shellWidth)

        for music in [true, false] {
            for meeting in [true, false] {
                let clock = TestAppClock(now: base, automaticallyAdvances: false)
                let presentation = DynamicIslandPresentationModel(clock: clock)
                let capture = TestAudioCapture()
                let meter = SystemAudioMeter(capture: capture, permissionGranted: { true }, activityClock: clock)
                let media = MediaFeatureModel(provider: MockMediaProvider(),
                    coordinator: presentation.activityCoordinator, visibilityClock: clock, audioMeter: meter)
                presentation.mediaRenderer = media
                if music {
                    media.receive(.init(playbackState: .playing, title: "Fixture track", trackID: "1", source: .spotify))
                    for _ in 0..<30 { await Task.yield() }
                    capture.levels?([0.3, 0.6, 0.9, 0.5, 0.8, 0.4, 0.2])
                    for _ in 0..<30 { await Task.yield() }
                    XCTAssertTrue(media.collapsedMediaVisible)
                    XCTAssertTrue(meter.isAudioActive)
                }
                let calendar = CalendarActivityModel(service: MockCalendarService(),
                    coordinator: presentation.activityCoordinator, clock: clock)
                presentation.calendarRenderer = calendar
                let event = CalendarEventSummary(id: UUID(), title: "Quarterly Engineering Planning and Architecture Meeting",
                    startDate: base.addingTimeInterval(1800), endDate: base.addingTimeInterval(3600),
                    meetingURL: meeting ? URL(string: "https://meet.google.com/abc-defg-hij") : nil)
                await calendar.reminders.update(events: [event])
                for _ in 0..<30 { await Task.yield() }
                XCTAssertTrue(presentation.showsCalendarReminder)
                XCTAssertEqual(presentation.showsCollapsedMedia, music)

                let name = "\(music ? "music" : "idle")-\(meeting ? "join" : "no-link")"
                let view = NotchiumShellView(model: presentation, layout: layout)
                    .frame(width: layout.panelFrame.width, height: layout.panelFrame.height)
                let host = NSHostingView(rootView: view.transaction { $0.disablesAnimations = true })
                host.frame = CGRect(origin: .zero, size: layout.panelFrame.size)
                host.layoutSubtreeIfNeeded()
                for _ in 0..<10 { await Task.yield() }
                let bitmap = try render(view, name: name)
                let bottom = Int(layout.collapsedVisibleFrame.height + presentation.calendarReminderHeight)
                XCTAssertEqual(presentation.calendarReminderHeight, meeting ? 96 : 60)
                XCTAssertEqual(inkBands(bitmap, x: (left + 36)..<(left + 258), y: 52..<84, scale: 1).count, 2)

                // The outer edges are identical above, across, and below the old seam.
                for y in [1, 30, 37, 38, 39, bottom - 10] {
                    for x in [left + 1, right - 2] {
                        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        XCTAssertGreaterThan(color.alphaComponent, 0.99, name)
                        XCTAssertLessThan(color.redComponent + color.greenComponent + color.blueComponent, 0.01, name)
                    }
                    assertBackground(bitmap, x: left - 1, y: y)
                    assertBackground(bitmap, x: right + 1, y: y)
                }
                assertBackground(bitmap, x: left + 20, y: bottom + 1)
                let dot = try XCTUnwrap(bitmap.colorAt(x: left + 23, y: 60)?.usingColorSpace(.sRGB))
                XCTAssertGreaterThan(dot.blueComponent, 0.7, "Reminder content must remain visible: \(name)")
                // A bright capsule has long solid white runs; text alone does not.
                XCTAssertEqual(longestWhiteRun(bitmap, rows: 40..<bottom) > 40, meeting, name)
                let hitFrame = NotchReminderGeometry.contentFrame(for: layout, height: presentation.calendarReminderHeight)
                XCTAssertEqual(hitFrame.width, shellWidth)
                XCTAssertEqual(hitFrame.maxY, layout.collapsedVisibleFrame.minY)
                calendar.reminders.stop()
                media.stop()
            }
        }
    }

    func testTitleWrappingAtStandardAndRetinaScale() async throws {
        let titles = ["Dentist", "Weekly Engineering Team Meeting",
                      "Quarterly Engineering Planning and Architecture Meeting",
                      "Quarterly Engineering Planning and Architecture Meeting with all regional teams and project leads"]
        for scale: CGFloat in [1, 2] {
            for meeting in [false, true] {
                var heights: [Int] = []
                for (index, title) in titles.enumerated() {
                    let clock = TestAppClock(now: base, automaticallyAdvances: false)
                    let calendar = CalendarActivityModel(service: MockCalendarService(),
                        coordinator: ActivityCoordinator(clock: clock), clock: clock)
                    let event = CalendarEventSummary(id: UUID(), title: title,
                        startDate: base.addingTimeInterval(1800), endDate: base.addingTimeInterval(3600),
                        meetingURL: meeting ? URL(string: "https://meet.google.com/abc-defg-hij") : nil)
                    await calendar.reminders.update(events: [event])
                    let bitmap = try render(CalendarReminderView(model: calendar)
                        .frame(width: 356).foregroundStyle(.white).background(.black),
                        name: "title-\(index)-\(meeting ? "join" : "no-link")-\(Int(scale))x", scale: scale)
                    heights.append(Int(CGFloat(bitmap.pixelsHigh) / scale))
                    if meeting { assertCenteredJoin(bitmap, scale: Int(scale)) }
                    // Title ink occupies one or two distinct bands, at the same font size.
                    let titleRows = index < 2 ? 14..<32 : 14..<46
                    let bands = inkBands(bitmap, x: 36..<258, y: titleRows, scale: Int(scale))
                    XCTAssertEqual(bands.count, index < 2 ? 1 : 2, title)
                    XCTAssertGreaterThanOrEqual(bands.first?.count ?? 0, 9 * Int(scale), title)
                    // The countdown stays on the first row, with a clear gutter.
                    XCTAssertEqual(inkBands(bitmap, x: 268..<310, y: 14..<32, scale: Int(scale)).count, 1)
                    calendar.reminders.stop()
                }
                XCTAssertEqual(heights[0], heights[1])
                XCTAssertGreaterThan(heights[2], heights[0])
                XCTAssertLessThanOrEqual(heights[2] - heights[0], 18)
                XCTAssertEqual(heights[3], heights[2], "Extra-long titles truncate after two lines")
            }
        }
    }

    func testCenteredJoinWithLocationAndJoinNow() async throws {
        for scale: CGFloat in [1, 2] {
            for (name, meeting, minutes) in [("location-only", false, 30),
                                             ("join-location", true, 30),
                                             ("join-now", true, 0)] {
                let clock = TestAppClock(now: base, automaticallyAdvances: false)
                let calendar = CalendarActivityModel(service: MockCalendarService(),
                    coordinator: ActivityCoordinator(clock: clock), clock: clock)
                let event = CalendarEventSummary(id: UUID(),
                    title: "Quarterly Engineering Planning and Architecture Meeting",
                    startDate: base.addingTimeInterval(Double(minutes * 60)),
                    endDate: base.addingTimeInterval(3600),
                    meetingURL: meeting ? URL(string: "https://meet.google.com/abc-defg-hij") : nil,
                    location: "Engineering conference room, North campus")
                await calendar.reminders.update(events: [event])
                XCTAssertNotNil(calendar.reminders.current)
                let bitmap = try render(CalendarReminderView(model: calendar)
                    .frame(width: 356).foregroundStyle(.white).background(.black),
                    name: "centered-\(name)-\(Int(scale))x", scale: scale)
                if meeting {
                    assertCenteredJoin(bitmap, scale: Int(scale))
                } else {
                    XCTAssertLessThan(longestWhiteRun(bitmap, rows: 0..<bitmap.pixelsHigh), 40 * Int(scale))
                }
                let expectedHeight = minutes == 0 ? 96 : (meeting ? 119 : 83)
                XCTAssertEqual(bitmap.pixelsHigh, expectedHeight * Int(scale))
                calendar.reminders.stop()
            }
        }
    }

    private func assertCenteredJoin(_ bitmap: NSBitmapImageRep, scale: Int) {
        let span = longestWhiteSpan(bitmap, rows: (40 * scale)..<bitmap.pixelsHigh)
        XCTAssertGreaterThan(span.count, 40 * scale, "Join remains bright at rest")
        XCTAssertLessThan(span.count, 100 * scale, "The action remains compact")
        let center = CGFloat(span.lowerBound + span.upperBound) / 2
        XCTAssertEqual(center, CGFloat(bitmap.pixelsWide) / 2, accuracy: CGFloat(scale),
                       "Join centers on the reminder, independent of title and secondary text")
    }

    private func inkBands(_ bitmap: NSBitmapImageRep, x: Range<Int>, y: Range<Int>, scale: Int) -> [Range<Int>] {
        var bands: [Range<Int>] = []
        var start: Int?
        for row in (y.lowerBound * scale)..<(y.upperBound * scale) {
            let hasInk = ((x.lowerBound * scale)..<(x.upperBound * scale)).contains { column in
                guard row < bitmap.pixelsHigh,
                      let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { return false }
                return color.redComponent > 0.5 && color.greenComponent > 0.5 && color.blueComponent > 0.5
            }
            if hasInk && start == nil { start = row }
            if !hasInk, let first = start { bands.append(first..<row); start = nil }
        }
        if let first = start { bands.append(first..<(y.upperBound * scale)) }
        return bands
    }

    func testJoinIsOpaqueWhiteWithBlackContentAtRest() throws {
        for scheme in [ColorScheme.dark, .light] {
            let bitmap = try render(Button {} label: {
                Label("Join", systemImage: "video.fill")
            }
            .buttonStyle(CalendarJoinButtonStyle())
            .foregroundStyle(.white)
            .padding(10)
            .background(.black)
            .environment(\.colorScheme, scheme), name: "join-\(scheme)")
            XCTAssertGreaterThan(longestWhiteRun(bitmap, rows: 10..<38), 40)
            var white = 0
            var black = 0
            for y in 17..<31 {
                for x in 24..<(bitmap.pixelsWide - 24) {
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    XCTAssertGreaterThan(color.alphaComponent, 0.99)
                    if color.redComponent > 0.98 && color.greenComponent > 0.98 && color.blueComponent > 0.98 { white += 1 }
                    if color.redComponent < 0.02 && color.greenComponent < 0.02 && color.blueComponent < 0.02 { black += 1 }
                }
            }
            XCTAssertGreaterThan(white, 100)
            XCTAssertGreaterThan(black, 20)
        }
    }

    func testCalendarPageJoinUsesBrightStyleOnlyWithMeetingURL() async throws {
        for meeting in [true, false] {
            let clock = TestAppClock(now: base, automaticallyAdvances: false)
            let event = CalendarEventSummary(id: UUID(), title: "New Event",
                startDate: base.addingTimeInterval(1800), endDate: base.addingTimeInterval(3600),
                meetingURL: meeting ? URL(string: "https://meet.google.com/abc-defg-hij") : nil)
            let calendar = CalendarActivityModel(service: MockCalendarService(snapshot:
                .init(availability: .available, upcomingEvents: [event])),
                coordinator: ActivityCoordinator(clock: clock), clock: clock)
            calendar.start()
            for _ in 0..<30 { await Task.yield() }
            let bitmap = try render(CalendarActivityView(model: calendar)
                .frame(width: 560, height: 264).background(.black)
                .environment(\.notchCalendarPageVisible, false)
                .environment(\.colorScheme, .dark), name: "page-\(meeting ? "join" : "no-link")")
            XCTAssertEqual(longestWhiteRun(bitmap, rows: 35..<85) > 40, meeting)
            calendar.stop()
        }
    }

    private func render<V: View>(_ view: V, name: String, scale: CGFloat = 1) throws -> NSBitmapImageRep {
        let settled = view.transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        }
        let renderer = ImageRenderer(content: settled.background(Color(white: 0.3)))
        renderer.scale = scale
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/notchium-ui-\(name).png"))
        return bitmap
    }

    private func assertBackground(_ bitmap: NSBitmapImageRep, x: Int, y: Int) {
        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        // Compare in the renderer's output profile rather than assuming the
        // grayscale input has identical component values after color conversion.
        let background = bitmap.colorAt(x: 0, y: 0)!.usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(background.redComponent, 0.2)
        XCTAssertEqual(color.redComponent, background.redComponent, accuracy: 0.01)
        XCTAssertEqual(color.greenComponent, background.greenComponent, accuracy: 0.01)
        XCTAssertEqual(color.blueComponent, background.blueComponent, accuracy: 0.01)
    }

    private func longestWhiteRun(_ bitmap: NSBitmapImageRep, rows: Range<Int>) -> Int {
        longestWhiteSpan(bitmap, rows: rows).count
    }

    private func longestWhiteSpan(_ bitmap: NSBitmapImageRep, rows: Range<Int>) -> Range<Int> {
        var longest = 0..<0
        for y in rows {
            var run = 0
            for x in 0..<bitmap.pixelsWide {
                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                if color.alphaComponent > 0.99 && color.redComponent > 0.98
                    && color.greenComponent > 0.98 && color.blueComponent > 0.98 {
                    run += 1
                    if run > longest.count { longest = (x - run + 1)..<(x + 1) }
                } else { run = 0 }
            }
        }
        return longest
    }
}
