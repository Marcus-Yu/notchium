import Foundation
import NotchCore
import NotchDiagnostics
import NotchPersistence
import NotchServices

public enum FixtureFactory {
    public static let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    public static let mediaSnapshot = MediaSnapshot(
        availability: .available,
        playbackState: .playing,
        title: "Fixture Track",
        artist: "Fixture Artist",
        elapsed: 42,
        duration: 180
    )

    public static let calendarSnapshot = CalendarSnapshot(
        availability: .available,
        upcomingEvents: [
            CalendarEventSummary(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                title: "Fixture Meeting",
                startDate: referenceDate.addingTimeInterval(600),
                endDate: referenceDate.addingTimeInterval(2_400),
                meetingURL: URL(string: "https://meet.example.com/fixture")
            ),
        ]
    )

    public static func serviceRegistry() -> ServiceRegistry {
        ServiceRegistry(
            media: MockMediaService(snapshot: mediaSnapshot),
            calendar: MockCalendarService(snapshot: calendarSnapshot),
            shelf: MockShelfService(),
            screenshot: MockScreenshotService(),
            clipboard: MockClipboardService(),
            camera: MockCameraService(),
            audioDevices: MockAudioDevicesService(),
            battery: MockBatteryService(
                snapshot: BatterySnapshot(
                    availability: .available,
                    chargeLevel: 0.72,
                    isCharging: true,
                    isConnectedToPower: true
                )
            ),
            caffeine: MockCaffeineService(),
            keyboardLock: MockKeyboardLockService(),
            systemStats: MockSystemStatsService(),
            downloads: MockDownloadsService(),
            meetings: MockMeetingsService(),
            focus: MockFocusService(),
            audioMeter: MockAudioMeterProvider(
                sample: AudioLevelSample(rms: 0.25, peak: 0.5, sampledAt: referenceDate)
            ),
            activityEvents: MockActivityEventSource(),
            browserActivity: MockBrowserActivityProvider()
        )
    }

    public static func clock() -> TestAppClock {
        TestAppClock(now: referenceDate)
    }

    public static func logger() -> MockAppLogger {
        MockAppLogger()
    }

    public static func persistence() -> MockPersistenceStore {
        MockPersistenceStore()
    }
}
