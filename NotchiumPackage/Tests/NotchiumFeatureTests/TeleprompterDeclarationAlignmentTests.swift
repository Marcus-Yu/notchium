import Foundation
import NotchiumCore
import XCTest

final class TeleprompterDeclarationAlignmentTests: XCTestCase {
    private let declaration = """
    In Congress, July 4, 1776

    The unanimous Declaration of the thirteen united States of America, When in the Course of human events, it becomes necessary for one people to dissolve the political bands which have connected them with another, and to assume among the powers of the earth, the separate and equal station to which the Laws of Nature and of Nature's God entitle them, a decent respect to the opinions of mankind requires that they should declare the causes which impel them to the separation.

    We hold these truths to be self-evident, that all men are created equal, that they are endowed by their Creator with certain unalienable Rights, that among these are Life, Liberty and the pursuit of Happiness.--That to secure these rights, Governments are instituted among Men, deriving their just powers from the consent of the governed, --That whenever any Form of Government becomes destructive of these ends, it is the Right of the People to alter or to abolish it, and to institute new Government, laying its foundation on such principles and organizing its powers in such form, as to them shall seem most likely to effect their Safety and Happiness.
    """

    func testDeclarationHeadingAcceptsSpokenOrdinalAndYear() throws {
        let alignment = TeleprompterAlignment(text: declaration)
        let match = try XCTUnwrap(alignment.match(transcript: "in congress july fourth seventeen seventy six", near: 0))
        XCTAssertEqual(match.nextWordIndex, 5)
    }

    func testFirstLongRecognitionBatchCanPassTheOriginalThirtySixWordWindow() throws {
        let alignment = TeleprompterAlignment(text: declaration)
        let transcript = alignment.words[5..<65].map(\.text).joined(separator: " ")
        let match = try XCTUnwrap(alignment.match(transcript: transcript, near: 0))
        XCTAssertEqual(match.nextWordIndex, 65)
    }

    func testReaderCanStartAtTheFamousParagraphWithoutReadingTheHeading() throws {
        let alignment = TeleprompterAlignment(text: declaration)
        let index = try XCTUnwrap(alignment.words.firstIndex(where: { $0.text == "We" }))
        let transcript = alignment.words[index..<(index + 17)].map(\.text).joined(separator: " ")
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: transcript, near: 0)).nextWordIndex, index + 17)
    }

    func testDeclarationParagraphsFollowProgressiveAndBatchedResults() throws {
        let alignment = TeleprompterAlignment(text: declaration)
        var position = 0
        for end in stride(from: 7, to: alignment.wordCount, by: 7) {
            let transcript = alignment.words[max(0, end - 24)..<end].map(\.text).joined(separator: " ")
            position = try XCTUnwrap(alignment.match(transcript: transcript, near: position), "Failed at word \(end)").nextWordIndex
            XCTAssertEqual(position, end)
        }
        let last = alignment.words.suffix(18).map(\.text).joined(separator: " ")
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: last, near: position)).nextWordIndex, alignment.wordCount)
    }

    func testMinorDeclarationRecognitionErrorsDoNotLoseThePhrase() throws {
        let alignment = TeleprompterAlignment(text: declaration)
        let index = try XCTUnwrap(alignment.words.firstIndex(where: { $0.text == "unalienable" }))
        let transcript = "their creator with certain inalienable rights"
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: transcript, near: index - 4)).nextWordIndex, index + 2)
    }

    func testAnchoredFinalWordCanTolerateDeclarationSpellingVariation() throws {
        let alignment = TeleprompterAlignment(text: declaration)
        let index = try XCTUnwrap(alignment.words.firstIndex(where: { $0.text == "unalienable" }))
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: "their creator with certain inalienable", near: index - 4))
            .nextWordIndex, index + 1)
    }

    func testLongRecoveryAllowsAnOmittedFunctionWord() throws {
        let alignment = TeleprompterAlignment(text: declaration)
        let transcript = "governments are instituted among men deriving just powers from the consent of the governed"
        let end = try XCTUnwrap(alignment.words.firstIndex(where: { $0.text == "governed" })) + 1
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: transcript, near: 20)).nextWordIndex, end)
    }

    func testPrintedOrdinalDateAndCardinalNumberFormsStillMatch() throws {
        let alignment = TeleprompterAlignment(text: "In Congress, July 4th, 1776")
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: "in congress july four one thousand seven hundred seventy six", near: 0))
            .nextWordIndex, alignment.wordCount)
    }

    func testUniqueLongPhraseRecoversAfterMissingARecognizedSentence() throws {
        let alignment = TeleprompterAlignment(text: declaration)
        let transcript = "governments are instituted among men deriving their just powers from the consent of the governed"
        let end = try XCTUnwrap(alignment.words.firstIndex(where: { $0.text == "governed" })) + 1
        XCTAssertEqual(try XCTUnwrap(alignment.match(transcript: transcript, near: 20)).nextWordIndex, end)
    }

    func testRecoveryStillRejectsUnrelatedSpeechAndAmbiguousDistantRepeats() {
        let phrase = "important community members approved the final publication schedule today"
        let gap = Array(repeating: "different material follows here", count: 25).joined(separator: " ")
        let alignment = TeleprompterAlignment(text: "Opening words here. \(gap) \(phrase). \(gap) \(phrase).")
        XCTAssertNil(alignment.match(transcript: phrase, near: 0), "Distant duplicated phrases need a manual anchor")
        XCTAssertNil(TeleprompterAlignment(text: declaration).match(transcript:
            "please wait while I answer a phone call about tomorrow's appointment", near: 0))
    }
}
