import AppKit
import SwiftUI
import XCTest
import NotchiumCore
import NotchiumServices
import NotchiumPersistence
@testable import NotchiumClipboardFeature
@testable import NotchiumDynamicIsland
@testable import NotchiumFeature

/// Opt-in visual QA: renders the real shell with mock services and synthetic worst-case content.
/// Skipped unless `NOTCHIUM_VISUAL_CAPTURE_DIR` names an output folder; never reads personal data.
@MainActor final class Stage27A1VisualCaptureTests: XCTestCase {
    private var output: URL!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["NOTCHIUM_VISUAL_CAPTURE_DIR"] else {
            throw XCTSkip("Set NOTCHIUM_VISUAL_CAPTURE_DIR to capture shell renders")
        }
        output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    }

    func testCaptureExpandedPagesAndMotion() async throws {
        let reduceMotion = ProcessInfo.processInfo.environment["NOTCHIUM_VISUAL_REDUCE_MOTION"] == "1"
        let fixture = try VisualFixture()
        defer { fixture.stop() }
        let presentation = fixture.presentation
        let layout = NotchGeometryResolver.layout(for:
            .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
        let host = NSHostingView(rootView: NotchiumShellView(model: presentation, layout: layout,
            renderConfiguration: .init(appearance: .dark, reduceMotion: reduceMotion ? .on : .off))
            .frame(width: layout.panelFrame.width, height: layout.panelFrame.height))
        host.frame = CGRect(origin: .zero, size: layout.panelFrame.size)
        host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: layout.panelFrame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(white: 0.5, alpha: 1)
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        let prefix = reduceMotion ? "rm-" : ""

        try await Task.sleep(for: .milliseconds(600))
        try capture(host, "\(prefix)00-collapsed-media")

        presentation.present(.expanded)
        try await frames(host, "\(prefix)10-open", count: 14, interval: .milliseconds(35))
        try await Task.sleep(for: .milliseconds(300))
        for page in presentation.pageModel.enabledPages {
            presentation.pageModel.selectedPage = page
            try await Task.sleep(for: .milliseconds(250))
            try capture(host, "\(prefix)20-page-\(page.rawValue)")
        }
        presentation.pageModel.selectedPage = .shelf
        presentation.pageModel.shelfSection = .clipboard
        try await Task.sleep(for: .milliseconds(250))
        try capture(host, "\(prefix)20-page-clipboard")
        presentation.pageModel.shelfSection = .files
        presentation.pageModel.selectedPage = .home

        // Close, then reverse half-way: the shell must retarget from its live geometry.
        presentation.present(.collapsed)
        try await frames(host, "\(prefix)30-close", count: 14, interval: .milliseconds(35))
        try await Task.sleep(for: .milliseconds(400))
        presentation.present(.expanded)
        try await Task.sleep(for: .milliseconds(140))
        presentation.present(.collapsed)
        try await frames(host, "\(prefix)40-reverse-close", count: 4, interval: .milliseconds(35))
        presentation.present(.expanded)
        try await frames(host, "\(prefix)41-reverse-open", count: 14, interval: .milliseconds(35))
        presentation.present(.collapsed)
        try await Task.sleep(for: .milliseconds(700))

        // Transient activities on the collapsed notch.
        _ = presentation.notificationCoordinator.present(.audio(.init(kind: .volume,
            deviceName: "External headphones — long output name", volume: 0.42, isMuted: false, deviceStyle: .headphones)))
        try await frames(host, "\(prefix)50-volume-hud", count: 10, interval: .milliseconds(35))
        try await Task.sleep(for: .milliseconds(400))
        try capture(host, "\(prefix)51-volume-hud-settled")
        _ = presentation.notificationCoordinator.present(.audio(.init(kind: .outputChanged,
            deviceName: "AirPods Pro — 李雷的耳机", volume: 0.5, isMuted: false, deviceStyle: .airPodsPro,
            deviceID: "pods", battery: .init(level: 0.82, isCharging: false))))
        try await Task.sleep(for: .milliseconds(700))
        try capture(host, "\(prefix)52-airpods-connected")
        try await Task.sleep(for: .milliseconds(600))
        try capture(host, "\(prefix)52b-airpods-settled")
        _ = presentation.notificationCoordinator.present(.charging(level: 0.67))
        try await Task.sleep(for: .milliseconds(700))
        try capture(host, "\(prefix)53-charging")
        _ = presentation.notificationCoordinator.present(.feedback(
            "Reminder Added — a very long reminder title that must truncate cleanly", kind: .reminderAdded, key: "qa"))
        try await Task.sleep(for: .milliseconds(700))
        try capture(host, "\(prefix)54-feedback")
        presentation.notificationCoordinator.dismissByUser()
        try await frames(host, "\(prefix)55-dismiss", count: 8, interval: .milliseconds(35))
        try await Task.sleep(for: .milliseconds(900))
        try capture(host, "\(prefix)56-restored-settled")

        // A battery activity over a settled connection: the restored entry must not turn again.
        _ = presentation.notificationCoordinator.present(.audio(.init(kind: .outputChanged,
            deviceName: "AirPods Max", volume: 0.5, isMuted: false, deviceStyle: .airPodsMax,
            deviceID: "max", battery: .init(level: 0.4, isCharging: false))))
        try await Task.sleep(for: .milliseconds(1_200))
        try capture(host, "\(prefix)57-connected-settled")
        _ = presentation.notificationCoordinator.present(.powerDisconnected(level: 0.55))
        try await Task.sleep(for: .milliseconds(500))
        try capture(host, "\(prefix)57b-preempted")
        presentation.notificationCoordinator.dismissByUser()
        try await frames(host, "\(prefix)58-restore", count: 8, interval: .milliseconds(35))

        // Compact → compact swap inside the shell: rows of different widths share one slot.
        try await Task.sleep(for: .milliseconds(3_000))
        _ = presentation.notificationCoordinator.present(.audio(.init(kind: .outputChanged,
            deviceName: "AirPods Pro", volume: 0.5, isMuted: false, deviceStyle: .airPodsPro,
            deviceID: "swap", battery: .init(level: 0.82, isCharging: false))))
        try await Task.sleep(for: .milliseconds(400))
        _ = presentation.notificationCoordinator.present(.charging(level: 0.67))
        try await Task.sleep(for: .milliseconds(500))
        try capture(host, "\(prefix)59-swap-start")
        presentation.notificationCoordinator.dismissByUser()
        try await frames(host, "\(prefix)59-swap", count: 9, interval: .milliseconds(25))
    }

    func testCaptureMirrorAndSettings() async throws {
        let fixture = try VisualFixture()
        defer { fixture.stop() }
        let presentation = fixture.presentation
        let layout = NotchGeometryResolver.layout(for:
            .init(display: NotchShellDebugModel.builtInFixture, mode: .physicalNotch), state: .collapsed)
        let shell = try host(NotchiumShellView(model: presentation, layout: layout,
            renderConfiguration: .init(appearance: .dark, reduceMotion: .off))
            .frame(width: layout.panelFrame.width, height: layout.panelFrame.height), size: layout.panelFrame.size)
        defer { shell.window?.close() }
        try await Task.sleep(for: .milliseconds(600))
        presentation.present(.expanded)
        try await Task.sleep(for: .milliseconds(700))
        try capture(shell, "59-mirror-before")
        XCTAssertNotNil(presentation.cameraController, "The fixture enables the Mirror utility")
        presentation.cameraController?.togglePreview()
        try await frames(shell, "60-mirror-open", count: 10, interval: .milliseconds(35))
        try await Task.sleep(for: .milliseconds(400))
        try capture(shell, "61-mirror-open-settled")
        presentation.cameraController?.togglePreview()
        try await frames(shell, "62-mirror-close", count: 8, interval: .milliseconds(35))

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let settings = try host(NotchiumSettingsView(environment: fixture.controller.environment,
                calendarModel: fixture.controller.calendarModel, caffeineModel: fixture.controller.caffeineModel,
                quickActions: fixture.controller.quickActions, clipboardModel: fixture.controller.clipboardModel,
                pomodoroModel: fixture.controller.pomodoroModel)
                .frame(width: 720, height: 520), size: CGSize(width: 720, height: 520), appearance: appearance)
            try await Task.sleep(for: .milliseconds(500))
            try capture(settings, "70-settings-general-\(name)")
            settings.window?.close()
        }
    }

    private func host(_ view: some View, size: CGSize,
                      appearance: NSAppearance.Name = .darkAqua) throws -> NSView {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(white: 0.5, alpha: 1)
        window.appearance = host.appearance
        window.contentView = host
        window.orderBack(nil)
        return host
    }

    private func frames(_ host: NSView, _ name: String, count: Int, interval: Duration) async throws {
        let start = ContinuousClock.now
        for index in 0..<count {
            try capture(host, String(format: "%@-%02d", name, index))
            try await Task.sleep(until: start + interval * (index + 1), clock: .continuous)
        }
    }

    private func capture(_ host: NSView, _ name: String) throws {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }
}

/// Composition-root models over mock services, started without placing any panel on screen.
@MainActor private final class VisualFixture {
    let controller: NotchiumApplicationController
    let suite = "Stage27A1VisualCapture.\(UUID())"
    var presentation: DynamicIslandPresentationModel { controller.displayCoordinator.presentationModel }

    init() throws {
        let now = Date()
        let media = MockMediaProvider(snapshot: .init(playbackState: .playing,
            title: "夜に駆ける (Racing into the Night) — Extended Live Version 🎧 with a long subtitle",
            artist: "YOASOBI, The Philharmonic Orchestra of Somewhere Very Far Away",
            elapsed: 92, duration: 7_265, trackID: "qa-long", volumePercent: 100, source: .spotify,
            capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true,
                canSeek: true, canShuffle: true, canRepeat: true, canSetVolume: true)))
        let calendar = MockCalendarService(snapshot: .init(availability: .available, upcomingEvents: [
            .init(id: UUID(), title: "季度产品设计评审 — Quarterly product design review with the extended platform team",
                  startDate: now.addingTimeInterval(1_500), endDate: now.addingTimeInterval(5_100),
                  meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"),
                  location: "Building 4, Floor 12, Conference Room “Aurora Borealis”", calendarName: "Work"),
            .init(id: UUID(), title: "1:1", startDate: now.addingTimeInterval(7_200), endDate: now.addingTimeInterval(9_000)),
            .init(id: UUID(), title: "🎉 Launch party — 庆祝发布 🚀🚀🚀 everyone welcome, bring snacks",
                  startDate: now.addingTimeInterval(86_400), endDate: now.addingTimeInterval(90_000))
        ], permission: .granted))
        let audio = MockAudioDevicesService(snapshot: .init(availability: .available, outputs: [
            .init(id: "qa-1", name: "李雷的 AirPods Pro — Noise Cancellation Enabled", isDefaultOutput: true,
                  volume: 1, isMuted: false, canSetVolume: true, canSetMute: true, transport: .bluetooth,
                  battery: .available(.init(left: 1, right: 0.05, caseLevel: 0, isCharging: false, measuredAt: now))),
            .init(id: "qa-2", name: "MacBook Pro Speakers", isDefaultOutput: false, volume: 0),
            .init(id: "qa-3", name: "LG UltraFine 5K Display Audio (Thunderbolt 3, Port 2)", isDefaultOutput: false)
        ]))
        let services = ServiceRegistry.mock(media: media, audioDevices: audio, calendar: calendar)
        let shelfPaths = [
            "/private/tmp/notchium-qa/Quarterly Business Review — Final Draft (v27, approved by legal) copy 2.pdf",
            "/private/tmp/notchium-qa/截图 2026-10-16 下午11.42.13.png",
            "/private/tmp/notchium-qa/a.txt",
            "/private/tmp/notchium-qa/🎨 Moodboard.key"
        ]
        (services.shelf as? MockShelfService)?.existingPaths.formUnion(shelfPaths)
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = QuickActionStore(preferences: preferences)
        controller = NotchiumApplicationController(environment: .mock(clock: ContinuousAppClock(), services: services,
            featureFlags: .stageNineteenUtilities), actionStore: store)
        controller.calendarModel.start()
        controller.audioModel.start()
        controller.filesModel.start()
        controller.clipboardModel.start()
        controller.pomodoroModel.start()
        controller.mediaModel.start()
        _ = controller.filesModel.shelf.add(shelfPaths.map { URL(fileURLWithPath: $0) })
        for text in ["https://example.com/a/very/long/path/that/keeps/going?query=string&with=parameters#and-a-fragment",
                     "你好，世界！这是一段很长的中文剪贴板内容，用于测试换行与截断是否正确。",
                     "🙂", String(repeating: "W", count: 400)] {
            controller.clipboardModel.receive(ClipboardCapture(content: .text(text), capturedAt: now))
        }
    }

    func stop() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}
