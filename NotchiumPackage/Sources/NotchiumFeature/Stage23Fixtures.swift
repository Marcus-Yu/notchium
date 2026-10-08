#if DEBUG
import Foundation
import NotchiumServices

extension NotchiumApplicationController {
    /// Explicit mock launch for native accessibility and hostile-content QA. No hardware,
    /// account, EventKit or pasteboard access is used by these services.
    static func qualityServices() -> ServiceRegistry {
        let media = MockMediaProvider(snapshot: .init(playbackState: .paused,
            title: "A very long listening title — 日本語 🎧 with enough words to exercise truncation",
            artist: "Artist with a long name and an unusual character: Ω", elapsed: 92, duration: 225,
            trackID: "quality-fixture", volumePercent: 50, source: .spotify,
            capabilities: .init(canPlayPause: true, canSkipForward: true, canSkipBackward: true,
                canSeek: true, canShuffle: true, canRepeat: true, canSetVolume: true),
            shuffle: true, repeatMode: .track))
        let now = Date()
        let calendar = MockCalendarService(snapshot: .init(availability: .available, upcomingEvents: [
            .init(id: UUID(), title: "A long calendar meeting title — 設計レビュー with additional detail",
                  startDate: now.addingTimeInterval(1800), endDate: now.addingTimeInterval(3600),
                  location: "A long meeting room name", calendarName: "Quality fixture")
        ]))
        let audio = MockAudioDevicesService(snapshot: .init(availability: .available, outputs: [
            .init(id: "quality-speakers", name: "External headphones — long output name", isDefaultOutput: true,
                  volume: 0.5, isMuted: false, canSetVolume: true, canSetMute: true, transport: .bluetooth,
                  battery: .available(.init(left: 0.8, right: 0.75, caseLevel: 0.4,
                                            isCharging: true, measuredAt: now)))
        ]))
        let camera = MockCameraService(authorization: .notDetermined,
            devices: (1...7).map { .init(id: "quality-camera-\($0)", name: "Camera \($0) — External display") })
        return .mock(media: media, audioDevices: audio, calendar: calendar, camera: camera)
    }
}
#endif
