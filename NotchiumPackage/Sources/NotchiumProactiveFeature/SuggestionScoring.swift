import NotchiumCore

public enum SuggestionScoring {
    public static func score(evidence: Double, urgency: Double, affinity: Double, timingPenalty: Double = 0) -> Double {
        guard evidence.isFinite, urgency.isFinite, affinity.isFinite, timingPenalty.isFinite else { return 0 }
        let value = SuggestionPolicyDefaults.evidenceWeight * evidence
            + SuggestionPolicyDefaults.urgencyWeight * urgency
            + SuggestionPolicyDefaults.affinityWeight * affinity - max(0, timingPenalty)
        return min(1, max(0, value))
    }

    public static func meetsThreshold(_ score: Double) -> Bool {
        score.isFinite && score >= SuggestionPolicyDefaults.eligibilityThreshold
    }
}
