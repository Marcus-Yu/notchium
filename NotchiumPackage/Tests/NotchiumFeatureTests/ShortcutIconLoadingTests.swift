import AppKit
import Observation
import XCTest
import NotchiumCore
import NotchiumPersistence
import NotchiumServices
@testable import NotchiumDynamicIsland
@testable import NotchiumQuickActionsFeature

@MainActor final class ShortcutIconLoadingTests: XCTestCase {
    func testFirstHomePreparationInvalidatesTheIconWithoutRunningTheShortcut() async throws {
        let suite = "Shortcuts.IconLoading.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = QuickActionStore(preferences: preferences)
        let action = QuickAction(kind: .application, displayName: "Calendar", target: "file:///Applications/Calendar.app",
                                 pinnedToHome: true)
        try store.save(action)
        let workspace = IconLoadingWorkspace()
        let clock = TestAppClock(now: Date(), automaticallyAdvances: false)
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let runner = QuickActionRunner(store: store, workspace: workspace, shortcuts: CountingStage20Shortcuts(),
                                       notifications: presentation.notificationCoordinator, clock: clock)
        defer { runner.stop(); presentation.reset() }
        let observation = IconLoadingObservation()
        XCTAssertNil(workspace.icon(for: action))
        withObservationTracking {
            _ = QuickActionIcon(action: action, runner: runner).body
        } onChange: {
            MainActor.assumeIsolated { observation.invalidated = true }
        }

        await runner.prepareHome()

        XCTAssertNotNil(workspace.icon(for: action))
        XCTAssertTrue(runner.icon(for: action) === workspace.icon(for: action))
        XCTAssertTrue(observation.invalidated, "The placeholder must redraw as soon as the native icon loads")
        XCTAssertTrue(workspace.opened.isEmpty, "Loading an icon must not launch the application")
        await runner.prepareHome()
        XCTAssertEqual(workspace.iconPreparations, 1, "Repeated Home presentation reuses the prepared icon")

        var edited = action
        edited.target = "file:///Applications/Reminders.app"
        try store.save(edited)
        XCTAssertNil(runner.icon(for: edited), "An edited target must not display the previous application's icon")
        await runner.prepareHomeAction(edited)
        XCTAssertNotNil(runner.icon(for: edited))
        XCTAssertNil(runner.icon(for: action))
    }
}

@MainActor private final class IconLoadingWorkspace: Stage20Workspace {
    private var prepared: QuickAction?
    private let image = NSImage(size: NSSize(width: 18, height: 18))
    override func prepareIcon(for action: QuickAction) {
        super.prepareIcon(for: action)
        prepared = action
    }
    override func icon(for action: QuickAction) -> NSImage? { prepared == action ? image : nil }
}

@MainActor private final class IconLoadingObservation {
    var invalidated = false
}
