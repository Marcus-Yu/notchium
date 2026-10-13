import Foundation

public enum SuggestionFocusState: Equatable, Sendable {
    case unknown, on, off
}

/// A future composition layer projects the existing owners into these booleans.
/// This value neither ranks activities nor owns display/fullscreen state.
public struct SuggestionPresentationRestrictions: OptionSet, Equatable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let sleeping = Self(rawValue: 1 << 0)
    public static let fullscreen = Self(rawValue: 1 << 1)
    public static let presenting = Self(rawValue: 1 << 2)
    public static let expanded = Self(rawValue: 1 << 3)
    public static let manualInteraction = Self(rawValue: 1 << 4)
    public static let auxiliaryInteraction = Self(rawValue: 1 << 5)
    public static let dragging = Self(rawValue: 1 << 6)
    public static let mirror = Self(rawValue: 1 << 7)
    public static let protectedTransient = Self(rawValue: 1 << 8)
    public static let criticalActivity = Self(rawValue: 1 << 9)
    public static let activeTransfer = Self(rawValue: 1 << 10)
    public static let protectedTimer = Self(rawValue: 1 << 11)
}

public struct SuggestionEligibilityContext: Equatable, Sendable {
    public var time: ProactiveTime
    public var isEnabled: Bool
    public var consent: SourceConsent
    public var source: SuggestionSourceSnapshot
    /// Required secondary evidence owners (for example Caffeine in work battery advice).
    /// The closed source enum bounds this projection; missing evidence fails closed.
    public var supportingSources: [SuggestionSource: SuggestionSourceSnapshot] = [:]
    public var focus: SuggestionFocusState = .unknown
    public var quietDuringKnownFocus = true
    public var restrictions: SuggestionPresentationRestrictions = []
    public var manualCooldown: SuggestionCooldown?
    /// The owner supplies its high-water wall date so a backwards clock cannot replay expiry.
    public var wallTimeFloor: Date?
    /// Count actual unsolicited exposures in the owner's current local-day accounting window.
    public var dailyExposureCount = 0
    /// Excludes this occurrence, including when checking an update at full capacity.
    public var otherPendingCandidateCount = 0
    public var timingPenalty = 0.0

    public init(time: ProactiveTime, isEnabled: Bool, consent: SourceConsent, source: SuggestionSourceSnapshot) {
        self.time = time
        self.isEnabled = isEnabled
        self.consent = consent
        self.source = source
    }
}

public enum SuggestionDiscardReason: Equatable, Sendable {
    case globallyDisabled, sourceNotConsented, categoryDisabled, sourceUnavailable
    case sourceIdentityChanged, staleRevision, staleSource, cancelled, expired
    case invalidCandidate, invalidInput, occurrenceSuppressed, belowThreshold
    case noEligibleWindow, feedbackCapacity
}

public enum SuggestionDeferralReason: Equatable, Sendable {
    case notYetEligible, cooldown, focus, protectedPresentation, dailyCap, pendingCapacity
}

public enum SuggestionEligibilityDecision: Equatable, Sendable {
    case eligible(score: Double)
    /// nil means wait for a meaningful owner state change, without scheduling a timer here.
    case deferred(SuggestionDeferralReason, until: ProactiveTime?)
    case discard(SuggestionDiscardReason)
}
