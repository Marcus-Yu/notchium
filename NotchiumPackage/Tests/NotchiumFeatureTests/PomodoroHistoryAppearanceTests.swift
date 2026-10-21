import AppKit
import NotchiumCore
import NotchiumDesignSystem
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumFocusFeature

@MainActor final class PomodoroHistoryAppearanceTests: XCTestCase {
    func testZeroDisplayedMinutesStayNeutralIncludingWhenHovered() throws {
        for focus in [0.0, 0.001, 15, 59.999, 60] {
            for appearance in [(hovered: false, contrast: false), (hovered: true, contrast: false),
                               (hovered: true, contrast: true)] {
                for isToday in [false, true] {
                    let image = try render(PomodoroHistoryBar(focus: focus, peak: 3600,
                        isToday: isToday, isHovered: appearance.hovered)
                        .environment(\.notchIncreaseContrastOverride, appearance.contrast)
                        .frame(width: 9, height: 92, alignment: .bottom).padding(8),
                        size: CGSize(width: 25, height: 108))
                    let tinted = tintedPixelCount(image)
                    if PomodoroStatistics.duration(focus) == "0m" {
                        XCTAssertEqual(tinted, 0, "0m bars and their hover glow must stay neutral: \(focus)s")
                    } else {
                        XCTAssertGreaterThan(tinted, 4, "A full minute must display the Focus accent")
                    }
                }
            }
        }
    }

    func testPausedFocusControlsStayCloseWithResumeCentered() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let suite = "Pomodoro.Appearance.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite); presentation.reset() }
        var state = PomodoroState()
        state.phaseDuration = 1800
        state.run = .paused(remaining: 1200)
        let model = PomodoroModel(store: InMemoryPomodoroStore(.init(state: state)),
            notifications: presentation.notificationCoordinator, clock: clock, preferences: preferences, now: { now })
        defer { model.stop() }
        for reduced in [false, true] {
            let image = try render(PomodoroControlsView(model: model, centersPrimary: true)
                .environment(\.notchReduceMotionOverride, reduced), size: CGSize(width: 290, height: 36))
            // Above the labels, each visible capsule is one continuous run of pixels.
            let runs = try filledRuns(image, y: 6)
            XCTAssertEqual(runs.count, 3)
            guard runs.count == 3 else { continue }
            XCTAssertEqual(Double(runs[1].lowerBound + runs[1].upperBound - 1) / 2, 144.5, accuracy: 1,
                           "Resume stays centered independently of secondary label widths")
            for index in 1...2 {
                let gap = runs[index].lowerBound - runs[index - 1].upperBound
                XCTAssertGreaterThanOrEqual(gap, 8)
                XCTAssertLessThanOrEqual(gap, 18, "Secondary controls must sit beside Resume, not at the column edges")
            }
        }
    }

    func testHistoryPeekRendersTheDateAboveTheFocusDuration() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12)))
        let stats = PomodoroStatistics(records: [], openSegments: [DateInterval(start: date, duration: 5040)],
                                       now: date, calendar: calendar, dayCount: 1)
        let day = try XCTUnwrap(stats.days.first)
        let image = try render(PomodoroHistoryPeek(day: day, calendar: calendar), size: CGSize(width: 128, height: 44))
        XCTAssertGreaterThan(whitePixelCount(image, rows: 6..<20), 20, "The date occupies its own line")
        XCTAssertGreaterThan(whitePixelCount(image, rows: 23..<38), 20, "The Focus duration occupies the second line")
        try save(image, name: "history-peek")
    }

    func testPaletteAndPhaseFixtures() throws {
        // Running countdowns render against wall time, including when their page is hidden.
        let now = Date()
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let suite = "Pomodoro.Palette.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite); presentation.reset() }
        for phase in [PomodoroPhase.focus, .shortBreak, .longBreak] {
            let color = try XCTUnwrap(NSColor(PomodoroStyle.accent(phase)).usingColorSpace(.sRGB))
            let luminance = [color.redComponent, color.greenComponent, color.blueComponent]
                .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            let contrastOnBlack = (0.2126 * luminance[0] + 0.7152 * luminance[1] + 0.0722 * luminance[2] + 0.05) / 0.05
            XCTAssertGreaterThan(contrastOnBlack, 7, "Accents remain legible against the black notch")
            var state = PomodoroState()
            state.phase = phase
            state.phaseDuration = 1800
            let runs: [(String, PomodoroState.Run)] = [
                ("ready", .ready), ("running", .running(endsAt: now.addingTimeInterval(1200))),
                ("paused", .paused(remaining: 1200))
            ]
            for (name, run) in runs {
                state.run = run
                let model = PomodoroModel(store: InMemoryPomodoroStore(.init(state: state)),
                    notifications: presentation.notificationCoordinator, clock: clock, preferences: preferences, now: { now })
                defer { model.stop() }
                let image = try render(PomodoroPageView(model: model)
                    .environment(\.notchReduceMotionOverride, true), size: CGSize(width: 524, height: 196))
                try save(image, name: "\(name)-\(phase.rawValue)")
            }
        }
    }

    private func render<V: View>(_ view: V, size: CGSize) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
            .foregroundStyle(.white).background(.black)
            .environment(\.colorScheme, .dark)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    private func tintedPixelCount(_ image: NSBitmapImageRep) -> Int {
        (0..<image.pixelsHigh).reduce(into: 0) { count, y in
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let components = [color.redComponent, color.greenComponent, color.blueComponent]
                if components.max()! - components.min()! > 0.025 { count += 1 }
            }
        }
    }

    private func filledRuns(_ image: NSBitmapImageRep, y: Int) throws -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for x in 0...image.pixelsWide {
            let filled = x < image.pixelsWide && (image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)?.blueComponent ?? 0) > 0.06
            if filled, start == nil { start = x }
            if !filled, let first = start { runs.append(first..<x); start = nil }
        }
        return runs
    }

    private func whitePixelCount(_ image: NSBitmapImageRep, rows: Range<Int>) -> Int {
        rows.reduce(into: 0) { count, y in
            for x in 0..<image.pixelsWide {
                if (image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)?.redComponent ?? 0) > 0.6 { count += 1 }
            }
        }
    }

    private func save(_ image: NSBitmapImageRep, name: String) throws {
        let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/private/tmp/notchium-pomodoro-\(name).png"))
    }
}
