import NotchiumDynamicIsland
import XCTest

@MainActor
final class NotchPageModelTests: XCTestCase {
    func testMusicAndCalendarAreOrderedTopLevelPages() {
        let model = NotchPageModel()
        XCTAssertEqual(model.enabledPages, [.music, .calendar])
        XCTAssertEqual(model.selectedPage, .music)
        XCTAssertEqual(NotchPage.music.title, "Music")
        XCTAssertEqual(NotchPage.calendar.symbol, "calendar")

        model.moveSelection(forward: true)
        XCTAssertEqual(model.selectedPage, .calendar)
        model.moveSelection(forward: false)
        XCTAssertEqual(model.selectedPage, .music)
    }

    func testDisabledPageCannotBeSelected() {
        let model = NotchPageModel(enabledPages: [.music])
        model.selectedPage = .calendar
        XCTAssertEqual(model.selectedPage, .music)
    }

    func testSelectionFallsBackWhenEnabledPagesChange() {
        let model = NotchPageModel(selectedPage: .calendar, defaultPage: .music)
        model.enabledPages = [.music]
        XCTAssertEqual(model.selectedPage, .music)
        model.enabledPages = [.calendar]
        XCTAssertEqual(model.selectedPage, .calendar)
        model.defaultPage = .calendar
        model.selectDefaultPage()
        XCTAssertEqual(model.selectedPage, .calendar)
    }

    func testEmptyAndDuplicateListsKeepValidSelection() {
        let model = NotchPageModel(enabledPages: [])
        XCTAssertEqual(model.enabledPages, [.music])
        model.enabledPages = [.calendar, .calendar, .music]
        XCTAssertEqual(model.enabledPages, [.calendar, .music])
        model.moveSelection(forward: true)
        XCTAssertEqual(model.selectedPage, .calendar)
        model.enabledPages = []
        XCTAssertEqual(model.selectedPage, .music)
    }
}
