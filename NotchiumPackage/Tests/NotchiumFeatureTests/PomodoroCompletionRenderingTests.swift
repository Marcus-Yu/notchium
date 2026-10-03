import AppKit
import NotchiumCore
import SwiftUI
import XCTest
@testable import NotchiumDynamicIsland
@testable import NotchiumFocusFeature

@MainActor
final class PomodoroCompletionRenderingTests: XCTestCase {
    func testCompletionBannerRendersInsideCalendarWidthAtStandardAndRetinaScale() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let placement = NotchShellPlacement(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch)
        let layout = NotchGeometryResolver.layout(for: placement, state: .collapsed)
        let scenarios: [(completed: PomodoroPhase, cadence: Int, name: String)] = [
            (.focus, 4, "break"), (.focus, 1, "long-break"), (.shortBreak, 4, "focus")
        ]
        for scenario in scenarios {
            let configuration = PomodoroConfiguration(sessionsPerCycle: scenario.cadence)
            var state = PomodoroState()
            state.phase = scenario.completed
            PomodoroEngine.start(&state, configuration: configuration, at: base)
            let date = base.addingTimeInterval(configuration.duration(of: scenario.completed))
            let clock = TestAppClock(now: date, automaticallyAdvances: false)
            let presentation = DynamicIslandPresentationModel(clock: clock)
            let suite = "notchium.tests.pomodoro.render.\(UUID().uuidString)"
            let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
            let timer = PomodoroModel(store: InMemoryPomodoroStore(PomodoroArchive(state: state)),
                notifications: presentation.notificationCoordinator, clock: clock, preferences: preferences, now: { date })
            defer { timer.stop(); presentation.reset(); preferences.removePersistentDomain(forName: suite) }
            timer.configuration = configuration
            presentation.pomodoroRenderer = timer
            timer.refresh()

            for scale: CGFloat in [1, 2] {
                let content = PomodoroCompletionView(model: timer,
                    title: scenario.completed == .focus ? "Focus Complete" : "Break Over", openTimer: {})
                    .frame(width: NotchReminderGeometry.width(for: layout)).background(.black)
                let banner = try render(content, scale: scale, name: "\(scenario.name)-\(Int(scale))x")
                XCTAssertEqual(banner.pixelsWide, Int(NotchReminderGeometry.width(for: layout) * scale))
                XCTAssertEqual(banner.pixelsHigh, Int(NotchNotificationGeometry.pomodoroCompletionHeight * scale))
                // The colored primary capsule centers independently of unequal secondary buttons.
                let coloredColumns = (0..<banner.pixelsWide).filter { x in
                    guard let color = banner.colorAt(x: x, y: Int(74 * scale))?.usingColorSpace(.sRGB) else { return false }
                    let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                    return (channels.max()! - channels.min()!) > 0.2 && color.greenComponent > 0.25
                }
                let first = try XCTUnwrap(coloredColumns.first)
                let last = try XCTUnwrap(coloredColumns.last)
                XCTAssertEqual(Double(first + last) / 2, Double(banner.pixelsWide - 1) / 2, accuracy: 1,
                               "The Start button is centered for both two- and three-button banners")
            }
            for reduceMotion in [false, true] {
                presentation.setReduceMotion(reduceMotion)
                let shell = NotchiumShellView(model: presentation, layout: layout,
                    renderConfiguration: .init(reduceMotion: reduceMotion ? .on : .off))
                    .frame(width: layout.panelFrame.width, height: layout.panelFrame.height)
                let bitmap = try render(shell, scale: 1, name: "shell-\(scenario.name)-\(reduceMotion ? "reduced" : "animated")")
                let bottom = Int(layout.collapsedVisibleFrame.height + NotchNotificationGeometry.pomodoroCompletionHeight)
                let center = bitmap.pixelsWide / 2
                let bodyColor = try XCTUnwrap(bitmap.colorAt(x: center, y: bottom - 2)?.usingColorSpace(.sRGB))
                let belowColor = try XCTUnwrap(bitmap.colorAt(x: center, y: bottom + 2)?.usingColorSpace(.sRGB))
                XCTAssertLessThan(bodyColor.redComponent, 0.05)
                XCTAssertGreaterThan(belowColor.redComponent, 0.2, "The banner stops well above the full expanded height")
            }
        }
    }

    private func render<V: View>(_ view: V, scale: CGFloat, name: String) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        }.background(Color(white: 0.3)))
        renderer.scale = scale
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/notchium-pomodoro-\(name).png"))
        return bitmap
    }
}
