import Foundation
import NotchiumCore
import NotchiumServices
@testable import NotchiumTeleprompterFeature
import XCTest

@MainActor
final class TeleprompterReadingSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let script = "Welcome everyone to our quarterly report. Customer retention increased substantially across every region."

    func testVoiceFollowUsesWordsAndHoldsImmediatelyOffScript() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.wordIndex == 4 }
        XCTAssertEqual(session.state, .reading)
        await speech.emit(.transcript(text: "sorry my coffee spilled everywhere", audioStart: 2, audioEnd: 4, isFinal: false))
        await waitUntil { session.state == .waiting }
        XCTAssertEqual(session.wordIndex, 4)
        await speech.emit(.audioLevel(0.5))
        session.advance(at: now.addingTimeInterval(0.1))
        XCTAssertEqual(session.state, .waiting, "Unrelated microphone activity must not restore scrolling")
        session.stop()
    }

    func testNearbyScriptPhraseResumesAfterDigression() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: true))
        await waitUntil { session.wordIndex == 4 }
        await speech.emit(.transcript(text: "sorry my coffee spilled everywhere", audioStart: 2, audioEnd: 3, isFinal: true))
        await waitUntil { session.state == .waiting }
        await speech.emit(.transcript(text: "our quarterly report", audioStart: 3, audioEnd: 4, isFinal: true))
        await waitUntil { session.wordIndex == 6 }
        XCTAssertEqual(session.state, .reading)
        session.stop()
    }

    func testRevisedAudioRangeReplacesEarlierWordsWithoutRollingCursorBack() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.wordIndex == 4 }
        await speech.emit(.transcript(text: "welcome everybody outside our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.state == .waiting }
        XCTAssertEqual(session.wordIndex, 4)
        await speech.emit(.transcript(text: "welcome everyone to our quarterly report", audioStart: 0, audioEnd: 3, isFinal: true))
        await waitUntil { session.wordIndex == 6 }
        session.stop()
    }

    func testEarlierTranscriptRevisionDoesNotReplaceLatestOffScriptTail() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.wordIndex == 4 }
        await speech.emit(.transcript(text: "please wait while I answer the door", audioStart: 2, audioEnd: 4, isFinal: false))
        await waitUntil { session.state == .waiting }
        await speech.emit(.transcript(text: "welcome everyone to our quarterly report", audioStart: 0, audioEnd: 2, isFinal: true))
        await drainTasks()
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(session.wordIndex, 4)
        session.stop()
    }

    func testSilenceHoldsWithInjectedClock() async {
        let (session, speech, clock) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.wordIndex == 4 }
        await clock.advance(by: .seconds(1))
        session.advance(at: await clock.now())
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(session.wordIndex, 4)
        session.stop()
    }

    func testActualDeclarationSubwordsPreserveRecentReadingConfidence() async {
        let source = "In Congress, July 4, 1776. The unanimous Declaration of the thirteen united States of America."
        let (session, speech, clock) = await voiceSession(text: source)
        let prefix = "In Congress, July 4th, 1776, the"
        await speech.emit(.transcript(text: prefix, audioStart: 0, audioEnd: 15.219, isFinal: false))
        await waitUntil { session.wordIndex == 6 }
        for fragment in ["un", "unan", "unanim"] {
            await clock.advance(by: .milliseconds(100))
            await speech.emit(.audioLevel(0.01))
            await speech.emit(.transcript(text: prefix + " " + fragment, audioStart: 0, audioEnd: 15.219, isFinal: false))
            await drainTasks()
            XCTAssertEqual(session.state, .reading, "Apple's unfinished '\(fragment)' must not flicker into off-script state")
            XCTAssertEqual(session.wordIndex, 6, "An unfinished word must not be marked read")
        }
        await speech.emit(.transcript(text: prefix + " unanimous Dec", audioStart: 0, audioEnd: 15.219, isFinal: false))
        await waitUntil { session.wordIndex == 7 }
        XCTAssertEqual(session.state, .reading)
        session.stop()
    }

    func testProvisionalFragmentCannotRenewTheVoiceGateWithoutCompletedWords() async {
        let (session, speech, clock) = await voiceSession(mode: .voiceGated)
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.state == .reading }
        for fragment in ["q", "qu", "qua", "quar", "quart", "quarte", "quarter", "quarterl"] {
            await clock.advance(by: .milliseconds(250))
            await speech.emit(.audioLevel(0.1))
            await speech.emit(.transcript(text: "welcome everyone to our " + fragment,
                audioStart: 0, audioEnd: 2, isFinal: false))
            await drainTasks()
            session.advance(at: await clock.now())
        }
        XCTAssertEqual(session.state, .waiting, "Partial-word churn cannot extend a previous confirmed match indefinitely")
        let held = session.position
        await clock.advance(by: .seconds(1))
        await speech.emit(.audioLevel(0.1))
        await drainTasks()
        session.advance(at: await clock.now())
        XCTAssertEqual(session.position, held)
        session.stop()
    }

    func testFinalUnfinishedWordDoesNotReceiveProvisionalGrace() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.state == .reading }
        await speech.emit(.transcript(text: "welcome everyone to our qu", audioStart: 0, audioEnd: 3, isFinal: true))
        await waitUntil { session.state == .waiting }
        XCTAssertEqual(session.wordIndex, 4)
        session.stop()
    }

    func testOlderFinalKeepsLatestPartialProvisionalWithoutRenewingGrace() async {
        let (session, speech, clock) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.wordIndex == 4 }
        await clock.advance(by: .milliseconds(200))
        await speech.emit(.transcript(text: "qu", audioStart: 2, audioEnd: 3, isFinal: false))
        await drainTasks()
        await speech.emit(.transcript(text: "WELCOME EVERYONE TO OUR.", audioStart: 0, audioEnd: 2, isFinal: true))
        await drainTasks()
        XCTAssertEqual(session.state, .reading, "An older final does not finalize a newer unfinished word")
        XCTAssertEqual(session.wordIndex, 4)
        await clock.advance(by: .seconds(2))
        await speech.emit(.audioLevel(0.1))
        await drainTasks()
        session.advance(at: await clock.now())
        XCTAssertEqual(session.state, .waiting, "Revising old audio must not renew the last progress deadline")
        session.stop()
    }

    func testUnchangedProvisionalTextIsReevaluatedWhenFinalized() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.wordIndex == 4 }
        let partial = "welcome everyone to our qu"
        await speech.emit(.transcript(text: partial, audioStart: 0, audioEnd: 3, isFinal: false))
        await drainTasks()
        XCTAssertEqual(session.state, .reading)
        await speech.emit(.transcript(text: partial, audioStart: 0, audioEnd: 3, isFinal: true))
        await waitUntil { session.state == .waiting }
        XCTAssertEqual(session.wordIndex, 4)
        session.stop()
    }

    func testFreshPartialCannotRestartConsumedWordsAfterOffScriptSpeech() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.wordIndex == 4 }
        await speech.emit(.transcript(text: "sorry my coffee spilled everywhere", audioStart: 2, audioEnd: 3, isFinal: true))
        await waitUntil { session.state == .waiting }
        await speech.emit(.transcript(text: "welcome everyone to our qu", audioStart: 3, audioEnd: 4, isFinal: false))
        await drainTasks()
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(session.wordIndex, 4)
        session.stop()
    }

    func testCompletedPrefixWordsCanResumeBeforeTheNextWordFinishes() async {
        let (session, speech, clock) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.wordIndex == 4 }
        await clock.advance(by: .seconds(1))
        session.advance(at: await clock.now())
        XCTAssertEqual(session.state, .waiting)
        await speech.emit(.transcript(text: "welcome everyone to our quarterly rep", audioStart: 0, audioEnd: 3, isFinal: false))
        await waitUntil { session.wordIndex == 5 }
        XCTAssertEqual(session.state, .reading)
        session.stop()
    }

    func testIdenticalVolatileEvidenceDoesNotKeepScrollingAlive() async {
        let (session, speech, clock) = await voiceSession()
        let event = TeleprompterSpeechEvent.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false)
        await speech.emit(event)
        await waitUntil { session.wordIndex == 4 }
        await clock.advance(by: .seconds(1))
        await speech.emit(event)
        await drainTasks()
        session.advance(at: await clock.now())
        XCTAssertEqual(session.state, .waiting)
        session.stop()
    }

    func testFixedSpeedFirstTickAdvancesWithoutStartingMicrophone() async {
        let speech = MockTeleprompterSpeechService()
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let session = TeleprompterReadingSession(speech: speech, clock: clock)
        session.prepare(text: script)
        session.mode = .fixedSpeed
        session.wordsPerMinute = 120
        session.start()
        await clock.waitForPendingSleeps()
        await clock.advance(by: .milliseconds(100))
        await waitUntil { session.position > 0 }
        XCTAssertEqual(session.position, 0.2, accuracy: 0.000_01)
        let startCount = await speech.startCount
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(session.state, .reading)
        session.stop()
    }

    func testVoiceGatedSpeedNeedsMatchingEvidenceAndStopsOnDigression() async {
        let (session, speech, clock) = await voiceSession(mode: .voiceGated)
        await speech.emit(.audioLevel(0.5))
        session.advance(at: now)
        XCTAssertEqual(session.position, 0)
        XCTAssertEqual(session.state, .waiting)
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.state == .reading }
        await clock.advance(by: .milliseconds(100))
        session.advance(at: await clock.now())
        XCTAssertGreaterThan(session.position, 0)
        XCTAssertLessThan(session.position, 4, "Fixed pace must not jump directly to recognized words")
        let position = session.position
        await speech.emit(.transcript(text: "sorry my coffee spilled everywhere", audioStart: 2, audioEnd: 4, isFinal: true))
        await waitUntil { session.state == .waiting }
        await clock.advance(by: .milliseconds(100))
        session.advance(at: await clock.now())
        XCTAssertEqual(session.position, position)
        session.stop()
    }

    func testPauseReleasesCaptureAndResumeCreatesFreshGeneration() async {
        let (session, speech, _) = await voiceSession()
        let stoppedBeforePause = await speech.stopCount
        session.pause()
        XCTAssertEqual(session.state, .paused)
        await waitUntil { await speech.stopCount > stoppedBeforePause }
        session.start()
        await waitUntil { await speech.startCount == 2 }
        await waitUntil { session.state == .waiting }
        session.stop()
        await waitUntil { await speech.stopCount > stoppedBeforePause + 1 }
        XCTAssertEqual(session.state, .idle)
    }

    func testSeekClearsVoiceGateUntilNewEvidence() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: true))
        await waitUntil { session.wordIndex == 4 }
        session.seek(to: 6)
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(session.wordIndex, 6)
        session.stop()
    }

    func testCompletionReleasesCapture() async {
        let (session, speech, _) = await voiceSession(text: "Hello everyone welcome")
        let stoppedBeforeCompletion = await speech.stopCount
        await speech.emit(.transcript(text: "hello everyone welcome", audioStart: 0, audioEnd: 2, isFinal: true))
        await waitUntil { session.state == .finished }
        XCTAssertEqual(session.wordIndex, 3)
        await waitUntil { await speech.stopCount > stoppedBeforeCompletion }
    }

    func testDelayedPreSeekRevisionCannotReactivateRepeatedParagraph() async {
        let (session, speech, _) = await voiceSession(mode: .voiceGated,
            text: "Quarterly customer retention improved. Quarterly customer retention improved. Next we discuss revenue.")
        await speech.emit(.transcript(text: "quarterly customer retention improved", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.state == .reading }
        session.seek(to: 4)
        await speech.emit(.transcript(text: "quarterly customer retention improved!", audioStart: 0, audioEnd: 2, isFinal: true))
        await drainTasks()
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(session.wordIndex, 4)
        await speech.emit(.transcript(text: "quarterly customer retention improved", audioStart: 2, audioEnd: 4, isFinal: true))
        await waitUntil { session.state == .reading }
        session.stop()
    }

    func testPresentationNumbersRemainFiniteAndBounded() {
        let speech = MockTeleprompterSpeechService()
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let session = TeleprompterReadingSession(speech: speech, clock: clock)
        session.wordsPerMinute = .nan
        XCTAssertEqual(session.wordsPerMinute, 140)
        session.wordsPerMinute = 999
        XCTAssertEqual(session.wordsPerMinute, 300)
        session.fontSize = .infinity
        XCTAssertEqual(session.fontSize, 24)
        session.fontSize = 0
        XCTAssertEqual(session.fontSize, 16)
        session.fontSize = 100
        XCTAssertEqual(session.fontSize, 40)
    }

    func testProviderFailurePreservesCursorAndReleasesCapture() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: true))
        await waitUntil { session.wordIndex == 4 }
        let stoppedBeforeFailure = await speech.stopCount
        await speech.emit(.failure(.audioConfigurationChanged))
        await waitUntil { session.state == .failed }
        XCTAssertEqual(session.wordIndex, 4)
        XCTAssertNotNil(session.message)
        await waitUntil { await speech.stopCount > stoppedBeforeFailure }
    }

    func testCancelledGenerationCannotApplyEventAfterClockSuspends() async {
        let speech = MockTeleprompterSpeechService(events: [.preparing])
        let clock = SuspendedTeleprompterClock(now: now)
        let session = TeleprompterReadingSession(speech: speech, clock: clock)
        session.prepare(text: script)
        session.start()
        await clock.waitForNowRequest()
        session.pause()
        await clock.releaseNow()
        await drainTasks()
        XCTAssertEqual(session.state, .paused, "A stale event must not restore preparing/reading after Pause")
        session.stop()
    }

    func testMicrophoneLevelAndActualInputAreVisibleWithoutAdvancingOffScript() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.inputDevice(name: "Built-in microphone"))
        await speech.emit(.audioLevel(0.001))
        await waitUntil { session.inputLevel > 0 && session.inputDeviceName != nil }
        XCTAssertEqual(session.microphoneDescription, "Built-in microphone")
        XCTAssertEqual(session.wordIndex, 0)
        XCTAssertFalse(session.hasRecognizedSpeech)
        XCTAssertTrue(session.statusText.contains("Built-in microphone"))
        await speech.emit(.transcript(text: "the weather has been lovely today", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.hasRecognizedSpeech }
        XCTAssertEqual(session.wordIndex, 0)
        XCTAssertEqual(session.state, .waiting)
        session.pause()
        XCTAssertEqual(session.inputLevel, 0)
    }

    func testQuietVoiceContinuesFixedPaceBetweenDelayedRecognitionUpdates() async {
        let (session, speech, clock) = await voiceSession(mode: .voiceGated)
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 1, isFinal: false))
        await waitUntil { session.state == .reading }
        await clock.advance(by: .milliseconds(1_100))
        await speech.emit(.audioLevel(0.001))
        await waitUntil { session.inputLevel > 0 }
        await clock.advance(by: .milliseconds(100))
        session.advance(at: await clock.now())
        XCTAssertEqual(session.state, .reading, "Quiet microphone input must not be rejected by the old fixed gain threshold")
        XCTAssertGreaterThan(session.position, 0)
        session.stop()
    }

    func testSelectedMicrophoneIsRoutedAndChangingItPausesCapture() async {
        let devices = [TeleprompterMicrophone(id: "airpods", name: "AirPods", isDefault: true),
                       TeleprompterMicrophone(id: "built-in", name: "Built-in microphone", isDefault: false)]
        let speech = MockTeleprompterSpeechService(microphones: devices)
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let session = TeleprompterReadingSession(speech: speech, clock: clock)
        session.refreshInputDevices()
        await waitUntil { session.availableMicrophones.count == 2 }
        session.inputDeviceID = "built-in"
        session.prepare(text: script)
        session.start()
        await waitUntil { session.state == .waiting }
        let selected = await speech.requestedInputDeviceID
        XCTAssertEqual(selected, "built-in")
        session.inputDeviceID = "airpods"
        XCTAssertEqual(session.state, .paused)
        XCTAssertEqual(session.microphoneDescription, "AirPods")
        session.stop()
    }

    func testFinalPunctuationRevisionDoesNotRestartScrollingAfterSilence() async {
        let (session, speech, clock) = await voiceSession(mode: .voiceGated)
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 1, isFinal: false))
        await waitUntil { session.state == .reading }
        await clock.advance(by: .seconds(1))
        session.advance(at: await clock.now())
        XCTAssertEqual(session.state, .waiting)
        let held = session.position
        await speech.emit(.transcript(text: "Welcome, everyone, to our.", audioStart: 0, audioEnd: 1, isFinal: true))
        await drainTasks()
        session.advance(at: await clock.now())
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(session.position, held)
        session.stop()
    }

    func testRealDeclarationRecognitionRevisionsAdvanceThroughTheOpening() async {
        let source = """
        In Congress, July 4, 1776
        The unanimous Declaration of the thirteen united States of America,
        When in the Course of human events, it becomes necessary for one people to dissolve the political bands which have connected them with another,
        and to assume among the powers of the earth, the separate and equal station to which the Laws of Nature and of Nature's God entitle them.
        """
        let (session, speech, _) = await voiceSession(text: source)
        let recognized = "In Congress, July 4th, 1776, the unanimous declaration of the 13 United States of America, when in the course of human events, it becomes necessary for one people to dissolve the political bands which have connected them with another."
        // These word/number forms and same-range revisions were observed from the
        // real local Apple transcriber on synthetic Declaration audio, not a mic.
        await speech.emit(.transcript(text: "In Congress, July 4th, 1776", audioStart: 0, audioEnd: 15.219, isFinal: false))
        await speech.emit(.transcript(text: recognized, audioStart: 0, audioEnd: 15.219, isFinal: false))
        let expected = (session.alignment.words.firstIndex(where: { $0.text == "another" }) ?? -1) + 1
        await waitUntil { session.wordIndex == expected }
        await speech.emit(.transcript(text: recognized, audioStart: 0, audioEnd: 14.76, isFinal: true))
        await drainTasks()
        XCTAssertEqual(session.wordIndex, expected)
        XCTAssertGreaterThan(session.wordIndex, 36, "A delayed partial must not strand the reader behind its old search horizon")
        session.stop()
    }

    func testVoiceGatedModeReanchorsWhenReadingStartsPastTheHeading() async {
        let source = Array(repeating: "An introductory heading and passage precede this statement.", count: 8).joined(separator: " ")
            + "\nWe hold these truths to be self-evident, that all men are created equal, that they are endowed by their Creator with certain unalienable Rights."
        let (session, speech, _) = await voiceSession(mode: .voiceGated, text: source)
        await speech.emit(.transcript(text: "we hold these truths to be self evident that all men are created equal",
            audioStart: 0, audioEnd: 5, isFinal: false))
        let start = session.alignment.words.firstIndex(where: { $0.text == "We" }) ?? 0
        await waitUntil { session.position >= Double(start) }
        XCTAssertEqual(session.state, .reading)
        session.stop()
    }

    func testFirstTwoWordsAdvanceWithoutWaitingForAThreeWordPhrase() async {
        let (session, speech, _) = await voiceSession(text: "In Congress July 4 1776 we declare these truths.")
        await speech.emit(.transcript(text: "In", audioStart: 0, audioEnd: 1, isFinal: false))
        await waitUntil { session.wordIndex == 1 }
        await speech.emit(.transcript(text: "In Congress", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.wordIndex == 2 }
        session.stop()
    }

    func testOpeningFragmentAndUnrelatedFirstWordDoNotAdvance() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.transcript(text: "wel", audioStart: 0, audioEnd: 1, isFinal: false))
        await drainTasks()
        XCTAssertEqual(session.wordIndex, 0)
        await speech.emit(.transcript(text: "everyone", audioStart: 0, audioEnd: 1, isFinal: true))
        await drainTasks()
        XCTAssertEqual(session.wordIndex, 0, "One-word startup must not search ahead")
        await speech.emit(.transcript(text: "Welcome", audioStart: 0, audioEnd: 1, isFinal: false))
        await waitUntil { session.wordIndex == 1 }
        session.stop()
    }

    func testFirstWordAfterSeekUsesNewAnchorAndRejectsOldAudio() async {
        let (session, speech, _) = await voiceSession()
        await speech.emit(.transcript(text: "welcome everyone to our", audioStart: 0, audioEnd: 2, isFinal: false))
        await waitUntil { session.wordIndex == 4 }
        session.seek(to: 6)
        await speech.emit(.transcript(text: "Customer", audioStart: 0, audioEnd: 2, isFinal: true))
        await drainTasks()
        XCTAssertEqual(session.wordIndex, 6)
        await speech.emit(.transcript(text: "Customer", audioStart: 2, audioEnd: 3, isFinal: false))
        await waitUntil { session.wordIndex == 7 }
        session.stop()
    }

    private func voiceSession(mode: TeleprompterMode = .voiceFollow, text: String? = nil) async
        -> (TeleprompterReadingSession, MockTeleprompterSpeechService, TestAppClock) {
        let speech = MockTeleprompterSpeechService()
        let clock = TestAppClock(now: now, automaticallyAdvances: false)
        let session = TeleprompterReadingSession(speech: speech, clock: clock)
        session.prepare(text: text ?? script)
        session.mode = mode
        session.start()
        await waitUntil { session.state == .waiting }
        await clock.waitForPendingSleeps()
        return (session, speech, clock)
    }

    private func waitUntil(_ predicate: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if await predicate() { return }
            await Task.yield()
        }
        XCTFail("Expected asynchronous state was not reached", file: file, line: line)
    }

    private func drainTasks() async {
        for _ in 0..<30 { await Task.yield() }
    }
}

private actor SuspendedTeleprompterClock: AppClock {
    private let date: Date
    private var pending: CheckedContinuation<Date, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []

    init(now: Date) { date = now }

    func now() async -> Date {
        await withCheckedContinuation { continuation in
            pending = continuation
            let waiting = observers
            observers.removeAll()
            waiting.forEach { $0.resume() }
        }
    }

    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }

    func waitForNowRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func releaseNow() {
        pending?.resume(returning: date)
        pending = nil
    }
}
