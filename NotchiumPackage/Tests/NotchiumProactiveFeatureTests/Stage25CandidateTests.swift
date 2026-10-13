import Foundation
import NotchiumCore
import NotchiumProactiveFeature
import XCTest

final class Stage25CandidateTests: XCTestCase {
    func testSourcesDefaultOffAndEnableIndependently() {
        var consent = SourceConsent()
        for source in SuggestionSource.allCases { XCTAssertFalse(consent[source]) }
        consent[.calendar] = true
        for source in SuggestionSource.allCases { XCTAssertEqual(consent[source], source == .calendar) }
    }

    func testFreshMeetingInFiveMinutesHasOnlyOpaqueEvidenceAndAction() throws {
        let candidate = Stage25Fixture.candidate()
        XCTAssertEqual(candidate.evidence, .upcomingMeeting(startsAt: Stage25Fixture.date.addingTimeInterval(300),
                                                            endsAt: Stage25Fixture.date.addingTimeInterval(3_900)))
        XCTAssertEqual(candidate.actions, [.joinCurrentMeeting(candidate.identity.occurrence)])
        XCTAssertEqual(candidate.relevantUntil, Stage25Fixture.date.addingTimeInterval(420))
        XCTAssertEqual(candidate.eligibleAt, Stage25Fixture.date)
    }

    func testNoCandidateWithoutConsentOrValidMeetingFacts() {
        let valid = Stage25Fixture.meeting()
        XCTAssertNil(MeetingSuggestionRule.candidate(for: valid, source: Stage25Fixture.status(for: valid.identity),
                                                      consent: SourceConsent(), at: Stage25Fixture.time()))
        for input in [Stage25Fixture.meeting(allDay: true), Stage25Fixture.meeting(link: false),
                      Stage25Fixture.meeting(start: 301), Stage25Fixture.meeting(start: -300, end: -1),
                      Stage25Fixture.meeting(start: 300, end: 200)] {
            XCTAssertNil(MeetingSuggestionRule.candidate(for: input, source: Stage25Fixture.status(for: input.identity),
                                                          consent: Stage25Fixture.consent, at: Stage25Fixture.time()))
        }
        for status in [Stage25Fixture.status(for: valid.identity, cancelled: true),
                       Stage25Fixture.status(for: valid.identity, validUntil: 0),
                       Stage25Fixture.status(for: valid.identity, availability: .unavailable(.permissionDenied)),
                       Stage25Fixture.status(for: Stage25Fixture.meeting(revision: 2).identity)] {
            XCTAssertNil(MeetingSuggestionRule.candidate(for: valid, source: status,
                                                          consent: Stage25Fixture.consent, at: Stage25Fixture.time()))
        }
    }

    func testRevisionsCoalesceWithoutExtendingRelevance() {
        var pending = SuggestionCandidateSet()
        let original = Stage25Fixture.candidate()
        let updated = Stage25Fixture.candidate(revision: 2, end: 5_000)
        XCTAssertEqual(pending.upsert(original), .inserted)
        XCTAssertEqual(pending.upsert(updated), .updated)
        XCTAssertEqual(pending.candidates.count, 1)
        XCTAssertEqual(original.identity.key, updated.identity.key)
        XCTAssertEqual(pending.candidates[0].identity.revision, 2)
        XCTAssertEqual(pending.candidates[0].relevantUntil, original.relevantUntil)
        XCTAssertEqual(pending.upsert(original), .rejectedStaleRevision)
        XCTAssertEqual(pending.upsert(Stage25Fixture.candidate(token: 4)), .inserted)
    }

    func testRevisionCannotExtendShortOriginalDeadline() {
        var pending = SuggestionCandidateSet()
        let original = Stage25Fixture.candidate(end: 310)
        _ = pending.upsert(original)
        _ = pending.upsert(Stage25Fixture.candidate(revision: 2, end: 4_000))
        XCTAssertEqual(pending.candidates[0].relevantUntil, original.relevantUntil)
    }

    func testRepeatedGenerationIsUnchangedEvenWithLaterCreationTime() {
        var pending = SuggestionCandidateSet()
        _ = pending.upsert(Stage25Fixture.candidate())
        XCTAssertEqual(pending.upsert(Stage25Fixture.candidate(at: Stage25Fixture.time(wall: 10, elapsed: 10))), .unchanged)
        XCTAssertEqual(pending.candidates[0].createdAt, Stage25Fixture.date)
    }

    func testPendingCapacityRejectsWithoutEvictingAndAllowsRevisionUpdate() {
        var pending = SuggestionCandidateSet()
        for token in 3..<11 { XCTAssertEqual(pending.upsert(Stage25Fixture.candidate(token: token)), .inserted) }
        let before = pending.candidates
        XCTAssertEqual(pending.upsert(Stage25Fixture.candidate(token: 11)), .capacityReached)
        XCTAssertEqual(pending.candidates, before)
        XCTAssertEqual(pending.upsert(Stage25Fixture.candidate(revision: 2)), .updated)
        XCTAssertEqual(pending.candidates.count, 8)
    }

    func testScoringWeightsClampingAndThreshold() {
        XCTAssertEqual(SuggestionScoring.score(evidence: 1, urgency: 1, affinity: 0.5), 0.875, accuracy: 0.00001)
        XCTAssertEqual(SuggestionScoring.score(evidence: 0.8, urgency: 0.7, affinity: 0.6, timingPenalty: 0.1),
                       0.63, accuracy: 0.00001)
        XCTAssertEqual(SuggestionScoring.score(evidence: 100, urgency: 100, affinity: 100), 1)
        XCTAssertEqual(SuggestionScoring.score(evidence: -100, urgency: -100, affinity: -100), 0)
        XCTAssertEqual(SuggestionScoring.score(evidence: 1, urgency: 1, affinity: 1, timingPenalty: 100), 0)
        XCTAssertEqual(SuggestionScoring.score(evidence: .nan, urgency: 1, affinity: 1), 0)
        XCTAssertFalse(SuggestionScoring.meetsThreshold(0.749999))
        XCTAssertTrue(SuggestionScoring.meetsThreshold(0.75))
        XCTAssertGreaterThan(SuggestionScoring.score(evidence: 1, urgency: 1, affinity: 0.5),
                             SuggestionScoring.score(evidence: 1, urgency: 0, affinity: 0.5))
    }
}
