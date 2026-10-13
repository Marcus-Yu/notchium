import Foundation
import NotchiumCore

public enum SuggestionFeedbackResult: Equatable, Sendable {
    case recorded, applied, duplicate, unknownExposure, invalidInput, occurrenceSuppressed
    case categoryDisabled, exposureAlreadyOpen, capacityReached
}

public enum SuggestionFeedbackReducer {
    @discardableResult
    public static func recordExposure(_ exposure: SuggestionExposure, in state: inout SuggestionFeedbackState,
                                      configuration: SuggestionPolicyConfiguration = .init()) -> SuggestionFeedbackResult {
        guard configuration.isValid, exposure.beganAt.isValid,
              exposure.relevantUntil.timeIntervalSinceReferenceDate.isFinite,
              exposure.beganAt.wallDate < exposure.relevantUntil,
              (state.wallTimeFloor ?? exposure.beganAt.wallDate) < exposure.relevantUntil else { return .invalidInput }
        if state.exposures.contains(where: { $0.exposure.id == exposure.id }) { return .duplicate }
        if state[exposure.identity.category].isDisabled { return .categoryDisabled }
        if state.isSuppressed(exposure.identity.key) { return .occurrenceSuppressed }
        if state.hasOpenExposure(exposure.identity.key) { return .exposureAlreadyOpen }
        guard state.hasReceiptCapacity else { return .capacityReached }
        state.exposures.append(SuggestionExposureRecord(exposure: exposure))
        state.observe(exposure.beganAt)
        extendGlobalCooldown(at: exposure.beganAt, in: &state, configuration: configuration)
        return .recorded
    }

    @discardableResult
    public static func respond(_ response: SuggestionResponse, to exposureID: UUID, at time: ProactiveTime,
                               in state: inout SuggestionFeedbackState,
                               configuration: SuggestionPolicyConfiguration = .init()) -> SuggestionFeedbackResult {
        guard let index = state.exposures.firstIndex(where: { $0.exposure.id == exposureID }) else { return .unknownExposure }
        var record = state.exposures[index]
        guard record.response == nil else { return .duplicate }
        guard configuration.isValid, time.isValid, time.runID == record.exposure.beganAt.runID,
              time.elapsed >= record.exposure.beganAt.elapsed else { return .invalidInput }
        let category = record.exposure.identity.category
        var feedback = state[category]
        var quietsCategory = false
        if response == .opened {
            guard !record.wasOpened else { return .duplicate }
            record.wasOpened = true
        } else {
            // Opening is neutral and nonterminal; every other response consumes this receipt.
            record.response = response
            switch response {
            case .accept:
                feedback.positiveWeight += SuggestionPolicyDefaults.acceptWeight
                record.suppressesOccurrence = true
            case .dismiss:
                feedback.negativeWeight += SuggestionPolicyDefaults.dismissWeight
                feedback.distinctDismissals = min(configuration.negativeQuietingCount, feedback.distinctDismissals + 1)
                quietsCategory = feedback.distinctDismissals >= configuration.negativeQuietingCount
                record.suppressesOccurrence = true
            case let .ignore(visibleDuration):
                if !record.wasOpened, visibleDuration >= configuration.minimumVisibleExposure,
                   visibleDuration <= time.elapsed - record.exposure.beganAt.elapsed {
                    feedback.negativeWeight += SuggestionPolicyDefaults.ignoreWeight
                    feedback.distinctIgnores = min(configuration.negativeQuietingCount, feedback.distinctIgnores + 1)
                    quietsCategory = feedback.distinctIgnores >= configuration.negativeQuietingCount
                }
                // Even a briefly visible expiry is consumed, without negative learning.
                record.suppressesOccurrence = true
            case .lessLikeThis:
                feedback.negativeWeight += SuggestionPolicyDefaults.lessLikeThisWeight
                quietsCategory = true
                record.suppressesOccurrence = true
            case .neverSuggestThis:
                feedback.isDisabled = true
                record.suppressesOccurrence = true
            case let .snooze(duration):
                // Invalid or overlong snoozes consume the exposure without creating a stale reschedule.
                let until = time.advanced(by: max(.zero, duration))
                let effectiveWall = max(time.wallDate, state.wallTimeFloor ?? time.wallDate)
                if duration > .zero, until.isValid,
                   effectiveWall.addingTimeInterval(duration.timeInterval) < record.exposure.relevantUntil {
                    record.snoozedUntil = until
                } else {
                    record.suppressesOccurrence = true
                }
            case .withdraw, .opened: break
            }
            if quietsCategory {
                extendCategoryCooldown(at: time, feedback: &feedback, configuration: configuration)
            }
            boundWeights(&feedback)
        }
        state[category] = feedback
        state.exposures[index] = record
        state.observe(time)
        return .applied
    }

    public static func setCategory(_ category: SuggestionCategory, enabled: Bool, in state: inout SuggestionFeedbackState) {
        state[category].isDisabled = !enabled
    }

    public static func resetLearning(in state: inout SuggestionFeedbackState) {
        for category in SuggestionCategory.allCases {
            let disabled = state[category].isDisabled
            state[category] = SuggestionCategoryFeedback()
            state[category].isDisabled = disabled
        }
        // Retain receipts, global timing and the high-water date: reset is not replay authorization.
    }

    private static func boundWeights(_ feedback: inout SuggestionCategoryFeedback) {
        let total = feedback.positiveWeight + feedback.negativeWeight
        if total > SuggestionPolicyDefaults.maximumTotalWeight {
            let scale = SuggestionPolicyDefaults.maximumTotalWeight / total
            feedback.positiveWeight *= scale
            feedback.negativeWeight *= scale
        }
    }

    private static func extendGlobalCooldown(at time: ProactiveTime, in state: inout SuggestionFeedbackState,
                                             configuration: SuggestionPolicyConfiguration) {
        let remaining = max(configuration.globalCooldown, state.globalCooldown?.remaining(at: time) ?? .zero)
        state.globalCooldown = SuggestionCooldown(startedAt: time, duration: remaining)
    }

    private static func extendCategoryCooldown(at time: ProactiveTime, feedback: inout SuggestionCategoryFeedback,
                                               configuration: SuggestionPolicyConfiguration) {
        let remaining = max(configuration.categoryQuietDuration, feedback.cooldown?.remaining(at: time) ?? .zero)
        feedback.cooldown = SuggestionCooldown(startedAt: time, duration: remaining)
    }
}
