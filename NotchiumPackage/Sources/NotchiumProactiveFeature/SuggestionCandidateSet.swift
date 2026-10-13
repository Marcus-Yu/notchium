import Foundation
import NotchiumCore

public enum SuggestionCandidateUpdate: Equatable, Sendable {
    case inserted, updated, unchanged, rejectedStaleRevision, conflictingRevision, invalidCandidate, capacityReached
}

/// Small in-memory value collection, not a scheduler. Upserts never evict an occurrence
/// or extend its absolute relevance. Removal is explicit and belongs to the future owner.
public struct SuggestionCandidateSet: Equatable, Sendable {
    public private(set) var candidates: [SuggestionCandidate] = []
    public init() {}

    @discardableResult
    public mutating func upsert(_ candidate: SuggestionCandidate) -> SuggestionCandidateUpdate {
        guard SuggestionCandidateValidity.isWellFormed(candidate) else { return .invalidCandidate }
        if let index = candidates.firstIndex(where: { $0.identity.key == candidate.identity.key }) {
            let old = candidates[index]
            guard candidate.identity.revision >= old.identity.revision else { return .rejectedStaleRevision }
            let updated = SuggestionCandidate(
                identity: candidate.identity, evidence: candidate.evidence,
                structuredEvidence: candidate.structuredEvidence, urgency: candidate.urgency,
                createdAt: min(old.createdAt, candidate.createdAt), eligibleAt: candidate.eligibleAt,
                relevantUntil: min(old.relevantUntil, candidate.relevantUntil),
                actions: candidate.actions, importance: candidate.importance, supportingRevisions: candidate.supportingRevisions)
            guard SuggestionCandidateValidity.isWellFormed(updated) else { return .invalidCandidate }
            if candidate.identity.revision == old.identity.revision {
                return updated == old ? .unchanged : .conflictingRevision
            }
            candidates[index] = updated
            return .updated
        }
        guard candidates.count < SuggestionPolicyDefaults.maximumPendingCandidates else { return .capacityReached }
        candidates.append(candidate)
        return .inserted
    }

    public mutating func remove(_ key: SuggestionKey) {
        candidates.removeAll { $0.identity.key == key }
    }
}
