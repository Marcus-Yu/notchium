import XCTest

final class NotchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSkeletonLaunchesWithoutPermissionPrompts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertEqual(app.alerts.count, 0)
    }
}
