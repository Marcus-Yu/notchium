import Foundation

public enum TeleprompterSpeechAvailability: Equatable, Sendable {
    case available
    case requiresDownload
    case microphoneNotDetermined
    case denied
    case restricted
    case unsupportedLocale
    case unavailable
}

public enum TeleprompterSpeechFailure: Error, Equatable, Sendable {
    case microphoneDenied
    case microphoneRestricted
    case unsupportedLocale
    case unavailable
    case assetsUnavailable
    case audioInputUnavailable
    case audioConfigurationChanged
    case sessionInterrupted
    case recognitionFailed
    case audioProcessingOverloaded
}

public struct TeleprompterMicrophone: Identifiable, Equatable, Sendable {
    /// Stable Core Audio device UID, never a transient process/object identifier.
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool) {
        self.id = id; self.name = name; self.isDefault = isDefault
    }
}

public enum TeleprompterSpeechEvent: Equatable, Sendable {
    case preparing
    case downloadingAssets
    case ready
    case inputDevice(name: String)
    /// Linear root-mean-square microphone amplitude, in the range 0...1.
    case audioLevel(Double)
    /// A replacement for the supplied audio range, not an append-only fragment.
    case transcript(text: String, audioStart: TimeInterval, audioEnd: TimeInterval, isFinal: Bool)
    case failure(TeleprompterSpeechFailure)
}

/// Captures microphone input only after an explicit start. Audio and recognition text
/// remain in memory; ending the stream or calling stop releases capture and analysis.
public protocol TeleprompterSpeechService: Sendable {
    func availability(localeIdentifier: String) async -> TeleprompterSpeechAvailability
    func inputDevices() async -> [TeleprompterMicrophone]
    func start(localeIdentifier: String) async throws -> AsyncStream<TeleprompterSpeechEvent>
    func start(localeIdentifier: String, inputDeviceID: String?) async throws -> AsyncStream<TeleprompterSpeechEvent>
    func stop() async
}

public extension TeleprompterSpeechService {
    func inputDevices() async -> [TeleprompterMicrophone] { [] }

    func start(localeIdentifier: String, inputDeviceID: String?) async throws -> AsyncStream<TeleprompterSpeechEvent> {
        guard inputDeviceID == nil else { throw TeleprompterSpeechFailure.audioInputUnavailable }
        return try await start(localeIdentifier: localeIdentifier)
    }
}

/// An event-driven provider that never requests permission or opens an audio device.
public actor MockTeleprompterSpeechService: TeleprompterSpeechService {
    private let status: TeleprompterSpeechAvailability
    private let initialEvents: [TeleprompterSpeechEvent]
    private let startFailure: TeleprompterSpeechFailure?
    private let microphones: [TeleprompterMicrophone]
    private var continuation: AsyncStream<TeleprompterSpeechEvent>.Continuation?
    private var generation = 0
    public private(set) var startCount = 0
    public private(set) var stopCount = 0
    public private(set) var requestedInputDeviceID: String?

    public init(availability: TeleprompterSpeechAvailability = .available,
                events: [TeleprompterSpeechEvent] = [.ready],
                failure: TeleprompterSpeechFailure? = nil, microphones: [TeleprompterMicrophone] = []) {
        status = availability
        initialEvents = events
        startFailure = failure
        self.microphones = microphones
    }

    isolated deinit { continuation?.finish() }

    public func availability(localeIdentifier: String) -> TeleprompterSpeechAvailability { status }
    public func inputDevices() async -> [TeleprompterMicrophone] { microphones }

    public func start(localeIdentifier: String, inputDeviceID: String?) async throws -> AsyncStream<TeleprompterSpeechEvent> {
        requestedInputDeviceID = inputDeviceID
        return try start(localeIdentifier: localeIdentifier)
    }

    public func start(localeIdentifier: String) throws -> AsyncStream<TeleprompterSpeechEvent> {
        if let startFailure { throw startFailure }
        continuation?.finish()
        generation &+= 1
        let token = generation
        startCount += 1
        let pair = AsyncStream.makeStream(of: TeleprompterSpeechEvent.self, bufferingPolicy: .bufferingNewest(64))
        continuation = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.end(ifCurrent: token) }
        }
        for event in initialEvents { pair.continuation.yield(event) }
        return pair.stream
    }

    public func emit(_ event: TeleprompterSpeechEvent) { continuation?.yield(event) }

    public func stop() {
        generation &+= 1
        stopCount += 1
        continuation?.finish()
        continuation = nil
    }

    private func end(ifCurrent token: Int) {
        guard token == generation else { return }
        stop()
    }
}
