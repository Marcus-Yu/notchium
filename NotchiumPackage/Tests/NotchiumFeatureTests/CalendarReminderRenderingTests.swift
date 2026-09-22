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
                let event = CalendarEventSummary(id: UUID(), title: "New Event",
                    startDate: base.addingTimeInterval(1800), endDate: base.addingTimeInterval(3600),
                    meetingURL: meeting ? URL(string: "https://meet.google.com/abc-defg-hij") : nil)
                await calendar.reminders.update(events: [event])
                for _ in 0..<30 { await Task.yield() }
                XCTAssertTrue(presentation.showsCalendarReminder)
                XCTAssertEqual(presentation.showsCollapsedMedia, music)

                let name = "\(music ? "music" : "idle")-\(meeting ? "join" : "no-link")"
                let bitmap = try render(NotchiumShellView(model: presentation, layout: layout)
                    .frame(width: layout.panelFrame.width, height: layout.panelFrame.height), name: name)

                // The outer edges are identical above, across, and below the old seam.
                for y in [1, 30, 37, 38, 39, 90, 98] {
                    for x in [left + 1, right - 2] {
                        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        XCTAssertGreaterThan(color.alphaComponent, 0.99, name)
                        XCTAssertLessThan(color.redComponent + color.greenComponent + color.blueComponent, 0.01, name)
                    }
                    assertBackground(bitmap, x: left - 1, y: y)
                    assertBackground(bitmap, x: right + 1, y: y)
                }
                assertBackground(bitmap, x: left + 20, y: 109)
                let dot = try XCTUnwrap(bitmap.colorAt(x: left + 21, y: 73)?.usingColorSpace(.sRGB))
                XCTAssertGreaterThan(dot.blueComponent, 0.7, "Reminder content must remain visible: \(name)")
                // A bright capsule has long solid white runs; text alone does not.
                XCTAssertEqual(longestWhiteRun(bitmap, rows: 40..<105) > 40, meeting, name)
                let hitFrame = NotchReminderGeometry.contentFrame(for: layout)
                XCTAssertEqual(hitFrame.width, shellWidth)
                XCTAssertEqual(hitFrame.maxY, layout.collapsedVisibleFrame.minY)
                calendar.reminders.stop()
                media.stop()
            }
        }
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

    private func render<V: View>(_ view: V, name: String) throws -> NSBitmapImageRep {
        let settled = view.transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        }
        let renderer = ImageRenderer(content: settled.background(Color(white: 0.3)))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/notchium-ui-\(name).png"))
        return bitmap
    }

    private func assertBackground(_ bitmap: NSBitmapImageRep, x: Int, y: Int) {
        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        XCTAssertEqual(color.redComponent, 0.3, accuracy: 0.01)
        XCTAssertEqual(color.greenComponent, 0.3, accuracy: 0.01)
        XCTAssertEqual(color.blueComponent, 0.3, accuracy: 0.01)
    }

    private func longestWhiteRun(_ bitmap: NSBitmapImageRep, rows: Range<Int>) -> Int {
        var longest = 0
        for y in rows {
            var run = 0
            for x in 0..<bitmap.pixelsWide {
                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                if color.alphaComponent > 0.99 && color.redComponent > 0.98
                    && color.greenComponent > 0.98 && color.blueComponent > 0.98 {
                    run += 1
                    longest = max(longest, run)
                } else { run = 0 }
            }
        }
        return longest
    }
}
