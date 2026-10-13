import Foundation
import NotchiumCore

public enum SuggestionCandidateValidity {
    public static func rejection(for candidate: SuggestionCandidate, source: SuggestionSourceSnapshot,
                                 consent: SourceConsent, wallDate: Date,
                                 supportingSources: [SuggestionSource: SuggestionSourceSnapshot] = [:]) -> SuggestionDiscardReason? {
        guard isWellFormed(candidate), wallDate.timeIntervalSinceReferenceDate.isFinite,
              source.validUntil.timeIntervalSinceReferenceDate.isFinite else { return .invalidCandidate }
        guard candidate.evidence.requiredSources.allSatisfy({ consent[$0] }) else { return .sourceNotConsented }
        guard source.availability == .available else { return .sourceUnavailable }
        guard source.occurrence == candidate.identity.occurrence else { return .sourceIdentityChanged }
        guard source.revision == candidate.identity.revision else { return .staleRevision }
        guard !source.isCancelled else { return .cancelled }
        guard wallDate < candidate.relevantUntil else { return .expired }
        guard wallDate < source.validUntil else { return .staleSource }
        for requiredSource in candidate.evidence.requiredSources where requiredSource != source.occurrence.source.source {
            guard let supporting = supportingSources[requiredSource], supporting.availability == .available,
                  let expected = candidate.supportingRevisions[requiredSource] else { return .sourceUnavailable }
            guard supporting.occurrence.source == expected.identity else { return .sourceIdentityChanged }
            guard supporting.revision == expected.revision else { return .staleRevision }
            guard !supporting.isCancelled else { return .cancelled }
            guard supporting.validUntil.timeIntervalSinceReferenceDate.isFinite,
                  wallDate < supporting.validUntil else { return .staleSource }
        }
        return nil
    }

    static func isWellFormed(_ candidate: SuggestionCandidate) -> Bool {
        guard [candidate.createdAt, candidate.eligibleAt, candidate.relevantUntil]
            .allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
              candidate.createdAt < candidate.relevantUntil,
              candidate.eligibleAt < candidate.relevantUntil,
              candidate.structuredEvidence.isFinite, (0...1).contains(candidate.structuredEvidence),
              candidate.urgency.isFinite, (0...1).contains(candidate.urgency),
              !candidate.actions.isEmpty, candidate.actions.count <= SuggestionPolicyDefaults.maximumActions else { return false }
        let source = candidate.identity.occurrence.source.source
        let secondarySources = candidate.evidence.requiredSources.subtracting([source])
        guard Set(candidate.supportingRevisions.keys) == secondarySources,
              candidate.supportingRevisions.allSatisfy({ $0.key == $0.value.identity.source }) else { return false }
        switch (candidate.identity.category, candidate.evidence) {
        case let (.upcomingMeeting, .upcomingMeeting(start, end)):
            guard source == .calendar, start.timeIntervalSinceReferenceDate.isFinite,
                  end.timeIntervalSinceReferenceDate.isFinite, start < end,
                  candidate.eligibleAt >= start.addingTimeInterval(-SuggestionPolicyDefaults.meetingLeadTime),
                  candidate.relevantUntil <= min(end, start.addingTimeInterval(SuggestionPolicyDefaults.meetingGraceTime)) else { return false }
        case let (.workBattery, .workBattery(percent, work)):
            guard source == .battery, (0...100).contains(percent) else { return false }
            if case let .pomodoro(remaining) = work, remaining <= .zero { return false }
        case let (.completedTransfer, .completedTransfer(bytes)):
            guard source == .transfers, bytes >= 0 else { return false }
        case let (.returnBrief, .returnBrief(count, sources)):
            guard source == .lifecycle, (1...5).contains(count), !sources.isEmpty else { return false }
        default: return false
        }
        return candidate.actions.allSatisfy { action in
            switch action {
            case let .joinCurrentMeeting(occurrence):
                return candidate.identity.category == .upcomingMeeting && occurrence == candidate.identity.occurrence
            case let .revealObservedTransfer(occurrence), let .addObservedTransferToShelf(occurrence):
                return candidate.identity.category == .completedTransfer && occurrence == candidate.identity.occurrence
            case let .startPomodoro(duration): return duration > .zero
            case .showMirror, .ensureCaffeine, .runPinnedShortcut: return true
            }
        }
    }
}
