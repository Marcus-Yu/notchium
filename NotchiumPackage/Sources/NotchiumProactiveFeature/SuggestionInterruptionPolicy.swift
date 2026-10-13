import Foundation
import NotchiumCore

public enum SuggestionInterruptionPolicy {
    public static func evaluate(_ candidate: SuggestionCandidate, in context: SuggestionEligibilityContext,
                                feedback: SuggestionFeedbackState,
                                configuration: SuggestionPolicyConfiguration = .init()) -> SuggestionEligibilityDecision {
        guard context.isEnabled else { return .discard(.globallyDisabled) }
        guard configuration.isValid, context.time.isValid, context.dailyExposureCount >= 0,
              context.otherPendingCandidateCount >= 0, context.timingPenalty.isFinite,
              context.timingPenalty >= 0,
              context.wallTimeFloor?.timeIntervalSinceReferenceDate.isFinite != false else { return .discard(.invalidInput) }
        let wallDate = max(context.time.wallDate,
                           max(context.wallTimeFloor ?? context.time.wallDate, feedback.wallTimeFloor ?? context.time.wallDate))
        if let reason = SuggestionCandidateValidity.rejection(for: candidate, source: context.source,
                                                               consent: context.consent, wallDate: wallDate,
                                                               supportingSources: context.supportingSources) {
            return .discard(reason)
        }
        let category = feedback[candidate.identity.category]
        guard !category.isDisabled else { return .discard(.categoryDisabled) }
        guard !feedback.isSuppressed(candidate.identity.key) else { return .discard(.occurrenceSuppressed) }
        guard feedback.hasReceiptCapacity else { return .discard(.feedbackCapacity) }
        if feedback.hasOpenExposure(candidate.identity.key) { return .deferred(.protectedPresentation, until: nil) }
        let latestReceipt = feedback.exposures.last { $0.exposure.identity.key == candidate.identity.key }
        let snoozedUntil = latestReceipt?.snoozedUntil
        guard context.restrictions.isEmpty else { return .deferred(.protectedPresentation, until: nil) }
        if context.focus == .on, context.quietDuringKnownFocus { return .deferred(.focus, until: nil) }
        // A bounded explicit snooze requests this occurrence's return; it is not another
        // unsolicited exposure. Other owner/protected/category gates still apply.
        if snoozedUntil == nil, context.dailyExposureCount >= configuration.maximumDailyExposures {
            return .deferred(.dailyCap, until: nil)
        }
        if context.otherPendingCandidateCount >= SuggestionPolicyDefaults.maximumPendingCandidates {
            return .deferred(.pendingCapacity, until: nil)
        }
        let score = SuggestionScoring.score(evidence: candidate.structuredEvidence, urgency: candidate.urgency,
                                           affinity: category.affinity, timingPenalty: context.timingPenalty)
        guard SuggestionScoring.meetsThreshold(score) else { return .discard(.belowThreshold) }

        var remaining = max(.zero, Duration.seconds(candidate.eligibleAt.timeIntervalSince(context.time.wallDate)))
        var reason: SuggestionDeferralReason = .notYetEligible
        let ownSnoozedReturn = snoozedUntil != nil && feedback.exposures.last?.exposure.identity.key == candidate.identity.key
        let globalCooldown = ownSnoozedReturn ? nil : feedback.globalCooldown
        for cooldown in [globalCooldown, category.cooldown, context.manualCooldown].compactMap({ $0 }) {
            guard cooldown.startedAt.isValid, cooldown.duration.timeInterval.isFinite,
                  cooldown.wallUntil.timeIntervalSinceReferenceDate.isFinite else { return .discard(.invalidInput) }
            let value = cooldown.remaining(at: context.time)
            if value > remaining { remaining = value; reason = .cooldown }
        }
        // Only the latest snooze for this occurrence can request a future eligibility value.
        if let until = snoozedUntil {
            let value: Duration = until.runID == context.time.runID
                ? max(.zero, until.elapsed - context.time.elapsed)
                : .seconds(max(0, until.wallDate.timeIntervalSince(context.time.wallDate)))
            if value > remaining { remaining = value; reason = .cooldown }
        }
        guard remaining > .zero else { return .eligible(score: score) }
        // A wall jump cannot end an elapsed cooldown; absolute relevance still expires independently.
        guard wallDate.addingTimeInterval(remaining.timeInterval) < candidate.relevantUntil else {
            return .discard(.noEligibleWindow)
        }
        return .deferred(reason, until: context.time.advanced(by: remaining))
    }
}
