import Foundation
import NotchiumCore

public struct AudioLevelSample: Equatable, Sendable {
    public let rms: Double
    public let peak: Double
    public let sampledAt: Date

    public init(rms: Double, peak: Double, sampledAt: Date) {
        self.rms = rms
        self.peak = peak
        self.sampledAt = sampledAt
    }
}

public protocol AudioMeterProvider: Sendable {
    func availability() async -> FeatureAvailability
    func samples() async -> AsyncStream<AudioLevelSample>
}

public struct RealAudioMeterProvider: AudioMeterProvider {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.audioMeter)
    }

    public func samples() async -> AsyncStream<AudioLevelSample> {
        AsyncStream { $0.finish() }
    }
}

public struct MockAudioMeterProvider: AudioMeterProvider {
    public let sample: AudioLevelSample?

    public init(sample: AudioLevelSample? = nil) {
        self.sample = sample
    }

    public func availability() async -> FeatureAvailability {
        .available
    }

    public func samples() async -> AsyncStream<AudioLevelSample> {
        guard let sample else { return AsyncStream { $0.finish() } }
        return oneShotStream(sample)
    }
}

public enum ActivityKind: String, CaseIterable, Sendable {
    case volume
    case brightness
    case microphone
    case battery
    case audioConnection
    case media
    case meeting
    case download
    case screenshot
    case clipboardAction
    case ocr
}

public struct ActivityEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: ActivityKind
    public let occurredAt: Date

    public init(id: UUID, kind: ActivityKind, occurredAt: Date) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
    }
}

public protocol ActivityEventSource: Sendable {
    func availability() async -> FeatureAvailability
    func events() async -> AsyncStream<ActivityEvent>
}

public struct RealActivityEventSource: ActivityEventSource {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.activityEvents)
    }

    public func events() async -> AsyncStream<ActivityEvent> {
        AsyncStream { $0.finish() }
    }
}

public struct MockActivityEventSource: ActivityEventSource {
    public let event: ActivityEvent?

    public init(event: ActivityEvent? = nil) {
        self.event = event
    }

    public func availability() async -> FeatureAvailability {
        .available
    }

    public func events() async -> AsyncStream<ActivityEvent> {
        guard let event else { return AsyncStream { $0.finish() } }
        return oneShotStream(event)
    }
}

public struct BrowserActivitySample: Equatable, Sendable {
    public let domain: String
    public let observedAt: Date

    public init(domain: String, observedAt: Date) {
        self.domain = domain
        self.observedAt = observedAt
    }
}

public protocol BrowserActivityProvider: Sendable {
    func availability() async -> FeatureAvailability
    func domainEvents() async -> AsyncStream<BrowserActivitySample>
}

public struct RealBrowserActivityProvider: BrowserActivityProvider {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.browserActivity)
    }

    public func domainEvents() async -> AsyncStream<BrowserActivitySample> {
        AsyncStream { $0.finish() }
    }
}

public struct MockBrowserActivityProvider: BrowserActivityProvider {
    public let sample: BrowserActivitySample?

    public init(sample: BrowserActivitySample? = nil) {
        self.sample = sample
    }

    public func availability() async -> FeatureAvailability {
        .available
    }

    public func domainEvents() async -> AsyncStream<BrowserActivitySample> {
        guard let sample else { return AsyncStream { $0.finish() } }
        return oneShotStream(sample)
    }
}

public typealias MediaProvider = MediaService
public typealias CalendarProvider = CalendarService
public typealias ShelfStore = ShelfService
public typealias CameraProvider = CameraService
public typealias AudioDeviceProvider = AudioDevicesService
public typealias WakeLockProvider = CaffeineService
public typealias KeyboardGate = KeyboardLockService
public typealias ClipboardProvider = ClipboardService
public typealias SystemMetricsProvider = SystemStatsService
public typealias FocusTracker = FocusService
public typealias PermissionAuthorizer = PermissionAuthorizing
