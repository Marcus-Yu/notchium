import Foundation
import NotchiumCore
import NotchiumProactiveFeature
import XCTest

final class Stage25EligibilityTests: XCTestCase {
    private func decision(_ context: SuggestionEligibilityContext,
                          state: SuggestionFeedbackState = SuggestionFeedbackState()) -> SuggestionEligibilityDecision {
        SuggestionInterruptionPolicy.evaluate(Stage25Fixture.candidate(), in: context, feedback: state)
    }

    func testNormalContextPassesAndUnknownFocusDoesNotPretendToBeOff() {
        let candidate = Stage25Fixture.candidate()
        var context = Stage25Fixture.context(for: candidate)
        XCTAssertEqual(context.focus, .unknown)
        XCTAssertEqual(decision(context), .eligible(score: 0.875))
        context.focus = .on
        XCTAssertEqual(decision(context), .deferred(.focus, until: nil))
        context.quietDuringKnownFocus = false
        XCTAssertEqual(decision(context), .eligible(score: 0.875))
    }

    func testHardProhibitionsCannotBeOverriddenByScore() {
        let candidate = Stage25Fixture.candidate()
        var context = Stage25Fixture.context(for: candidate)
        context.isEnabled = false
        XCTAssertEqual(decision(context), .discard(.globallyDisabled))
        context.isEnabled = true
        context.consent[.calendar] = false
        XCTAssertEqual(decision(context), .discard(.sourceNotConsented))
        context.consent[.calendar] = true
        var feedback = SuggestionFeedbackState()
        SuggestionFeedbackReducer.setCategory(.upcomingMeeting, enabled: false, in: &feedback)
        XCTAssertEqual(decision(context, state: feedback), .discard(.categoryDisabled))
    }

    func testCancelledStaleUnavailableAndWrongEpochReject() {
        let candidate = Stage25Fixture.candidate()
        var context = Stage25Fixture.context(for: candidate)
        context.source = Stage25Fixture.status(for: candidate.identity, cancelled: true)
        XCTAssertEqual(decision(context), .discard(.cancelled))
        context.source = Stage25Fixture.status(for: Stage25Fixture.meeting(revision: 2).identity)
        XCTAssertEqual(decision(context), .discard(.staleRevision))
        for reason in [AvailabilityReason.permissionDenied, .permissionRevoked, .unsupportedDistribution, .unsupportedHardware] {
            context.source = Stage25Fixture.status(for: candidate.identity, availability: .unavailable(reason))
            XCTAssertEqual(decision(context), .discard(.sourceUnavailable))
        }
        context.source = Stage25Fixture.status(for: candidate.identity, validUntil: 0)
        XCTAssertEqual(decision(context), .discard(.staleSource))
        let wrong = SuggestionIdentity(occurrence: SuggestionOccurrence(
            source: SuggestionSourceIdentity(source: .calendar, epoch: Stage25Fixture.id(100)), token: Stage25Fixture.id(3)),
                                       category: .upcomingMeeting, revision: 1)
        context.source = Stage25Fixture.status(for: wrong)
        XCTAssertEqual(decision(context), .discard(.sourceIdentityChanged))
    }

    func testEveryProtectedPresentationConditionBlocksEvenTimeSensitiveSuggestions() {
        let candidate = Stage25Fixture.candidate()
        for restriction in [SuggestionPresentationRestrictions.criticalActivity, .protectedTransient, .activeTransfer,
                            .protectedTimer, .sleeping, .fullscreen, .presenting, .expanded, .manualInteraction,
                            .auxiliaryInteraction, .dragging, .mirror] {
            var context = Stage25Fixture.context(for: candidate)
            context.restrictions = restriction
            XCTAssertEqual(decision(context), .deferred(.protectedPresentation, until: nil))
        }
    }

    func testDailyCapAndPendingCapacity() {
        let candidate = Stage25Fixture.candidate()
        var context = Stage25Fixture.context(for: candidate)
        context.dailyExposureCount = 2
        XCTAssertEqual(decision(context), .eligible(score: 0.875))
        context.dailyExposureCount = 3
        XCTAssertEqual(decision(context), .deferred(.dailyCap, until: nil))
        context.dailyExposureCount = 0
        context.otherPendingCandidateCount = 8
        XCTAssertEqual(decision(context), .deferred(.pendingCapacity, until: nil))
    }

    func testPolicyThresholdBoundaryAndTimingPenalty() {
        let candidate = Stage25Fixture.candidate()
        var context = Stage25Fixture.context(for: candidate)
        context.timingPenalty = 0.125
        XCTAssertEqual(decision(context), .eligible(score: 0.75))
        context.timingPenalty = 0.125001
        XCTAssertEqual(decision(context), .discard(.belowThreshold))
        context.timingPenalty = -.infinity
        XCTAssertEqual(decision(context), .discard(.invalidInput))
    }

    func testRequestedSnoozeReturnHasOneBoundaryAndStillRespectsProtectedActivities() {
        let candidate = Stage25Fixture.candidate()
        var feedback = SuggestionFeedbackState()
        let exposure = Stage25Fixture.exposure(for: candidate)
        _ = SuggestionFeedbackReducer.recordExposure(exposure, in: &feedback)
        _ = SuggestionFeedbackReducer.respond(.snooze(for: .seconds(20)), to: exposure.id,
                                               at: Stage25Fixture.time(wall: 10, elapsed: 10), in: &feedback)
        var context = Stage25Fixture.context(for: candidate, at: Stage25Fixture.time(wall: 29, elapsed: 29))
        context.dailyExposureCount = 3
        XCTAssertEqual(decision(context, state: feedback),
                       .deferred(.cooldown, until: Stage25Fixture.time(wall: 30, elapsed: 30)))
        context.time = Stage25Fixture.time(wall: 30, elapsed: 30)
        XCTAssertEqual(decision(context, state: feedback), .eligible(score: 0.875))
        context.restrictions = .criticalActivity
        XCTAssertEqual(decision(context, state: feedback), .deferred(.protectedPresentation, until: nil))
    }

    func testGlobalCooldownExpiresAtExactElapsedBoundaryForNewOccurrence() {
        var feedback = SuggestionFeedbackState()
        _ = SuggestionFeedbackReducer.recordExposure(Stage25Fixture.exposure(for: Stage25Fixture.candidate()), in: &feedback)
        let time = Stage25Fixture.time(wall: 1_800, elapsed: 1_799)
        let next = Stage25Fixture.candidate(token: 4, start: 2_100, end: 5_700, at: time)
        var context = Stage25Fixture.context(for: next, at: time)
        XCTAssertEqual(SuggestionInterruptionPolicy.evaluate(next, in: context, feedback: feedback),
                       .deferred(.cooldown, until: time.advanced(by: .seconds(1))))
        context.time = Stage25Fixture.time(wall: 1_801, elapsed: 1_800)
        XCTAssertEqual(SuggestionInterruptionPolicy.evaluate(next, in: context, feedback: feedback), .eligible(score: 0.875))
    }

    func testInvalidElapsedAndWallValuesFailClosed() {
        let candidate = Stage25Fixture.candidate()
        var context = Stage25Fixture.context(for: candidate)
        context.time = ProactiveTime(wallDate: Stage25Fixture.date, elapsed: .seconds(-1), runID: Stage25Fixture.run)
        XCTAssertEqual(decision(context), .discard(.invalidInput))
        context.time = ProactiveTime(wallDate: Date(timeIntervalSince1970: .nan), elapsed: .zero, runID: Stage25Fixture.run)
        XCTAssertEqual(decision(context), .discard(.invalidInput))
    }

    func testAbsoluteExpiryBoundaryAndWallFloorPreventRollbackReplay() {
        let candidate = Stage25Fixture.candidate()
        var context = Stage25Fixture.context(for: candidate, at: Stage25Fixture.time(wall: 419, elapsed: 419))
        XCTAssertEqual(decision(context), .eligible(score: 0.875))
        context.time = Stage25Fixture.time(wall: 420, elapsed: 420)
        XCTAssertEqual(decision(context), .discard(.expired))
        context.time = Stage25Fixture.time(wall: -100, elapsed: 421)
        context.wallTimeFloor = Stage25Fixture.date.addingTimeInterval(420)
        XCTAssertEqual(decision(context), .discard(.expired))
    }

    func testCooldownUsesElapsedTimeAcrossWallAdjustmentsAndExactBoundary() {
        // Already inside the absolute lead-time window at either wall date.
        let candidate = Stage25Fixture.candidate(start: 200)
        var context = Stage25Fixture.context(for: candidate)
        context.manualCooldown = SuggestionCooldown(startedAt: Stage25Fixture.time(), duration: .seconds(30))
        for wall in [-50.0, 100.0] {
            context.time = Stage25Fixture.time(wall: wall, elapsed: 29)
            guard case let .deferred(.cooldown, until) = SuggestionInterruptionPolicy.evaluate(
                candidate, in: context, feedback: SuggestionFeedbackState()) else { return XCTFail("Expected cooldown") }
            XCTAssertEqual(until?.elapsed, .seconds(30))
        }
        context.time = Stage25Fixture.time(wall: 10, elapsed: 30)
        XCTAssertEqual(SuggestionInterruptionPolicy.evaluate(candidate, in: context, feedback: SuggestionFeedbackState()),
                       .eligible(score: 0.875))
    }

    func testSecondaryWorkEvidenceNeedsIndependentConsentAndFreshAvailability() {
        let source = SuggestionSourceIdentity(source: .battery, epoch: Stage25Fixture.id(2))
        let identity = SuggestionIdentity(occurrence: SuggestionOccurrence(source: source, token: Stage25Fixture.id(3)),
                                          category: .workBattery, revision: 1)
        let caffeineSource = SuggestionSourceIdentity(source: .caffeine, epoch: Stage25Fixture.id(4))
        let candidate = SuggestionCandidate(identity: identity, evidence: .workBattery(percent: 10, work: .caffeine),
                                            structuredEvidence: 1, urgency: 1, createdAt: Stage25Fixture.date,
                                            eligibleAt: Stage25Fixture.date, relevantUntil: Stage25Fixture.date.addingTimeInterval(100),
                                            actions: [.showMirror], importance: .routine,
                                            supportingRevisions: [.caffeine: SuggestionSourceRevision(identity: caffeineSource, revision: 1)])
        var context = Stage25Fixture.context(for: candidate)
        context.consent = SourceConsent(enabledSources: [.battery])
        func evaluate() -> SuggestionEligibilityDecision {
            SuggestionInterruptionPolicy.evaluate(candidate, in: context, feedback: SuggestionFeedbackState())
        }
        XCTAssertEqual(evaluate(), .discard(.sourceNotConsented))
        context.consent[.caffeine] = true
        XCTAssertEqual(evaluate(), .discard(.sourceUnavailable))
        let supportingIdentity = SuggestionIdentity(occurrence: SuggestionOccurrence(
            source: caffeineSource, token: Stage25Fixture.id(5)),
                                                     category: .workBattery, revision: 1)
        context.supportingSources[.caffeine] = Stage25Fixture.status(for: supportingIdentity)
        XCTAssertEqual(evaluate(), .eligible(score: 0.875))
        let newerSupportingIdentity = SuggestionIdentity(occurrence: supportingIdentity.occurrence,
                                                         category: .workBattery, revision: 2)
        context.supportingSources[.caffeine] = Stage25Fixture.status(for: newerSupportingIdentity)
        XCTAssertEqual(evaluate(), .discard(.staleRevision))
        context.supportingSources[.caffeine] = Stage25Fixture.status(for: supportingIdentity, validUntil: 0)
        XCTAssertEqual(evaluate(), .discard(.staleSource))
    }

    func testCooldownUsesWallBoundInDifferentRun() {
        let cooldown = SuggestionCooldown(startedAt: Stage25Fixture.time(), duration: .seconds(30))
        XCTAssertEqual(cooldown.remaining(at: Stage25Fixture.time(wall: 29, elapsed: 500, runID: Stage25Fixture.id(9))), .seconds(1))
        XCTAssertEqual(cooldown.remaining(at: Stage25Fixture.time(wall: 30, runID: Stage25Fixture.id(9))), .zero)
        XCTAssertEqual(cooldown.remaining(at: Stage25Fixture.time(wall: 100, elapsed: 1)), .seconds(29))
    }

    func testOverlappingCooldownsUseLatestBoundaryAndCannotOutliveExpiry() {
        let candidate = Stage25Fixture.candidate()
        var context = Stage25Fixture.context(for: candidate)
        var feedback = SuggestionFeedbackState()
        let other = Stage25Fixture.exposure(for: Stage25Fixture.candidate(token: 4), id: 20)
        _ = SuggestionFeedbackReducer.recordExposure(other, in: &feedback)
        context.manualCooldown = SuggestionCooldown(startedAt: Stage25Fixture.time(), duration: .seconds(30))
        XCTAssertEqual(decision(context, state: feedback), .discard(.noEligibleWindow))
        context.manualCooldown = SuggestionCooldown(startedAt: Stage25Fixture.time(), duration: .seconds(500))
        XCTAssertEqual(decision(context), .discard(.noEligibleWindow))
    }

    func testDismissalSurvivesNewContentRevision() {
        var feedback = SuggestionFeedbackState()
        let candidate = Stage25Fixture.candidate()
        let exposure = Stage25Fixture.exposure(for: candidate)
        _ = SuggestionFeedbackReducer.recordExposure(exposure, in: &feedback)
        _ = SuggestionFeedbackReducer.respond(.dismiss, to: exposure.id,
                                               at: Stage25Fixture.time(wall: 10, elapsed: 10), in: &feedback)
        let revised = Stage25Fixture.candidate(revision: 2)
        XCTAssertEqual(SuggestionInterruptionPolicy.evaluate(revised, in: Stage25Fixture.context(for: revised), feedback: feedback),
                       .discard(.occurrenceSuppressed))
    }
}
