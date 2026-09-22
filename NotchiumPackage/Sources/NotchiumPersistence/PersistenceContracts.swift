import Foundation
import NotchiumCore
import NotchiumServices

public struct RetentionPolicy: Equatable, Sendable {
    public let clipboardMaximumAge: Duration
    public let clipboardMaximumItems: Int
    public let focusMaximumAge: Duration

    public init(
        clipboardMaximumAge: Duration,
        clipboardMaximumItems: Int,
        focusMaximumAge: Duration
    ) {
        self.clipboardMaximumAge = clipboardMaximumAge
        self.clipboardMaximumItems = clipboardMaximumItems
        self.focusMaximumAge = focusMaximumAge
    }

    public static let productDefault = RetentionPolicy(
        clipboardMaximumAge: .seconds(30 * 24 * 60 * 60),
        clipboardMaximumItems: 500,
        focusMaximumAge: .seconds(90 * 24 * 60 * 60)
    )
}

public struct RetentionReport: Equatable, Sendable {
    public let removedClipboardItems: Int
    public let removedFocusRecords: Int

    public init(removedClipboardItems: Int, removedFocusRecords: Int) {
        self.removedClipboardItems = removedClipboardItems
        self.removedFocusRecords = removedFocusRecords
    }

    public static let empty = RetentionReport(
        removedClipboardItems: 0,
        removedFocusRecords: 0
    )
}

public protocol PersistenceStoring: MediaSnapshotStoring, Sendable {
    func performRetentionCleanup(
        policy: RetentionPolicy,
        referenceDate: Date
    ) async throws -> RetentionReport
}

public actor RealPersistenceStore: PersistenceStoring {
    private static let mediaTrackKey = "notchium.media.last-track.v1"
    private let defaults: UserDefaults

    public init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func performRetentionCleanup(
        policy: RetentionPolicy,
        referenceDate: Date
    ) async throws -> RetentionReport {
        // Retention-managed feature payloads are still introduced by later stages.
        .empty
    }

    public func loadLastMediaTrack() -> CachedMediaTrack? {
        guard let data = defaults.data(forKey: Self.mediaTrackKey) else { return nil }
        return try? JSONDecoder().decode(CachedMediaTrack.self, from: data)
    }

    public func saveLastMediaTrack(_ track: CachedMediaTrack) {
        guard let data = try? JSONEncoder().encode(track) else { return }
        defaults.set(data, forKey: Self.mediaTrackKey)
    }
}

public actor MockPersistenceStore: PersistenceStoring {
    private let report: RetentionReport
    private var cleanupCount = 0
    private var mediaTrack: CachedMediaTrack?

    public init(report: RetentionReport = .empty) {
        self.report = report
    }

    public func performRetentionCleanup(
        policy: RetentionPolicy,
        referenceDate: Date
    ) -> RetentionReport {
        cleanupCount += 1
        return report
    }

    public func performedCleanupCount() -> Int {
        cleanupCount
    }

    public func loadLastMediaTrack() -> CachedMediaTrack? { mediaTrack }
    public func saveLastMediaTrack(_ track: CachedMediaTrack) { mediaTrack = track }
}
