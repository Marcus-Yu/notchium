import NotchiumCore
@testable import NotchiumTeleprompterFeature
import XCTest

final class TeleprompterScriptDisplayTests: XCTestCase {
    func testLineFragmentsPreserveOriginalPunctuationAndSymbols() {
        let source = "• “Budget: $5.00—approved?”\nNext: 20%, then ‘go’."
        let alignment = TeleprompterAlignment(text: source)
        var displayed = ""
        for index in 0..<alignment.wordCount {
            displayed += String(TeleprompterScriptDisplay.line(alignment: alignment,
                words: index..<(index + 1), currentWord: 2).characters)
        }
        XCTAssertEqual(displayed, source)
    }

    func testWholeScriptRetainsOriginalSpacingAndNonLatinText() {
        let source = "  Bonjour — l’équipe!\n\n你好，世界。\tMerci."
        let alignment = TeleprompterAlignment(text: source)
        let display = TeleprompterScriptDisplay.line(alignment: alignment,
            words: 0..<alignment.wordCount, currentWord: 0)
        XCTAssertEqual(String(display.characters), source)
    }

    func testBulletStaysWithItsOwnParagraph() {
        let alignment = TeleprompterAlignment(text: "First.\n\n• Second, item.")
        let first = TeleprompterScriptDisplay.line(alignment: alignment, words: 0..<1, currentWord: 0)
        let second = TeleprompterScriptDisplay.line(alignment: alignment, words: 1..<alignment.wordCount, currentWord: 1)
        XCTAssertEqual(String(first.characters), "First.\n\n")
        XCTAssertEqual(String(second.characters), "• Second, item.")
    }
}
