import NotchiumCore

public struct AudioDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isDefaultOutput: Bool
    public let volume: Double?

    public init(
        id: String,
        name: String,
        isDefaultOutput: Bool,
        volume: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.isDefaultOutput = isDefaultOutput
        self.volume = volume
    }
}

public struct AudioDevicesSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let outputs: [AudioDevice]

    public init(
        availability: FeatureAvailability,
        outputs: [AudioDevice] = []
    ) {
        self.availability = availability
        self.outputs = outputs
    }
}

public protocol AudioDevicesService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<AudioDevicesSnapshot>
    func selectOutput(id: String) async throws
    func setVolume(_ volume: Double, deviceID: String) async throws
}

public struct RealAudioDevicesService: AudioDevicesService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.audioDevices)
    }

    public func updates() async -> AsyncStream<AudioDevicesSnapshot> {
        oneShotStream(AudioDevicesSnapshot(availability: stageOneUnavailable(.audioDevices)))
    }

    public func selectOutput(id: String) async throws {
        throw ServiceFailure.stageTwoRequired(.audioDevices)
    }

    public func setVolume(_ volume: Double, deviceID: String) async throws {
        throw ServiceFailure.stageTwoRequired(.audioDevices)
    }
}

public struct MockAudioDevicesService: AudioDevicesService {
    public let snapshot: AudioDevicesSnapshot

    public init(
        snapshot: AudioDevicesSnapshot = AudioDevicesSnapshot(availability: .available)
    ) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<AudioDevicesSnapshot> {
        oneShotStream(snapshot)
    }

    public func selectOutput(id: String) async throws {}
    public func setVolume(_ volume: Double, deviceID: String) async throws {}
}
