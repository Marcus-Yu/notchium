import NotchiumDynamicIsland
import XCTest

@MainActor
final class NotchPageModelTests: XCTestCase {
    func testDefaultsAndEnabledPageOrder() {
        let model = NotchPageModel()
        XCTAssertEqual(model.enabledPages, [.home, .media, .system, .utilities, .focus])
        model.enabledPages = [.focus, .media, .home]
        XCTAssertEqual(model.enabledPages, [.focus, .media, .home])
        model.moveSelection(forward: true)
        XCTAssertEqual(model.selectedPage, .focus)
        model.moveSelection(forward: false)
        XCTAssertEqual(model.selectedPage, .home)
    }

    func testDisabledPageCannotBeSelected() {
        let model = NotchPageModel(enabledPages: [.home, .focus])
        model.selectedPage = .media
        XCTAssertEqual(model.selectedPage, .home)
    }

    func testDisablingSelectionFallsBackToEnabledDefaultThenFirstPage() {
        let model = NotchPageModel(selectedPage: .media, defaultPage: .focus)
        model.enabledPages = [.home, .focus]
        XCTAssertEqual(model.selectedPage, .focus)
        model.enabledPages = [.utilities, .home]
        XCTAssertEqual(model.selectedPage, .utilities)
        model.defaultPage = .home
        model.selectDefaultPage()
        XCTAssertEqual(model.selectedPage, .home)
    }

    func testEmptyAndDuplicateListsKeepValidSelection() {
        let model = NotchPageModel(enabledPages: [])
        XCTAssertEqual(model.enabledPages, [.home])
        model.enabledPages = [.focus, .focus, .media]
        XCTAssertEqual(model.enabledPages, [.focus, .media])
        XCTAssertEqual(model.selectedPage, .focus)
        model.enabledPages = []
        XCTAssertEqual(model.selectedPage, .home)
    }
}
