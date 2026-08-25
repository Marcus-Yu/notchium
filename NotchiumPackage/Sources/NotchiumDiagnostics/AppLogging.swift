import Foundation
import NotchiumCore
import OSLog

public enum AppLogLevel: String, Equatable, Sendable {
    case debug
    case info
    case notice
    case error
}

public enum AppLogEvent: String, Equatable, Sendable {
    case applicationStarted
    case applicationStopped
    case notchPanelShown
    case notchPanelUnavailable
    case providerUnavailable
    case permissionStateChanged
    case retentionCleanupCompleted
    case syntheticActivityCreated
}

public struct AppLogEntry: Equatable, Sendable {
    public let event: AppLogEvent
    public let level: AppLogLevel

    public init(event: AppLogEvent, level: AppLogLevel) {
        self.event = event
        self.level = level
    }
}

public protocol AppLogging: Sendable {
    func record(_ event: AppLogEvent, level: AppLogLevel) async
}

public actor UnifiedAppLogger: AppLogging {
    private let logger: Logger

    public init(
        subsystem: String = "com.marcusyu.notchium",
        category: String = "application"
    ) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func record(_ event: AppLogEvent, level: AppLogLevel) {
        switch level {
        case .debug:
            logger.debug("\(event.rawValue, privacy: .public)")
        case .info:
            logger.info("\(event.rawValue, privacy: .public)")
        case .notice:
            logger.notice("\(event.rawValue, privacy: .public)")
        case .error:
            logger.error("\(event.rawValue, privacy: .public)")
        }
    }
}

public actor MockAppLogger: AppLogging {
    private var recordedEntries: [AppLogEntry] = []

    public init() {}

    public func record(_ event: AppLogEvent, level: AppLogLevel) {
        recordedEntries.append(AppLogEntry(event: event, level: level))
    }

    public func entries() -> [AppLogEntry] {
        recordedEntries
    }
}
