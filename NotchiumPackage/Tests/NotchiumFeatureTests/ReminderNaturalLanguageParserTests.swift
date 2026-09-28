import Foundation
import XCTest
@testable import NotchiumQuickActionsFeature

final class ReminderNaturalLanguageParserTests: XCTestCase {
    private let parser = ReminderNaturalLanguageParser()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.locale = Locale(identifier: "en_CA")
        calendar.firstWeekday = 1
        return calendar
    }
    private func date(_ day: Int = 27, month: Int = 9, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }
    func testRequestedExamples() throws {
        for (text, title, expected, timed) in [
            ("test friday 3:00pm", "test", date(2, month: 10, hour: 15), true),
            ("dentist tomorrow 10:30am", "dentist", date(28, hour: 10, minute: 30), true),
            ("meeting next monday 2 pm", "meeting", date(5, month: 10, hour: 14), true),
            ("call mom today 6pm", "call mom", date(hour: 18), true),
            ("submit assignment september 30 11:59pm", "submit assignment", date(30, hour: 23, minute: 59), true),
            ("buy milk friday", "buy milk", date(2, month: 10, hour: 0), false),
            ("call dentist tomorrow at 9am", "call dentist", date(28, hour: 9), true),
            ("call mom 6pm", "call mom", date(hour: 18), true)
        ] {
            let result = try XCTUnwrap(parser.parse(text, now: date(), calendar: calendar), text)
            XCTAssertEqual(result.title, title, text)
            XCTAssertEqual(result.date, expected, text)
            XCTAssertEqual(result.includesTime, timed, text)
        }
    }
    func testAllDateAndTimeSpellings() throws {
        for day in ["September 30", "Sep 30", "September 30 2026", "9/30", "9/30/2026"] {
            for time in ["3pm", "3 pm", "3:00pm", "3:00 pm", "15:00"] {
                let text = "test \(day) \(time)"
                let result = try XCTUnwrap(parser.parse(text, now: date(), calendar: calendar), text)
                XCTAssertEqual(result.date, date(30, hour: 15), text)
                XCTAssertEqual(result.title, "test", text)
            }
        }
    }
    func testWeekdaysAndCalendarWeekBoundary() throws {
        for (offset, weekday) in ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"].enumerated() {
            let result = try XCTUnwrap(parser.parse("test \(weekday)", now: date(), calendar: calendar))
            XCTAssertEqual(calendar.dateComponents([.day], from: calendar.startOfDay(for: date()), to: result.date).day, offset + 1)
        }
        let friday = date(2, month: 10)
        XCTAssertEqual(parser.parse("test friday", now: friday, calendar: calendar)?.date, date(9, month: 10, hour: 0))
        XCTAssertEqual(parser.parse("test this friday", now: friday, calendar: calendar)?.date, date(2, month: 10, hour: 0))
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        XCTAssertEqual(parser.parse("test next monday", now: date(), calendar: mondayFirst)?.date, date(28, hour: 0))
    }
    func testTimeOnlyAlwaysFutureAndDST() throws {
        XCTAssertEqual(parser.parse("call 6pm", now: date(hour: 19), calendar: calendar)?.date, date(28, hour: 18))
        XCTAssertEqual(parser.parse("call 6pm", now: date(hour: 18), calendar: calendar)?.date, date(28, hour: 18))
        let spring = date(8, month: 3, hour: 0)
        let result = try XCTUnwrap(parser.parse("call 2:30am", now: spring, calendar: calendar))
        XCTAssertGreaterThan(result.date, spring)
        XCTAssertEqual(calendar.component(.hour, from: result.date), 3)
        XCTAssertNil(parser.parse("call today 2:30am", now: spring, calendar: calendar))
    }
    func testInvalidTimePreservesValidDateAndUnparsedText() throws {
        let result = try XCTUnwrap(parser.parse("test friday 37pm", now: date(), calendar: calendar))
        XCTAssertEqual(result.date, date(2, month: 10, hour: 0))
        XCTAssertEqual(result.title, "test 37pm")
        XCTAssertFalse(result.includesTime)
        XCTAssertTrue(result.preservesTime)
        XCTAssertEqual(parser.parse("test friday at 37pm", now: date(), calendar: calendar)?.title, "test at 37pm")
        for text in ["call last friday", "call every monday", "call next tomorrow", "call 003pm", "call -3pm"] {
            XCTAssertNil(parser.parse(text, now: date(), calendar: calendar), text)
        }
    }

    func testTimeFormattingHasStableIdentity() {
        let original = parser.parse("test friday 3pm", now: date(), calendar: calendar)
        for text in ["updated friday 3:00 pm", "updated Friday 15:00"] {
            XCTAssertEqual(original?.signature, parser.parse(text, now: date(), calendar: calendar)?.signature)
        }
    }

    func testInvalidAmbiguousAndUnicodeInput() throws {
        for text in ["test sometime later", "test 25:00", "test 3:99pm", "test 3:0pm", "test 9/31", "test February 30 2026", "test 9/30/202", "Friday is a movie", "test 😀", "", "call 3pm please"] {
            XCTAssertNil(parser.parse(text, now: date(), calendar: calendar), text)
        }
        let result = try XCTUnwrap(parser.parse("  📞 call José tomorrow at 9am  ", now: date(), calendar: calendar))
        XCTAssertEqual(result.title, "📞 call José")
        XCTAssertEqual(parser.parse("friday 3pm", now: date(), calendar: calendar)?.title, "")
        XCTAssertEqual(parser.parse("read Friday stories on tomorrow at 9am", now: date(), calendar: calendar)?.title, "read Friday stories")
    }
}
