import Foundation
import NotchiumCore
import NotchiumProactiveFeature

enum Stage25Fixture {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static let run = id(1)
    static let source = SuggestionSourceIdentity(source: .calendar, epoch: id(2))

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    static func time(wall: Double = 0, elapsed: Int = 0, runID: UUID = run) -> ProactiveTime {
        ProactiveTime(wallDate: date.addingTimeInterval(wall), elapsed: .seconds(elapsed), runID: runID)
    }

    static func meeting(token: Int = 3, revision: UInt64 = 1, start: Double = 300,
                        end: Double = 3_900, allDay: Bool = false, link: Bool = true) -> MeetingSuggestionInput {
        MeetingSuggestionInput(
            identity: SuggestionIdentity(
                occurrence: SuggestionOccurrence(source: source, token: id(token)),
                category: .upcomingMeeting, revision: revision),
            startsAt: date.addingTimeInterval(start), endsAt: date.addingTimeInterval(end),
            isAllDay: allDay, supportedMeetingLinkAvailable: link)
    }

    static func status(for identity: SuggestionIdentity, availability: FeatureAvailability = .available,
                       cancelled: Bool = false, validUntil: Double = 7_200) -> SuggestionSourceSnapshot {
        SuggestionSourceSnapshot(occurrence: identity.occurrence, revision: identity.revision,
                                 availability: availability, isCancelled: cancelled,
                                 validUntil: date.addingTimeInterval(validUntil))
    }

    static var consent: SourceConsent { SourceConsent(enabledSources: [.calendar]) }

    static func candidate(token: Int = 3, revision: UInt64 = 1, start: Double = 300,
                          end: Double = 3_900, at time: ProactiveTime = time()) -> SuggestionCandidate {
        let input = meeting(token: token, revision: revision, start: start, end: end)
        return MeetingSuggestionRule.candidate(for: input, source: status(for: input.identity),
                                               consent: consent, at: time)!
    }

    static func context(for candidate: SuggestionCandidate, at time: ProactiveTime = time()) -> SuggestionEligibilityContext {
        SuggestionEligibilityContext(time: time, isEnabled: true, consent: consent,
                                     source: status(for: candidate.identity))
    }

    static func exposure(for candidate: SuggestionCandidate, id: Int = 10,
                         at time: ProactiveTime = time()) -> SuggestionExposure {
        SuggestionExposure(id: self.id(id), identity: candidate.identity,
                           relevantUntil: candidate.relevantUntil, beganAt: time)
    }
}
