import AppKit
import SwiftUI
import XCTest
import NotchiumCore
import NotchiumServices
@testable import NotchiumDynamicIsland
@testable import NotchiumMediaFeature
@testable import NotchiumCalendarFeature
@testable import NotchiumAudioFeature

/// Native-hosted visual fixtures, including native segmented controls and focusable sliders.
@MainActor final class ExpandedPageCompositionTests: XCTestCase {
    func testExpandedPageCompositions() async throws {
        let presentation = DynamicIslandPresentationModel(clock: TestAppClock(now: Date(), automaticallyAdvances: false))
        let media = MediaFeatureModel(provider: MockMediaProvider(), coordinator: presentation.activityCoordinator)
        media.receive(.init(connectionState: .authenticated, playbackState: .paused,
            title: "Midnight City", artist: "M83", elapsed: 81, duration: 244,
            trackID: "midnight", activeDeviceID: "mac", activeDeviceName: "MacBook Pro", volumePercent: 60, artwork: URL(string: "notchium-fixture://artwork/midnight"), source: .spotify,
            capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true, canSeek: true,
                                canShuffle: true, canRepeat: true, canSetVolume: true)))
        let calendar = CalendarActivityModel(service: MockCalendarService(), coordinator: presentation.activityCoordinator)
        let now = Date()
        let events = ["Design review", "Software Engineering Interview", "Weekly Product Development Meeting"].enumerated().map { index, title in
            CalendarEventSummary(id: UUID(), title: title, startDate: now.addingTimeInterval(Double(index + 1) * 1800),
                endDate: now.addingTimeInterval(Double(index + 2) * 1800),
                meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"))
        }
        calendar.receive(.init(availability: .available, upcomingEvents: events, permission: .granted))
        let suite = "ExpandedPageCompositionTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let audio = AudioFeatureModel(devices: MockAudioDevicesService(), processes: MockAudioProcessesService(),
                                      mixer: MockAppAudioMixerService(), preferences: preferences)
        audio.receive(.init(availability: .available, outputs: [
            .init(id: "7", name: "MacBook Pro Speakers", isDefaultOutput: true, volume: 0.6, isMuted: false, canSetVolume: true, canSetMute: true),
            .init(id: "8", name: "AirPods Pro", isDefaultOutput: false, volume: 0.5),
            .init(id: "9", name: "Studio Display", isDefaultOutput: false)
        ]))
        // The model deliberately only exposes rows owned by regular running apps.
        // Use their identity with mock routes; this does not capture or modify audio.
        audio.receiveProcesses(NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }.prefix(2).map {
            .init(id: $0.processIdentifier, bundleID: $0.bundleIdentifier, controllableOutputDeviceIDs: ["7"])
        })
        defer { media.stop(); calendar.stop(); audio.stop(); presentation.reset() }
        for page in NotchPage.allCases {
            presentation.pageModel.selectedPage = page
            let view = NotchPagesView(model: presentation.pageModel, mediaRenderer: media,
                calendarRenderer: calendar, audioRenderer: audio, isExpanded: true,
                caffeine: CompositionCaffeine())
                .frame(width: 524, height: 228)
                .foregroundStyle(.white).background(.black)
                .environment(\.colorScheme, .dark)
                .transaction { $0.disablesAnimations = true }
            try await render(view, name: page.rawValue, size: CGSize(width: 524, height: 228))
        }
        calendar.toggleEvent(events[1].id)
        try await render(CalendarActivityView(model: calendar).frame(width: 524, height: 196).background(.black)
            .environment(\.colorScheme, .dark), name: "calendar-expanded", size: CGSize(width: 524, height: 196))
    }

    func testLongTrackWaveformAndQueueFixtures() async throws {
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let capture = TestAudioCapture()
        let meter = SystemAudioMeter(capture: capture, permissionGranted: { true }, activityClock: clock)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let state = MediaState(connectionState: .authenticated, playbackState: .playing,
            title: "A Moment Apart — Live at the Sydney Opera House", artist: "ODESZA & The Cinematic Orchestra",
            elapsed: 81, duration: 244, trackID: "long", activeDeviceID: "mac", activeDeviceName: "Living Room Speakers",
            volumePercent: 60, artwork: URL(string: "notchium-fixture://artwork/long"), source: .spotify,
            capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true, canSeek: true,
                                canShuffle: true, canRepeat: true, canSetVolume: true), shuffle: true, repeatMode: .track,
            queue: [.init(id: "next", title: "Something About Us", artist: "Daft Punk"),
                    .init(id: "later", title: "The Less I Know the Better", artist: "Tame Impala")])
        let media = MediaFeatureModel(provider: MockMediaProvider(snapshot: state), coordinator: presentation.activityCoordinator,
                                      audioMeter: meter)
        media.receive(state)
        for _ in 0..<30 { await Task.yield() }
        capture.levels?([0.4, 0.6, 0.8, 0.9, 0.7, 0.4, 0.2])
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(meter.isAudioActive)
        defer { media.stop(); presentation.reset() }
        try await render(MediaPageView(model: media)
            .frame(width: 524, height: 196).background(.black)
            .environment(\.colorScheme, .dark),
            name: "music-long", size: CGSize(width: 524, height: 196))
        try await render(UpNextView(state: state).padding(30).frame(width: 524, height: 196).background(.black)
            .environment(\.colorScheme, .dark), name: "queue", size: CGSize(width: 524, height: 196))
    }

    private func render(_ view: some View, name: String, size: CGSize) async throws {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/notch-composition-\(name).png"))
        XCTAssertEqual(host.bounds.size, size)
    }
}

@MainActor private final class CompositionCaffeine: NotchCaffeineControlling {
    let pressInteraction = CaffeinePressInteraction()
    var mode: CaffeineMode { .off }
    var isBusy: Bool { false }
    var selectedDuration: CaffeineDuration? { nil }
    var expiresAt: Date? { nil }
    var statusMessage: String? { nil }
    var needsClosedLidApproval: Bool { false }
    func cycleMode() {}
    func keepDisplayAwake() {}
    func keepAwake(for duration: CaffeineDuration) {}
    func openClosedLidApproval() {}
}
