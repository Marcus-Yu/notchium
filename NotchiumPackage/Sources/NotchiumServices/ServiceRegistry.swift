import NotchiumCore

public struct ServiceRegistry: Sendable {
    public let media: any MediaService
    public let calendar: any CalendarService
    public let shelf: any ShelfService
    public let screenshot: any ScreenshotService
    public let clipboard: any ClipboardService
    public let camera: any CameraService
    public let audioDevices: any AudioDevicesService
    public let audioProcesses: any AudioProcessesService
    public let appAudioMixer: any AppAudioMixerService
    public let battery: any BatteryService
    public let caffeine: any CaffeineService
    public let systemStats: any SystemStatsService
    public let transfers: any FileTransferService
    public let meetings: any MeetingsService
    public let focus: any FocusService
    public let audioMeter: any AudioMeterProvider
    public let activityEvents: any ActivityEventSource
    public let browserActivity: any BrowserActivityProvider

    public init(
        media: any MediaService,
        calendar: any CalendarService,
        shelf: any ShelfService,
        screenshot: any ScreenshotService,
        clipboard: any ClipboardService,
        camera: any CameraService,
        audioDevices: any AudioDevicesService,
        audioProcesses: any AudioProcessesService = MockAudioProcessesService(),
        appAudioMixer: any AppAudioMixerService = MockAppAudioMixerService(),
        battery: any BatteryService,
        caffeine: any CaffeineService,
        systemStats: any SystemStatsService,
        transfers: any FileTransferService,
        meetings: any MeetingsService,
        focus: any FocusService,
        audioMeter: any AudioMeterProvider,
        activityEvents: any ActivityEventSource,
        browserActivity: any BrowserActivityProvider
    ) {
        self.media = media
        self.calendar = calendar
        self.shelf = shelf
        self.screenshot = screenshot
        self.clipboard = clipboard
        self.camera = camera
        self.audioDevices = audioDevices
        self.audioProcesses = audioProcesses
        self.appAudioMixer = appAudioMixer
        self.battery = battery
        self.caffeine = caffeine
        self.systemStats = systemStats
        self.transfers = transfers
        self.meetings = meetings
        self.focus = focus
        self.audioMeter = audioMeter
        self.activityEvents = activityEvents
        self.browserActivity = browserActivity
    }

    @MainActor public static func real() -> ServiceRegistry {
        ServiceRegistry(
            media: RealMediaService(),
            calendar: RealCalendarService(),
            shelf: RealShelfService(),
            screenshot: RealScreenshotService(),
            clipboard: RealClipboardService(),
            camera: RealCameraService(),
            audioDevices: RealAudioDevicesService(),
            audioProcesses: RealAudioProcessesService(),
            appAudioMixer: RealAppAudioMixerService(),
            battery: RealBatteryService(),
            caffeine: RealCaffeineService(),
            systemStats: RealSystemStatsService(),
            transfers: RealFileTransferService(),
            meetings: RealMeetingsService(),
            focus: RealFocusService(),
            audioMeter: RealAudioMeterProvider(),
            activityEvents: RealActivityEventSource(),
            browserActivity: RealBrowserActivityProvider()
        )
    }

#if DEBUG
    public static func mock(media: any MediaService = MockMediaService(),
                            audioDevices: any AudioDevicesService = MockAudioDevicesService(),
                            calendar: any CalendarService = MockCalendarService(),
                            camera: any CameraService = MockCameraService()) -> ServiceRegistry {
        ServiceRegistry(
            media: media,
            calendar: calendar,
            shelf: MockShelfService(),
            screenshot: MockScreenshotService(),
            clipboard: MockClipboardService(),
            camera: camera,
            audioDevices: audioDevices,
            audioProcesses: MockAudioProcessesService(),
            appAudioMixer: MockAppAudioMixerService(),
            battery: MockBatteryService(),
            caffeine: MockCaffeineService(),
            systemStats: MockSystemStatsService(),
            transfers: MockFileTransferService(),
            meetings: MockMeetingsService(),
            focus: MockFocusService(),
            audioMeter: MockAudioMeterProvider(),
            activityEvents: MockActivityEventSource(),
            browserActivity: MockBrowserActivityProvider()
        )
    }
#endif

    public func availability(for service: ServiceKind) async -> FeatureAvailability {
        switch service {
        case .media:
            await media.availability()
        case .calendar:
            await calendar.availability()
        case .shelf:
            .available
        case .screenshot:
            await screenshot.availability()
        case .clipboard:
            await clipboard.availability()
        case .camera:
            await camera.availability()
        case .audioDevices:
            await audioDevices.availability()
        case .battery:
            await battery.availability()
        case .caffeine:
            await caffeine.availability()
        case .systemStats:
            await systemStats.availability()
        case .downloads:
            await transfers.availability()
        case .meetings:
            await meetings.availability()
        case .focus:
            await focus.availability()
        case .audioMeter:
            await audioMeter.availability()
        case .activityEvents:
            await activityEvents.availability()
        case .browserActivity:
            await browserActivity.availability()
        }
    }
}
