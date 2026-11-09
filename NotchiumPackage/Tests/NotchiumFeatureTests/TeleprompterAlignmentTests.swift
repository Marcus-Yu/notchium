import Foundation
import NotchiumCore
import XCTest

final class TeleprompterAlignmentTests: XCTestCase {
    func testOpeningMatchesOnlyExactCompleteWordsAtTheChosenPosition() {
        let alignment = TeleprompterAlignment(text: "Welcome everyone to our report. Revenue grew 25 percent.")
        XCTAssertEqual(alignment.matchOpening(transcript: "Welcome", at: 0, allowTrailingPartial: true)?.nextWordIndex, 1)
        XCTAssertEqual(alignment.matchOpening(transcript: "Welcome every", at: 0, allowTrailingPartial: true)?.nextWordIndex, 1)
        XCTAssertNil(alignment.matchOpening(transcript: "Welcome every", at: 0, allowTrailingPartial: false))
        XCTAssertNil(alignment.matchOpening(transcript: "everyone", at: 0, allowTrailingPartial: true))
        XCTAssertNil(alignment.matchOpening(transcript: "wel", at: 0, allowTrailingPartial: true))
        XCTAssertNil(alignment.matchOpening(transcript: "twenty", at: 7, allowTrailingPartial: true))
        XCTAssertEqual(alignment.matchOpening(transcript: "twenty five", at: 7, allowTrailingPartial: true)?.nextWordIndex, 8)
    }

    func testExactPhraseAdvancesToExclusiveWordBoundary() throws {
        let alignment = TeleprompterAlignment(text: "Welcome everyone to our quarterly product review.")
        let match = try XCTUnwrap(alignment.match(transcript: "welcome everyone to our", near: 0))
        XCTAssertEqual(match.nextWordIndex, 4)
        XCTAssertEqual(match.matchedWordRange, 0..<4)
        XCTAssertEqual(match.score, 1)
    }

    func testOffScriptSpeechDoesNotAdvance() {
        let alignment = TeleprompterAlignment(text: "Welcome everyone to our quarterly product review. Revenue increased significantly this quarter.")
        XCTAssertNil(alignment.match(transcript: "Sorry my coffee cup is about to fall off the table", near: 4))
        XCTAssertNil(alignment.match(transcript: "we are going to the", near: 4))
        XCTAssertNil(alignment.match(transcript: "to our the and", near: 4))
    }

    func testNearbyPhraseReacquiresAfterDigression() throws {
        let alignment = TeleprompterAlignment(text: "Welcome everyone to our quarterly product review. Revenue increased significantly this quarter.")
        let match = try XCTUnwrap(alignment.match(transcript: "One moment please my phone is ringing revenue increased significantly", near: 7))
        XCTAssertEqual(match.nextWordIndex, 10)
    }

    func testRepeatedPhraseChoosesClosestOccurrence() throws {
        let alignment = TeleprompterAlignment(text: "Thank you for joining today. Our revenue increased substantially. Thank you for joining today. Next we discuss hiring.")
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: "thank you for joining today", near: 0)).nextWordIndex, 5)
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: "thank you for joining today", near: 10)).nextWordIndex, 14)
    }

    func testShortPhraseCannotSkipToDistantMatchingOccurrence() {
        let middle = Array(repeating: "completely different content", count: 5).joined(separator: " ")
        let alignment = TeleprompterAlignment(text: "Beginning of our presentation. \(middle) Important project milestones.")
        XCTAssertNil(alignment.match(transcript: "important project milestones", near: 0))
    }

    func testPhraseOutsideSearchWindowRequiresDeliberateSeek() throws {
        let middle = Array(repeating: "unrelated filler", count: 40).joined(separator: " ")
        let alignment = TeleprompterAlignment(text: "Opening words here. \(middle) Customer adoption exceeded expectations.")
        XCTAssertNil(alignment.match(transcript: "customer adoption exceeded expectations", near: 0))
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: "customer adoption exceeded expectations", near: 83)).nextWordIndex,
                       alignment.wordCount)
    }

    func testNearbyBacktrackingCanReanchorWithoutJumpingForward() throws {
        let alignment = TeleprompterAlignment(text: "First we discuss revenue growth. Next we review customer feedback.")
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: "discuss revenue growth", near: 7)).nextWordIndex, 5)
    }

    func testUnicodePunctuationAndContractionsPreserveDisplayRanges() throws {
        let alignment = TeleprompterAlignment(text: "We’re ready—let’s discuss café growth.\nOur next milestone is shipping.")
        XCTAssertEqual(alignment.words.map(\.text).prefix(4), ["We’re", "ready", "let’s", "discuss"])
        let match = try XCTUnwrap(alignment.match(transcript: "we are ready let us discuss cafe growth", near: 0))
        XCTAssertEqual(match.nextWordIndex, 6)
        for word in alignment.words {
            XCTAssertEqual(String(alignment.text[word.range]), word.text)
        }
        XCTAssertEqual(alignment.paragraphs.count, 2)
        XCTAssertEqual(alignment.paragraphs[0].wordRange, 0..<6)
        XCTAssertEqual(alignment.paragraphs[1].wordRange, 6..<11)
    }

    func testSpokenNumbersMatchDigitsAndDecimal() throws {
        let alignment = TeleprompterAlignment(text: "Revenue grew 25 percent to 2.5 million.")
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: "revenue grew twenty five percent", near: 0)).nextWordIndex, 4)
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: "to two point five million", near: 4)).nextWordIndex, 7)
    }

    func testSpokenThousandsMatchGroupedDigits() throws {
        let alignment = TeleprompterAlignment(text: "We welcomed 1,200 new customers this quarter.")
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: "we welcomed one thousand two hundred new customers", near: 0)).nextWordIndex, 5)
    }

    func testBriefFillerDoesNotLosePlace() throws {
        let alignment = TeleprompterAlignment(text: "Customer retention increased substantially this quarter.")
        let match = try XCTUnwrap(alignment.match(transcript: "customer retention um increased substantially", near: 0))
        XCTAssertEqual(match.nextWordIndex, 4)
    }

    func testLimitedRecognitionErrorRetainsLongPhrase() throws {
        let alignment = TeleprompterAlignment(text: "Customer retention increased substantially across every major region this quarter.")
        let match = try XCTUnwrap(alignment.match(transcript: "customer retention increased significantly across every major region", near: 0))
        XCTAssertEqual(match.nextWordIndex, 8)
    }

    func testTrailingOffScriptWordsDoNotAdvanceFromStaleMatchingPrefix() {
        let alignment = TeleprompterAlignment(text: "Customer retention increased substantially this quarter.")
        XCTAssertNil(alignment.match(transcript: "customer retention increased sorry let me answer the door", near: 0))
    }

    func testNoMatchForEmptyOrInsufficientEvidence() {
        let alignment = TeleprompterAlignment(text: "Customer retention increased substantially.")
        XCTAssertNil(alignment.match(transcript: "", near: 0))
        XCTAssertNil(alignment.match(transcript: "customer", near: 0))
        XCTAssertNil(TeleprompterAlignment(text: " \n").match(transcript: "hello there everyone", near: 0))
    }

    func testShortScriptAndOutOfRangeCursorAreSafe() throws {
        let alignment = TeleprompterAlignment(text: "Hello world")
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: "hello world", near: -1)).nextWordIndex, 2)
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: "hello world", near: 10_000)).nextWordIndex, 2)
    }

    func testSourceSnapshotModelsRoundTripWithoutGeneratingIdentity() throws {
        let script = TeleprompterScript(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                       title: "Weekly update", text: "Original script")
        XCTAssertEqual(try JSONDecoder().decode(TeleprompterScript.self, from: JSONEncoder().encode(script)), script)
        XCTAssertFalse(TeleprompterMode.fixedSpeed.usesMicrophone)
        XCTAssertTrue(TeleprompterMode.voiceFollow.usesMicrophone)
        XCTAssertTrue(TeleprompterMode.voiceGated.usesMicrophone)
    }
}
