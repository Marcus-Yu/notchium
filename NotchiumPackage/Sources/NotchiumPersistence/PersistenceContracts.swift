import Foundation
import NotchiumCore

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

public protocol PersistenceStoring: Sendable {
    func performRetentionCleanup(
        policy: RetentionPolicy,
        referenceDate: Date
    ) async throws -> RetentionReport
}

public struct RealPersistenceStore: PersistenceStoring {
    public init() {}

    public func performRetentionCleanup(
        policy: RetentionPolicy,
        referenceDate: Date
    ) async throws -> RetentionReport {
        // Stage 1 deliberately has no feature payload persistence.
        .empty
    }
}

public actor MockPersistenceStore: PersistenceStoring {
    private let report: RetentionReport
    private var cleanupCount = 0

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
}
