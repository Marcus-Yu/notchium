import Foundation

/// Provisional engineering hypotheses, not calibrated probabilities.
public enum SuggestionPolicyDefaults {
    public static let evidenceWeight = 0.55
    public static let urgencyWeight = 0.20
    public static let affinityWeight = 0.25
    public static let eligibilityThreshold = 0.75
    public static let initialWeight = 2.0
    public static let acceptWeight = 1.0
    public static let dismissWeight = 1.0
    public static let ignoreWeight = 0.25
    public static let lessLikeThisWeight = 3.0
    public static let maximumTotalWeight = 32.0
    public static let maximumPendingCandidates = 8
    public static let maximumActions = 7
    public static let maximumFeedbackReceipts = 128
    public static let maximumUnsolicitedExposuresPerDay = 3
    public static let globalCooldown: Duration = .seconds(30 * 60)
    public static let categoryQuietDuration: Duration = .seconds(7 * 24 * 60 * 60)
    public static let negativeQuietingCount = 3
    public static let minimumVisibleExposure: Duration = .seconds(5)
    public static let meetingLeadTime: TimeInterval = 5 * 60
    public static let meetingGraceTime: TimeInterval = 2 * 60
}

public struct SuggestionPolicyConfiguration: Equatable, Sendable {
    public var maximumDailyExposures = SuggestionPolicyDefaults.maximumUnsolicitedExposuresPerDay
    public var globalCooldown = SuggestionPolicyDefaults.globalCooldown
    public var categoryQuietDuration = SuggestionPolicyDefaults.categoryQuietDuration
    public var negativeQuietingCount = SuggestionPolicyDefaults.negativeQuietingCount
    public var minimumVisibleExposure = SuggestionPolicyDefaults.minimumVisibleExposure

    public init() {}

    public var isValid: Bool {
        maximumDailyExposures > 0 && globalCooldown >= .zero && categoryQuietDuration >= .zero
            && (1...SuggestionPolicyDefaults.maximumFeedbackReceipts).contains(negativeQuietingCount)
            && minimumVisibleExposure > .zero
    }
}

public enum SuggestionWithdrawalReason: Equatable, Sendable {
    case hiddenExpiry, sourceInvalidated, stopped, policyChanged
}

public enum SuggestionResponse: Equatable, Sendable {
    case opened
    case accept
    case snooze(for: Duration)
    case dismiss
    /// Confirmed cumulative visible duration, excluding hidden/queued/sleeping time.
    case ignore(visibleDuration: Duration)
    case lessLikeThis
    case neverSuggestThis
    case withdraw(SuggestionWithdrawalReason)
}

/// An explicit receipt for the optional suggestion actually being rendered. Submission
/// and an existing essential source alert are not exposures. The ID is supplied by the owner.
public struct SuggestionExposure: Equatable, Sendable {
    public let id: UUID
    public let identity: SuggestionIdentity
    public let relevantUntil: Date
    public let beganAt: ProactiveTime

    public init(id: UUID, identity: SuggestionIdentity, relevantUntil: Date, beganAt: ProactiveTime) {
        self.id = id
        self.identity = identity
        self.relevantUntil = relevantUntil
        self.beganAt = beganAt
    }
}
