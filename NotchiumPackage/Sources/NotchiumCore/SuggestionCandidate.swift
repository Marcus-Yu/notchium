import Foundation

/// Descriptions only. Resolution, permission checks, approval and execution belong to
/// future composition-owned adapters. An ID is never an authorization token.
public enum ProactiveAction: Equatable, Sendable {
    case joinCurrentMeeting(SuggestionOccurrence)
    case showMirror
    case ensureCaffeine(CaffeineDuration)
    case startPomodoro(duration: Duration)
    case runPinnedShortcut(pinID: UUID)
    case revealObservedTransfer(SuggestionOccurrence)
    case addObservedTransferToShelf(SuggestionOccurrence)
}

public enum SuggestionWorkContext: Equatable, Sendable {
    case caffeine
    case pomodoro(remaining: Duration)
}

public enum SuggestionEvidence: Equatable, Sendable {
    case upcomingMeeting(startsAt: Date, endsAt: Date)
    case workBattery(percent: Int, work: SuggestionWorkContext)
    case completedTransfer(reportedBytes: Int64)
    case returnBrief(observedFactCount: Int, sources: Set<SuggestionSource>)

    public var requiredSources: Set<SuggestionSource> {
        switch self {
        case .upcomingMeeting: [.calendar]
        case .workBattery(_, .caffeine): [.battery, .caffeine]
        case .workBattery(_, .pomodoro): [.battery, .pomodoro]
        case .completedTransfer: [.transfers]
        case let .returnBrief(_, sources): sources.union([.lifecycle])
        }
    }
}

/// This never maps directly to an activity priority. All proactive actions are optional.
public enum SuggestionInterruptionImportance: Equatable, Sendable {
    case routine, timeSensitive
}

public struct SuggestionCandidate: Equatable, Sendable {
    public let identity: SuggestionIdentity
    public let evidence: SuggestionEvidence
    public let structuredEvidence: Double
    public let urgency: Double
    public let supportingRevisions: [SuggestionSource: SuggestionSourceRevision]
    public let createdAt: Date
    public let eligibleAt: Date
    public let relevantUntil: Date
    public let actions: [ProactiveAction]
    public let importance: SuggestionInterruptionImportance

    public init(identity: SuggestionIdentity, evidence: SuggestionEvidence,
                structuredEvidence: Double, urgency: Double, createdAt: Date, eligibleAt: Date,
                relevantUntil: Date, actions: [ProactiveAction], importance: SuggestionInterruptionImportance,
                supportingRevisions: [SuggestionSource: SuggestionSourceRevision] = [:]) {
        self.identity = identity
        self.evidence = evidence
        self.structuredEvidence = structuredEvidence
        self.urgency = urgency
        self.supportingRevisions = supportingRevisions
        self.createdAt = createdAt
        self.eligibleAt = eligibleAt
        self.relevantUntil = relevantUntil
        self.actions = actions
        self.importance = importance
    }
}

/// An immutable owner projection; no provider object or personal content crosses this boundary.
public struct SuggestionSourceSnapshot: Equatable, Sendable {
    public let occurrence: SuggestionOccurrence
    public let revision: UInt64
    public let availability: FeatureAvailability
    public let isCancelled: Bool
    public let validUntil: Date

    public init(occurrence: SuggestionOccurrence, revision: UInt64, availability: FeatureAvailability,
                isCancelled: Bool, validUntil: Date) {
        self.occurrence = occurrence
        self.revision = revision
        self.availability = availability
        self.isCancelled = isCancelled
        self.validUntil = validUntil
    }
}

public struct MeetingSuggestionInput: Equatable, Sendable {
    public let identity: SuggestionIdentity
    public let startsAt: Date
    public let endsAt: Date
    public let isAllDay: Bool
    public let supportedMeetingLinkAvailable: Bool

    public init(identity: SuggestionIdentity, startsAt: Date, endsAt: Date,
                isAllDay: Bool, supportedMeetingLinkAvailable: Bool) {
        self.identity = identity
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.supportedMeetingLinkAvailable = supportedMeetingLinkAvailable
    }
}
