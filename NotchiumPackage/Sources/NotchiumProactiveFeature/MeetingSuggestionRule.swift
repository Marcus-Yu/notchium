import Foundation
import NotchiumCore

public enum MeetingSuggestionRule {
    public static func candidate(for input: MeetingSuggestionInput, source: SuggestionSourceSnapshot,
                                 consent: SourceConsent, at time: ProactiveTime) -> SuggestionCandidate? {
        guard time.isValid, input.identity.category == .upcomingMeeting,
              input.identity.occurrence.source.source == .calendar,
              !input.isAllDay, input.supportedMeetingLinkAvailable,
              input.startsAt.timeIntervalSince(time.wallDate) <= SuggestionPolicyDefaults.meetingLeadTime,
              time.wallDate < input.endsAt else { return nil }
        let eligibleAt = input.startsAt.addingTimeInterval(-SuggestionPolicyDefaults.meetingLeadTime)
        let candidate = SuggestionCandidate(
            identity: input.identity, evidence: .upcomingMeeting(startsAt: input.startsAt, endsAt: input.endsAt),
            structuredEvidence: 1, urgency: 1, createdAt: time.wallDate, eligibleAt: eligibleAt,
            relevantUntil: min(input.endsAt, input.startsAt.addingTimeInterval(SuggestionPolicyDefaults.meetingGraceTime)),
            actions: [.joinCurrentMeeting(input.identity.occurrence)], importance: .timeSensitive)
        guard SuggestionCandidateValidity.rejection(for: candidate, source: source, consent: consent,
                                                     wallDate: time.wallDate) == nil else { return nil }
        return candidate
    }
}
