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
                    startDate: base.addingTimeInterval(300), endDate: base.addingTimeInterval(3600),
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
                XCTAssertEqual(presentation.calendarReminderHeight, 88)
                XCTAssertEqual(inkBands(bitmap, x: (left + 24)..<(left + 165), y: 44..<115, scale: 1).count, 3)

                // The outer edges are identical above, across, and below the old seam.
                for y in [14, 30, 37, 38, 39] {
                    for x in [left + 13, right - 14] {
                        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        XCTAssertGreaterThan(color.alphaComponent, 0.99, name)
                        XCTAssertLessThan(color.redComponent + color.greenComponent + color.blueComponent, 0.01, name)
                    }
                    assertBackground(bitmap, x: left - 1, y: y)
                    assertBackground(bitmap, x: right + 1, y: y)
                }
                assertBackground(bitmap, x: left + 20, y: bottom + 1)
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
                        startDate: base.addingTimeInterval(300), endDate: base.addingTimeInterval(3600),
                        meetingURL: meeting ? URL(string: "https://meet.google.com/abc-defg-hij") : nil)
                    await calendar.reminders.update(events: [event])
                    let bitmap = try render(CalendarReminderView(model: calendar, openActivity: {})
                        .frame(width: 356).foregroundStyle(.white).background(.black),
                        name: "title-\(index)-\(meeting ? "join" : "no-link")-\(Int(scale))x", scale: scale)
                    heights.append(Int(CGFloat(bitmap.pixelsHigh) / scale))
                    if meeting { assertTrailingJoin(bitmap, scale: Int(scale)) }
                    // One/two title lines plus the separate countdown, with no font scaling.
                    let bands = inkBands(bitmap, x: 24..<170, y: 0..<88, scale: Int(scale))
                    XCTAssertEqual(bands.count, index == 0 || (index == 1 && !meeting) ? 2 : 3, title)
                    XCTAssertGreaterThanOrEqual(bands.first?.count ?? 0, 9 * Int(scale), title)
                    calendar.reminders.stop()
                }
                XCTAssertEqual(heights[0], heights[1])
                XCTAssertEqual(heights[2], heights[0], "Replacement keeps the shell stable")
                XCTAssertEqual(heights[3], heights[2], "Extra-long titles truncate after two lines")
            }
        }
    }

    func testLocationDoesNotChangeNotificationAndJoinNowStaysTrailing() async throws {
        for scale: CGFloat in [1, 2] {
            var images: [Data] = []
            for location in [String?.none, "Engineering conference room, North campus"] {
                let clock = TestAppClock(now: base, automaticallyAdvances: false)
                let calendar = CalendarActivityModel(service: MockCalendarService(),
                    coordinator: ActivityCoordinator(clock: clock), clock: clock)
                let event = CalendarEventSummary(id: UUID(), title: "Engineering planning",
                    startDate: base, endDate: base.addingTimeInterval(3600),
                    meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"), location: location)
                await calendar.reminders.update(events: [event])
                let bitmap = try render(CalendarReminderView(model: calendar, openActivity: {})
                    .frame(width: 356).background(.black), name: "stage9-join-now-\(Int(scale))x", scale: scale)
                assertTrailingJoin(bitmap, scale: Int(scale))
                XCTAssertEqual(bitmap.pixelsHigh, 88 * Int(scale))
                images.append(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])))
                calendar.reminders.stop()
            }
            XCTAssertEqual(images[0], images[1], "Location belongs on the Calendar page")
        }
    }

    func testQuietCalendarAndCompactAudioVisualReviewFixtures() async throws {
        let layout = NotchGeometryResolver.layout(
            for: .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
        let clock = TestAppClock(now: base, automaticallyAdvances: false)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let calendar = CalendarActivityModel(service: MockCalendarService(),
            coordinator: presentation.activityCoordinator, clock: clock)
        presentation.calendarRenderer = calendar
        await calendar.reminders.update(events: [.init(id: UUID(), title: "Product review",
            startDate: base.addingTimeInterval(1800), endDate: base.addingTimeInterval(3600),
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"))])
        for reduceMotion in [false, true] {
            presentation.setReduceMotion(reduceMotion)
            let view = NotchiumShellView(model: presentation, layout: layout,
                renderConfiguration: .init(reduceMotion: reduceMotion ? .on : .off))
                .frame(width: layout.panelFrame.width, height: layout.panelFrame.height)
            let bitmap = try render(view, name: "stage9-calendar-30-reduced-\(reduceMotion)")
            XCTAssertGreaterThan(inkBands(bitmap, x: 215..<350, y: 45..<110, scale: 1).count, 1)
            var darkGlyphPixels = 0
            for y in 73..<89 {
                for x in 430..<470 {
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    if color.redComponent < 0.1 && color.greenComponent < 0.1 && color.blueComponent < 0.1 {
                        darkGlyphPixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(darkGlyphPixels, 20, "Quiet Join must retain black content on its controlled light backing")
        }
        calendar.reminders.dismiss()
        for (name, hud) in [
            ("volume", NotchAudioHUD(kind: .volume, deviceName: "Speakers", volume: 0.62, isMuted: false)),
            ("mute", NotchAudioHUD(kind: .volume, deviceName: "Speakers", volume: 0.62, isMuted: true)),
            ("output", NotchAudioHUD(kind: .outputChanged, deviceName: "AirPods Pro", volume: 0.62, isMuted: false))
        ] {
            presentation.notificationCoordinator.dismiss()
            presentation.showAudioHUD(hud)
            let view = NotchiumShellView(model: presentation, layout: layout)
                .frame(width: layout.panelFrame.width, height: layout.panelFrame.height)
            let bitmap = try render(view, name: "stage9-audio-\(name)")
            let frame = NotchNotificationGeometry.frame(for: .audio, layout: layout)
            XCTAssertLessThan(frame.height, layout.collapsedVisibleFrame.height + 88)
            XCTAssertGreaterThan(inkBands(bitmap, x: 250..<475, y: 40..<86, scale: 1).count, 0)
        }
        calendar.reminders.stop()
        presentation.reset()
    }

    private func assertTrailingJoin(_ bitmap: NSBitmapImageRep, scale: Int) {
        let span = longestWhiteSpan(bitmap, rows: (25 * scale)..<(65 * scale))
        XCTAssertGreaterThan(span.count, 40 * scale, "Imminent Join remains bright at rest")
        XCTAssertLessThan(span.count, 110 * scale, "The action remains compact")
        XCTAssertGreaterThan(span.lowerBound, bitmap.pixelsWide / 2, "Action trails the event summary")
        XCTAssertLessThan(span.upperBound, bitmap.pixelsWide - 40 * scale, "Dismiss target has its own space")
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
            let content = CalendarActivityView(model: calendar)
                .frame(width: ExpandedNotchLayout.size.width,
                       height: ExpandedNotchLayout.size.height - 38 - ExpandedNotchLayout.navigationHeight).background(.black)
                .environment(\.notchCalendarPageVisible, false)
                .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 524, height: 196)
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 524, height: 196),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderBack(nil)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.needsDisplay = true
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = bitmap.pixelsHigh / 196
            XCTAssertEqual(longestWhiteRun(bitmap, rows: (140 * scale)..<(180 * scale)) > 40 * scale, meeting)
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
