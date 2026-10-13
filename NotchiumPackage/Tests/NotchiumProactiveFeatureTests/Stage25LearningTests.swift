import NotchiumCore
import NotchiumProactiveFeature
import XCTest

final class Stage25LearningTests: XCTestCase {
    private func responding(_ response: SuggestionResponse) -> SuggestionFeedbackState {
        var state = SuggestionFeedbackState()
        let exposure = Stage25Fixture.exposure(for: Stage25Fixture.candidate())
        XCTAssertEqual(SuggestionFeedbackReducer.recordExposure(exposure, in: &state), .recorded)
        _ = SuggestionFeedbackReducer.respond(response, to: exposure.id, at: Stage25Fixture.time(wall: 10, elapsed: 10), in: &state)
        return state
    }

    func testSmoothedAffinityAcceptAndDismiss() {
        XCTAssertEqual(SuggestionFeedbackState()[.upcomingMeeting].affinity, 0.5)
        XCTAssertEqual(responding(.accept)[.upcomingMeeting].affinity, 3.0 / 5)
        XCTAssertEqual(responding(.dismiss)[.upcomingMeeting].affinity, 2.0 / 5)
    }

    func testSnoozeIsTimingOnlyAndNeverCrossesExpiry() {
        var state = responding(.snooze(for: .seconds(20)))
        XCTAssertEqual(state[.upcomingMeeting].affinity, 0.5)
        XCTAssertEqual(state.exposures[0].snoozedUntil?.wallDate, Stage25Fixture.date.addingTimeInterval(30))
        let exposure = state.exposures[0].exposure
        XCTAssertEqual(SuggestionFeedbackReducer.respond(.snooze(for: .seconds(30)), to: exposure.id,
                                                         at: Stage25Fixture.time(wall: 11, elapsed: 11), in: &state), .duplicate)
        XCTAssertNil(responding(.snooze(for: .seconds(500))).exposures[0].snoozedUntil)
    }

    func testIgnoreRequiresRecordedGenuineExposureAndEnoughVisibleTime() {
        XCTAssertEqual(responding(.ignore(visibleDuration: .seconds(5)))[.upcomingMeeting].negativeWeight, 2.25)
        XCTAssertEqual(responding(.ignore(visibleDuration: .seconds(1)))[.upcomingMeeting].negativeWeight, 2)
        XCTAssertEqual(responding(.ignore(visibleDuration: .seconds(100)))[.upcomingMeeting].negativeWeight, 2)
        var hidden = SuggestionFeedbackState()
        XCTAssertEqual(SuggestionFeedbackReducer.respond(.ignore(visibleDuration: .seconds(10)), to: Stage25Fixture.id(50),
                                                         at: Stage25Fixture.time(wall: 500, elapsed: 500), in: &hidden), .unknownExposure)
        XCTAssertEqual(hidden[.upcomingMeeting].affinity, 0.5)
    }

    func testOpeningAndNeutralWithdrawalNeverBecomeDislike() {
        for response in [SuggestionResponse.opened, .withdraw(.hiddenExpiry), .withdraw(.sourceInvalidated),
                         .withdraw(.stopped), .withdraw(.policyChanged)] {
            XCTAssertEqual(responding(response)[.upcomingMeeting].affinity, 0.5)
        }
        var state = responding(.opened)
        _ = SuggestionFeedbackReducer.respond(.ignore(visibleDuration: .seconds(10)), to: Stage25Fixture.id(10),
                                               at: Stage25Fixture.time(wall: 20, elapsed: 20), in: &state)
        XCTAssertEqual(state[.upcomingMeeting].affinity, 0.5)
    }

    func testDuplicateTerminalResponseCannotTrainTwiceOrNewRevisionReplayDismissal() {
        var state = responding(.dismiss)
        let before = state
        XCTAssertEqual(SuggestionFeedbackReducer.respond(.accept, to: Stage25Fixture.id(10),
                                                         at: Stage25Fixture.time(wall: 20, elapsed: 20), in: &state), .duplicate)
        XCTAssertEqual(state, before)
        let revision = Stage25Fixture.candidate(revision: 2)
        XCTAssertEqual(SuggestionFeedbackReducer.recordExposure(Stage25Fixture.exposure(for: revision, id: 11), in: &state),
                       .occurrenceSuppressed)
    }

    func testThreeDistinctDismissalsAndIgnoresQuietForSevenDays() {
        for response in [SuggestionResponse.dismiss, .ignore(visibleDuration: .seconds(10))] {
            var state = SuggestionFeedbackState()
            for token in 3..<6 {
                let exposure = Stage25Fixture.exposure(for: Stage25Fixture.candidate(token: token), id: token + 20)
                _ = SuggestionFeedbackReducer.recordExposure(exposure, in: &state)
                _ = SuggestionFeedbackReducer.respond(response, to: exposure.id,
                                                       at: Stage25Fixture.time(wall: 10, elapsed: 10), in: &state)
            }
            XCTAssertEqual(state[.upcomingMeeting].cooldown?.duration, .seconds(7 * 24 * 60 * 60))
        }
    }

    func testLessLikeThisQuietsImmediatelyAndNeverSuggestSurvivesReset() {
        XCTAssertEqual(responding(.lessLikeThis)[.upcomingMeeting].negativeWeight, 5)
        XCTAssertEqual(responding(.lessLikeThis)[.upcomingMeeting].cooldown?.duration, .seconds(604_800))
        var state = responding(.neverSuggestThis)
        SuggestionFeedbackReducer.resetLearning(in: &state)
        XCTAssertTrue(state[.upcomingMeeting].isDisabled)
        XCTAssertEqual(state[.upcomingMeeting].affinity, 0.5)
        SuggestionFeedbackReducer.setCategory(.upcomingMeeting, enabled: true, in: &state)
        XCTAssertFalse(state[.upcomingMeeting].isDisabled)
    }

    func testResetKeepsLiveSuppressionReceiptsAndDoesNotChangeSourceConsent() {
        let consent = SourceConsent(enabledSources: [.calendar])
        var state = responding(.dismiss)
        SuggestionFeedbackReducer.resetLearning(in: &state)
        XCTAssertTrue(state.isSuppressed(Stage25Fixture.candidate().identity.key))
        XCTAssertEqual(state.exposures.count, 1)
        XCTAssertTrue(consent[.calendar])
        XCTAssertFalse(consent[.battery])
    }

    func testSnoozeThenNewExposureCanBeAcceptedAndOldResponseCannotReplay() {
        var state = responding(.snooze(for: .seconds(20)))
        let candidate = Stage25Fixture.candidate()
        let second = Stage25Fixture.exposure(for: candidate, id: 11, at: Stage25Fixture.time(wall: 30, elapsed: 30))
        XCTAssertEqual(SuggestionFeedbackReducer.recordExposure(second, in: &state), .recorded)
        XCTAssertEqual(SuggestionFeedbackReducer.respond(.accept, to: second.id,
                                                         at: Stage25Fixture.time(wall: 31, elapsed: 31), in: &state), .applied)
        let before = state
        XCTAssertEqual(SuggestionFeedbackReducer.respond(.dismiss, to: Stage25Fixture.id(10),
                                                         at: Stage25Fixture.time(wall: 32, elapsed: 32), in: &state), .duplicate)
        XCTAssertEqual(state, before)
        XCTAssertEqual(state[.upcomingMeeting].positiveWeight, 3)
        XCTAssertEqual(state[.upcomingMeeting].negativeWeight, 2)
    }

    func testAcceptAndNeutralWithdrawalCannotRenewExpiredNegativeQuieting() {
        var state = SuggestionFeedbackState()
        var configuration = SuggestionPolicyConfiguration()
        configuration.globalCooldown = .zero
        configuration.categoryQuietDuration = .seconds(30)
        for token in 3..<6 {
            let exposure = Stage25Fixture.exposure(for: Stage25Fixture.candidate(token: token), id: token + 20)
            _ = SuggestionFeedbackReducer.recordExposure(exposure, in: &state, configuration: configuration)
            _ = SuggestionFeedbackReducer.respond(.dismiss, to: exposure.id,
                                                   at: Stage25Fixture.time(wall: 10, elapsed: 10), in: &state,
                                                   configuration: configuration)
        }
        let cooldown = state[.upcomingMeeting].cooldown
        XCTAssertEqual(cooldown?.remaining(at: Stage25Fixture.time(wall: 40, elapsed: 40)), .zero)
        let next = Stage25Fixture.exposure(for: Stage25Fixture.candidate(token: 6), id: 26,
                                           at: Stage25Fixture.time(wall: 40, elapsed: 40))
        _ = SuggestionFeedbackReducer.recordExposure(next, in: &state, configuration: configuration)
        _ = SuggestionFeedbackReducer.respond(.accept, to: next.id, at: Stage25Fixture.time(wall: 41, elapsed: 41),
                                               in: &state, configuration: configuration)
        XCTAssertEqual(state[.upcomingMeeting].cooldown, cooldown)
        let withdrawn = Stage25Fixture.exposure(for: Stage25Fixture.candidate(token: 7), id: 27,
                                                at: Stage25Fixture.time(wall: 42, elapsed: 42))
        _ = SuggestionFeedbackReducer.recordExposure(withdrawn, in: &state, configuration: configuration)
        _ = SuggestionFeedbackReducer.respond(.withdraw(.sourceInvalidated), to: withdrawn.id,
                                               at: Stage25Fixture.time(wall: 43, elapsed: 43), in: &state,
                                               configuration: configuration)
        XCTAssertEqual(state[.upcomingMeeting].cooldown, cooldown)
    }

    func testElapsedExposureCannotCrossRunsAndHiddenWithdrawalIsIdempotent() {
        var state = SuggestionFeedbackState()
        let exposure = Stage25Fixture.exposure(for: Stage25Fixture.candidate())
        _ = SuggestionFeedbackReducer.recordExposure(exposure, in: &state)
        let before = state
        XCTAssertEqual(SuggestionFeedbackReducer.respond(.ignore(visibleDuration: .seconds(10)), to: exposure.id,
                                                         at: Stage25Fixture.time(wall: 10, elapsed: 10, runID: Stage25Fixture.id(99)),
                                                         in: &state), .invalidInput)
        XCTAssertEqual(state, before)
        _ = SuggestionFeedbackReducer.respond(.withdraw(.hiddenExpiry), to: exposure.id,
                                               at: Stage25Fixture.time(wall: 500, elapsed: 500), in: &state)
        XCTAssertEqual(SuggestionFeedbackReducer.respond(.ignore(visibleDuration: .seconds(10)), to: exposure.id,
                                                         at: Stage25Fixture.time(wall: 501, elapsed: 501), in: &state), .duplicate)
        XCTAssertEqual(state[.upcomingMeeting].negativeWeight, 2)
    }

    func testCopiesOfLearningStateAreIndependentAndDisableCannotBeLiftedByAccept() {
        var state = SuggestionFeedbackState()
        let first = Stage25Fixture.exposure(for: Stage25Fixture.candidate())
        let second = Stage25Fixture.exposure(for: Stage25Fixture.candidate(token: 4), id: 11)
        _ = SuggestionFeedbackReducer.recordExposure(first, in: &state)
        _ = SuggestionFeedbackReducer.recordExposure(second, in: &state)
        let copy = state
        _ = SuggestionFeedbackReducer.respond(.neverSuggestThis, to: first.id,
                                               at: Stage25Fixture.time(wall: 10, elapsed: 10), in: &state)
        _ = SuggestionFeedbackReducer.respond(.accept, to: second.id,
                                               at: Stage25Fixture.time(wall: 11, elapsed: 11), in: &state)
        XCTAssertTrue(state[.upcomingMeeting].isDisabled)
        XCTAssertFalse(copy[.upcomingMeeting].isDisabled)
        XCTAssertEqual(copy[.upcomingMeeting].positiveWeight, 2)
    }

    func testWeightsAndReceiptsAreBoundedWithoutSafetyEviction() {
        var state = SuggestionFeedbackState()
        for index in 0..<SuggestionPolicyDefaults.maximumFeedbackReceipts {
            let exposure = Stage25Fixture.exposure(for: Stage25Fixture.candidate(token: 100 + index), id: 300 + index)
            XCTAssertEqual(SuggestionFeedbackReducer.recordExposure(exposure, in: &state), .recorded)
            _ = SuggestionFeedbackReducer.respond(.accept, to: exposure.id,
                                                   at: Stage25Fixture.time(wall: 10, elapsed: 10), in: &state)
        }
        XCTAssertLessThanOrEqual(state[.upcomingMeeting].positiveWeight + state[.upcomingMeeting].negativeWeight,
                                 SuggestionPolicyDefaults.maximumTotalWeight)
        let before = state
        XCTAssertEqual(SuggestionFeedbackReducer.recordExposure(
            Stage25Fixture.exposure(for: Stage25Fixture.candidate(token: 999), id: 999), in: &state), .capacityReached)
        XCTAssertEqual(state, before)
    }
}
