import Foundation

public enum SuggestionCategory: CaseIterable, Hashable, Sendable {
    case upcomingMeeting, workBattery, completedTransfer, returnBrief
}

/// Evidence owners, not presentation destinations or permission grants.
public enum SuggestionSource: CaseIterable, Hashable, Sendable {
    case calendar, battery, transfers, pomodoro, caffeine, shortcuts, lifecycle
}

public struct SourceConsent: Equatable, Sendable {
    private var enabledSources: Set<SuggestionSource>

    public init(enabledSources: Set<SuggestionSource> = []) {
        self.enabledSources = enabledSources
    }

    public subscript(source: SuggestionSource) -> Bool {
        get { enabledSources.contains(source) }
        set {
            if newValue { enabledSources.insert(source) }
            else { enabledSources.remove(source) }
        }
    }
}

/// An owner supplies an opaque epoch; provider IDs must never be reused across epochs.
public struct SuggestionSourceIdentity: Hashable, Sendable {
    public let source: SuggestionSource
    public let epoch: UUID

    public init(source: SuggestionSource, epoch: UUID) {
        self.source = source
        self.epoch = epoch
    }
}

public struct SuggestionSourceRevision: Equatable, Sendable {
    public let identity: SuggestionSourceIdentity
    public let revision: UInt64

    public init(identity: SuggestionSourceIdentity, revision: UInt64) {
        self.identity = identity
        self.revision = revision
    }
}

public struct SuggestionOccurrence: Hashable, Sendable {
    public let source: SuggestionSourceIdentity
    public let token: UUID

    public init(source: SuggestionSourceIdentity, token: UUID) {
        self.source = source
        self.token = token
    }
}

/// Coalescing and per-occurrence suppression deliberately exclude content revision.
public struct SuggestionKey: Hashable, Sendable {
    public let occurrence: SuggestionOccurrence
    public let category: SuggestionCategory

    public init(occurrence: SuggestionOccurrence, category: SuggestionCategory) {
        self.occurrence = occurrence
        self.category = category
    }
}

public struct SuggestionIdentity: Hashable, Sendable {
    public let occurrence: SuggestionOccurrence
    public let category: SuggestionCategory
    public let revision: UInt64
    public var key: SuggestionKey { SuggestionKey(occurrence: occurrence, category: category) }

    public init(occurrence: SuggestionOccurrence, category: SuggestionCategory, revision: UInt64) {
        self.occurrence = occurrence
        self.category = category
        self.revision = revision
    }
}
