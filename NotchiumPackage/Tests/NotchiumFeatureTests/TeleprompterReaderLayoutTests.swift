import NotchiumCore
@testable import NotchiumTeleprompterFeature
import XCTest

@MainActor
final class TeleprompterReaderLayoutTests: XCTestCase {
    private let source = "• “In Congress, July 4, 1776.”\n\nThe unanimous Declaration of the thirteen united States of America, when in the Course of human events, it becomes necessary for one people to dissolve the political bands."

    func testWidthAndFontReflowPreserveEverySourceCharacterAndWordIdentity() {
        let alignment = TeleprompterAlignment(text: source)
        for (width, font) in [(CGFloat(490), 16.0), (619, 24), (619, 40)] {
            let lines = TeleprompterReaderLayout.lines(alignment: alignment, width: width, fontSize: font)
            XCTAssertFalse(lines.isEmpty)
            XCTAssertEqual(lines.flatMap(\.fragments).map(\.text).joined(), source)
            XCTAssertEqual(lines.flatMap(\.fragments).filter(\.isWord).map(\.wordIndex), Array(0..<alignment.wordCount))
            XCTAssertTrue(zip(lines, lines.dropFirst()).allSatisfy { $0.id < $1.id })
        }
    }

    func testWiderReaderUsesAvailableWidthAndLargerFontReflowsIntoMoreLines() {
        let alignment = TeleprompterAlignment(text: Array(repeating: "Customer retention increased substantially across every region.", count: 10).joined(separator: " "))
        let compact = TeleprompterReaderLayout.lines(alignment: alignment, width: 488, fontSize: 24)
        let expanded = TeleprompterReaderLayout.lines(alignment: alignment, width: 619, fontSize: 24)
        let large = TeleprompterReaderLayout.lines(alignment: alignment, width: 619, fontSize: 40)
        XCTAssertLessThan(expanded.count, compact.count)
        XCTAssertGreaterThan(large.count, expanded.count)
    }

    func testParagraphStartsRemainReanchorableAndInvalidMeasurementsAreSafe() {
        let alignment = TeleprompterAlignment(text: source)
        let lines = TeleprompterReaderLayout.lines(alignment: alignment, width: 619, fontSize: 24)
        XCTAssertTrue(lines.contains { $0.id == alignment.paragraphs[1].wordRange.lowerBound })
        XCTAssertTrue(TeleprompterReaderLayout.lines(alignment: alignment, width: 0, fontSize: 24).isEmpty)
        XCTAssertTrue(TeleprompterReaderLayout.lines(alignment: alignment, width: .infinity, fontSize: 24).isEmpty)
        XCTAssertTrue(TeleprompterReaderLayout.lines(alignment: alignment, width: 619, fontSize: .nan).isEmpty)
    }
}
