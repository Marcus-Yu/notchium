import NotchiumServices
import XCTest

final class TeleprompterMeetingContextTests: XCTestCase {
    func testOnlyActiveKnownConferenceInputSuggestsACall() {
        XCTAssertEqual(classify("us.zoom.xos"), .probableCall(provider: "Zoom"))
        XCTAssertEqual(classify("com.microsoft.teams2"), .probableCall(provider: "Microsoft Teams"))
        XCTAssertEqual(classify("com.microsoft.teams2.helper"), .probableCall(provider: "Microsoft Teams"))
        XCTAssertEqual(classify("us.zoom.xos", running: false), .idle)
        XCTAssertEqual(classify("us.zoom.xos.fake-unrelated", ownPID: 1), .idle)
        XCTAssertEqual(classify("us.zoom.xosimilar"), .idle)
        XCTAssertEqual(classify("com.apple.TextEdit"), .idle)
    }

    func testOwnMicrophoneCaptureCannotTriggerAMeetingSuggestion() {
        XCTAssertEqual(classify("us.zoom.xos", ownPID: 1), .idle)
        XCTAssertEqual(classify("com.google.Chrome", ownPID: 1), .idle)
    }

    func testBrowserInputIsEvidenceOnlyAndNeedsMeetingContext() {
        XCTAssertEqual(classify("com.google.Chrome.helper"), .browserUsingInput)
        XCTAssertEqual(classify("com.apple.Safari"), .browserUsingInput)
        XCTAssertEqual(classify("org.mozilla.firefox", running: false), .idle)
    }

    func testNativeCallEvidenceTakesPrecedenceOverBrowserInput() {
        let processes = [
            TeleprompterAudioInputProcess(processID: 1, bundleID: "com.google.Chrome", isRunningInput: true),
            TeleprompterAudioInputProcess(processID: 2, bundleID: "com.microsoft.teams2", isRunningInput: true)
        ]
        XCTAssertEqual(TeleprompterMeetingClassifier.context(for: processes, excludingProcessID: 100),
                       .probableCall(provider: "Microsoft Teams"))
    }

    private func classify(_ bundleID: String, running: Bool = true, ownPID: Int32 = 100) -> TeleprompterMeetingContext {
        TeleprompterMeetingClassifier.context(for: [
            .init(processID: 1, bundleID: bundleID, isRunningInput: running)
        ], excludingProcessID: ownPID)
    }
}
