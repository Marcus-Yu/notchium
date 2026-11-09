import NotchiumCore
@testable import NotchiumDynamicIsland
import XCTest

@MainActor
final class NotchPageModelTests: XCTestCase {
    func testAdditionalDisplayCopiesDisabledPagePolicy() {
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 0), automaticallyAdvances: false)
        let primary = DynamicIslandPresentationModel(clock: clock)
        primary.pageModel.enabledPages = [.home, .music]
        primary.pageModel.defaultPage = .music
        let secondary = DynamicIslandPresentationModel(clock: clock)
        secondary.useRenderers(from: primary)
        XCTAssertEqual(secondary.pageModel.enabledPages, [.home, .music])
        XCTAssertEqual(secondary.pageModel.defaultPage, .music)
        secondary.pageModel.selectedPage = .teleprompter
        XCTAssertEqual(secondary.pageModel.selectedPage, .music)
    }

    func testHomeMusicCalendarAndAudioAreOrderedTopLevelPages() {
        let model = NotchPageModel()
        XCTAssertEqual(model.enabledPages, [.home, .music, .calendar, .pomodoro, .audio, .shelf, .teleprompter])
        XCTAssertEqual(model.selectedPage, .home)
        model.moveSelection(forward: true)
        XCTAssertEqual(model.selectedPage, .music)
        XCTAssertEqual(NotchPage.music.title, "Music")
        XCTAssertEqual(NotchPage.calendar.symbol, "calendar")
        XCTAssertEqual(NotchPage.audio.title, "Audio")

        model.moveSelection(forward: true)
        XCTAssertEqual(model.selectedPage, .calendar)
        model.moveSelection(forward: true)
        XCTAssertEqual(model.selectedPage, .pomodoro, "Focus Timer sits between Calendar and Audio")
        model.moveSelection(forward: true)
        XCTAssertEqual(model.selectedPage, .audio)
        model.moveSelection(forward: false)
        XCTAssertEqual(model.selectedPage, .pomodoro)
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
        XCTAssertEqual(model.enabledPages, [.home])
        model.enabledPages = [.calendar, .calendar, .music]
        XCTAssertEqual(model.enabledPages, [.calendar, .music])
        model.moveSelection(forward: true)
        XCTAssertEqual(model.selectedPage, .music)
        model.enabledPages = []
        XCTAssertEqual(model.selectedPage, .home)
    }
}
