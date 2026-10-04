import AppKit
import SwiftUI
import XCTest
import NotchiumCore
import NotchiumFocusFeature
import Observation
@testable import NotchiumDynamicIsland

@MainActor
final class NotchLaunchRenderingTests: XCTestCase {
    func testShellInvalidationReadsTheResolvedPresentationMode() {
        let model = DynamicIslandPresentationModel(clock: TestAppClock(now: Date(), automaticallyAdvances: false))
        model.mediaRenderer = LaunchMediaRenderer()
        defer { model.reset() }
        let observation = LaunchObservation()
        withObservationTracking {
            _ = model.showsCollapsedMedia
        } onChange: {
            MainActor.assumeIsolated {
                observation.mediaVisible = model.showsCollapsedMedia
                observation.mode = model.activityCoordinator.presentationMode
            }
        }
        model.activityCoordinator.present(.init(id: UUID(), key: .media, kind: .media, title: "Music",
            subtitle: nil, priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
            isDismissible: false, destination: .music, duration: nil,
            payload: .mediaPlayback(isPlaying: true, isLocal: true), minimal: .artwork))
        XCTAssertEqual(observation.mode, .mediaSides, "Shell invalidation follows the complete activity resolution")
        XCTAssertEqual(observation.mediaVisible, true, "The first invalidation must already see running media")
    }

    func testRestoredTimerInvalidatesShellAfterCompactModeIsResolved() throws {
        let now = Date()
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let model = DynamicIslandPresentationModel(clock: clock)
        let observation = LaunchObservation()
        withObservationTracking {
            _ = model.presentationState
        } onChange: {
            MainActor.assumeIsolated { observation.presentation = model.presentationState }
        }
        var state = PomodoroState()
        PomodoroEngine.start(&state, configuration: .standard, at: now)
        let suite = "notchium.launch.timer.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let timer = PomodoroModel(store: InMemoryPomodoroStore(.init(state: state)),
            notifications: model.notificationCoordinator, clock: clock, preferences: preferences, now: { now })
        defer { timer.stop(); model.reset() }
        timer.start()
        XCTAssertEqual(observation.presentation, .activity, "The restored timer's first invalidation must show activity")
    }

    func testRunningTimerAndMusicAppearWhenRestoredBeforeWindowIsShown() async throws {
        for prepareBeforeRestoration in [false, true] {
            let now = Date()
            let clock = TestAppClock(now: now, automaticallyAdvances: false)
            let model = DynamicIslandPresentationModel(clock: clock)
            model.mediaRenderer = LaunchMediaRenderer()
            let layout = NotchGeometryResolver.layout(for:
                .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
            let host = NSHostingView(rootView: NotchiumShellView(model: model, layout: layout,
                renderConfiguration: .init(reduceMotion: .on))
                .frame(width: layout.panelFrame.width, height: layout.panelFrame.height))
            host.frame = CGRect(origin: .zero, size: layout.panelFrame.size)
            if prepareBeforeRestoration { host.layoutSubtreeIfNeeded(); _ = host.fittingSize }

            var state = PomodoroState()
            PomodoroEngine.start(&state, configuration: .standard, at: now)
            let suite = "notchium.launch.\(UUID())"
            let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { preferences.removePersistentDomain(forName: suite) }
            preferences.set("timer", forKey: "notchium.pomodoro.collapsed.v1")
            let timer = PomodoroModel(store: InMemoryPomodoroStore(.init(state: state)),
                notifications: model.notificationCoordinator, clock: clock, preferences: preferences, now: { now })
            model.pomodoroRenderer = timer
            defer { timer.stop(); model.reset() }
            timer.start()
            model.activityCoordinator.present(.init(id: UUID(), key: .media, kind: .media, title: "Music",
                subtitle: nil, priority: .low, presentationStyle: .mediaSides, lifetime: .persistent,
                isDismissible: false, destination: .music, duration: nil,
                payload: .mediaPlayback(isPlaying: true, isLocal: true), minimal: .artwork))
            XCTAssertTrue(model.showsCollapsedMedia)
            XCTAssertEqual(model.presentedNotification?.kind, .focusTimer)

            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: layout.panelFrame.size),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderBack(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(400))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            var red = 0, blue = 0, white = 0
            let scale = CGFloat(bitmap.pixelsWide) / layout.panelFrame.width
            for y in 0..<Int(layout.collapsedVisibleFrame.height * scale) {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if color.redComponent > color.blueComponent + 0.4 { red += 1 }
                    if color.blueComponent > color.redComponent + 0.4 { blue += 1 }
                    if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.7 { white += 1 }
                }
            }
            XCTAssertGreaterThan(red, 30, "Restored artwork must appear without opening the notch")
            XCTAssertGreaterThan(blue, 30, "The waveform must appear without opening the notch")
            XCTAssertGreaterThan(white, 30, "The running timer must appear without opening the notch")
        }
    }
}

@MainActor
private final class LaunchObservation {
    var mediaVisible: Bool?
    var mode: NotchPresentationMode?
    var presentation: NotchPresentationState?
}

@MainActor
private final class LaunchMediaRenderer: NotchMediaRendering {
    var collapsedMediaVisible: Bool { true }
    func collapsedMedia(hardwareWidth: CGFloat, hardwareHeight: CGFloat) -> AnyView {
        AnyView(HStack(spacing: 0) {
            Color.red.frame(width: 40)
            Color.clear.frame(width: hardwareWidth)
            Color.blue.frame(width: 40)
        }.frame(height: hardwareHeight))
    }
    func expandedMedia() -> AnyView { AnyView(EmptyView()) }
    func mediaArtwork(size: CGFloat) -> AnyView { AnyView(Color.red.frame(width: size, height: size)) }
    func mediaWaveform() -> AnyView { AnyView(Color.blue.frame(width: 22, height: 16)) }
}
