import Foundation
import NotchiumCore

public struct SystemStatsSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let cpuUtilization: Double?
    public let usedMemoryBytes: UInt64?
    public let totalMemoryBytes: UInt64?
    public let networkReceivedBytesPerSecond: UInt64?
    public let networkSentBytesPerSecond: UInt64?
    public let sampledAt: Date?

    public init(
        availability: FeatureAvailability,
        cpuUtilization: Double? = nil,
        usedMemoryBytes: UInt64? = nil,
        totalMemoryBytes: UInt64? = nil,
        networkReceivedBytesPerSecond: UInt64? = nil,
        networkSentBytesPerSecond: UInt64? = nil,
        sampledAt: Date? = nil
    ) {
        self.availability = availability
        self.cpuUtilization = cpuUtilization
        self.usedMemoryBytes = usedMemoryBytes
        self.totalMemoryBytes = totalMemoryBytes
        self.networkReceivedBytesPerSecond = networkReceivedBytesPerSecond
        self.networkSentBytesPerSecond = networkSentBytesPerSecond
        self.sampledAt = sampledAt
    }
}

public protocol SystemStatsService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<SystemStatsSnapshot>
    func refresh() async throws
}

public struct RealSystemStatsService: SystemStatsService {
    public init() {}

    public func availability() async -> FeatureAvailability {
        stageOneUnavailable(.systemStats)
    }

    public func updates() async -> AsyncStream<SystemStatsSnapshot> {
        oneShotStream(SystemStatsSnapshot(availability: stageOneUnavailable(.systemStats)))
    }

    public func refresh() async throws {
        throw ServiceFailure.stageTwoRequired(.systemStats)
    }
}

public struct MockSystemStatsService: SystemStatsService {
    public let snapshot: SystemStatsSnapshot

    public init(
        snapshot: SystemStatsSnapshot = SystemStatsSnapshot(availability: .available)
    ) {
        self.snapshot = snapshot
    }

    public func availability() async -> FeatureAvailability {
        snapshot.availability
    }

    public func updates() async -> AsyncStream<SystemStatsSnapshot> {
        oneShotStream(snapshot)
    }

    public func refresh() async throws {}
}
