import AppKit
import XCTest
import NotchiumCore
import NotchiumPersistence
import NotchiumServices
@testable import NotchiumDynamicIsland
@testable import NotchiumQuickActionsFeature

@MainActor final class Stage20ShortcutTests: XCTestCase {
    private var preferences: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        suite = "Stage20.Shortcuts.\(UUID())"
        preferences = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws { preferences.removePersistentDomain(forName: suite) }

    func testWebAndCustomURLValidation() {
        for target in ["https://github.com/example/repo", "http://localhost:3000/path", "notion://page/abc", "mailto:hello@example.com", "shortcuts://run-shortcut?name=Morning"] {
            XCTAssertNotNil(QuickAction.validatedURL(target), target)
        }
        for target in ["", "example.com", "https://", "https://user:password@example.com", "javascript:alert(1)",
                       "file:///tmp/test", "data:text/plain,test", "ssh://example.com", "app:", "https://exa mple.com", "https://example.com/%ZZ", "\nhttps://example.com/\nother"] {
            XCTAssertNil(QuickAction.validatedURL(target), target)
        }
    }
    func testAllNativeKindsDispatchWithoutActivitiesOrPageChanges() async throws {
        let workspace = Stage20Workspace()
        let shortcuts = CountingStage20Shortcuts()
        let (model, presentation) = fixture(workspace: workspace, shortcuts: shortcuts)
        defer { model.runner.stop(); presentation.reset() }
        presentation.present(.expanded, animated: false)
        presentation.pageModel.selectedPage = .calendar
        for kind in [QuickActionKind.application, .file, .folder, .url] {
            let action = QuickAction(kind: kind, displayName: kind.title, target: "https://example.com")
            try model.store.save(action)
            model.runner.run(action)
            await settle(model.runner, id: action.id)
            XCTAssertTrue(model.runner.succeeded.contains(action.id))
        }
        for native in NativeHomeAction.allCases {
            let action = QuickAction(kind: .systemAction, displayName: native.title, target: native.rawValue)
            try model.store.save(action)
            model.runner.run(action)
            await settle(model.runner, id: action.id)
        }
        XCTAssertEqual(workspace.opened.count, 7)
        XCTAssertEqual(workspace.opened.suffix(3).map(\.target), NativeHomeAction.allCases.map(\.rawValue))
        XCTAssertNil(presentation.notificationCoordinator.active)
        XCTAssertNil(presentation.activityCoordinator.activeTransient)
        XCTAssertEqual(presentation.pageModel.selectedPage, .calendar)
    }
    func testUnavailableAndDeniedTargetsStayEditableAndDisableLaunch() async throws {
        let workspace = Stage20Workspace()
        let (model, presentation) = fixture(workspace: workspace)
        defer { model.runner.stop(); presentation.reset() }
        for kind in [QuickActionKind.application, .file, .folder] {
            let action = QuickAction(kind: kind, displayName: kind.title, pinnedToHome: true)
            try model.store.save(action)
            workspace.failure = .unavailable
            await model.runner.validate(action)
            XCTAssertFalse(model.runner.canRun(action))
            XCTAssertNotNil(model.runner.unavailable[action.id])
            workspace.failure = .accessDenied
            await model.runner.validate(action)
            XCTAssertEqual(model.runner.unavailable[action.id], QuickActionFailure.accessDenied.localizedDescription)
            workspace.failure = nil
            await model.runner.validate(action)
            XCTAssertTrue(model.runner.canRun(action))
        }
        XCTAssertEqual(model.store.actions.count, 3)
    }
    func testDeletedAppleShortcutCannotSubstituteReusedName() async throws {
        let original = ExistingShortcut(id: UUID(), name: "Morning")
        let service = CountingStage20Shortcuts(shortcuts: [original])
        let (model, presentation) = fixture(shortcuts: service)
        defer { model.runner.stop(); presentation.reset() }
        let action = QuickAction(kind: .shortcut, displayName: original.name, target: original.name,
                                 shortcutID: original.id, pinnedToHome: true)
        try model.store.save(action)
        await model.runner.refresh()
        XCTAssertTrue(model.runner.canRun(action))
        model.runner.run(action)
        await settle(model.runner, id: action.id)
        let firstExecutions = await service.executions
        XCTAssertEqual(firstExecutions, [original])
        await service.replace([ExistingShortcut(id: UUID(), name: "Morning")])
        await model.runner.refresh()
        XCTAssertFalse(model.runner.canRun(action))
        model.runner.run(action)
        await settle(model.runner, id: action.id)
        let executions = await service.executions
        XCTAssertEqual(executions, [original])
        XCTAssertEqual(model.store.actions.count, 1)
        XCTAssertNotNil(model.runner.unavailable[action.id])
    }
    func testHomePreparationCachesDiscoveryResolutionAndIcons() async throws {
        let service = CountingStage20Shortcuts(shortcuts: [.init(id: UUID(), name: "Morning")])
        let workspace = Stage20Workspace()
        let clock = TestAppClock(now: Date(timeIntervalSince1970: 1_800_000_000), automaticallyAdvances: false)
        let (model, presentation) = fixture(workspace: workspace, shortcuts: service, clock: clock)
        defer { model.runner.stop(); presentation.reset() }
        let available = await service.list()
        let chosen = try XCTUnwrap(available.first)
        try model.store.save(QuickAction(kind: .shortcut, displayName: "Morning", target: chosen.name, shortcutID: chosen.id, pinnedToHome: true))
        try model.store.save(QuickAction(kind: .file, displayName: "Project", pinnedToHome: true))
        await model.runner.prepareHome()
        for _ in 0..<10 { await model.runner.prepareHome() }
        let lists = await service.listCount
        XCTAssertEqual(lists, 2, "One explicit fixture list and one cached Home discovery")
        XCTAssertEqual(workspace.resolutions, 1)
        XCTAssertEqual(workspace.iconPreparations, 2)
        await clock.advance(by: .seconds(61))
        await model.runner.prepareHome()
        let refreshedLists = await service.listCount
        XCTAssertEqual(refreshedLists, 3)
        XCTAssertEqual(workspace.resolutions, 2)
    }
    func testNoShortcutEnumerationForOnlyFileAndURLPins() async throws {
        let service = CountingStage20Shortcuts()
        let (model, presentation) = fixture(shortcuts: service)
        defer { model.runner.stop(); presentation.reset() }
        try model.store.save(QuickAction(kind: .url, displayName: "Docs", target: "https://example.com", pinnedToHome: true))
        await model.runner.prepareHome()
        let count = await service.listCount
        XCTAssertEqual(count, 0)
    }
    func testNativeBookmarkRestoreAndMissingFileFolderAvailability() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("stage20-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("document.txt")
        try Data("fixture".utf8).write(to: file)
        let workspace = NativeQuickActionWorkspace()
        let bookmark = try file.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let action = QuickAction(kind: .file, displayName: "Document", target: file.absoluteString, bookmark: bookmark)
        let restored = try JSONDecoder().decode(QuickAction.self, from: JSONEncoder().encode(action))
        let resolved = try await workspace.resolve(restored)
        XCTAssertEqual(URL(string: resolved.target)?.standardizedFileURL.path, file.standardizedFileURL.path)
        await workspace.prepareIcon(for: resolved)
        XCTAssertNotNil(workspace.icon(for: resolved))
        let folder = QuickAction(kind: .folder, displayName: "Project", target: directory.absoluteString,
                                 bookmark: try directory.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        _ = try await workspace.resolve(folder)
        try FileManager.default.removeItem(at: directory)
        for missing in [action, folder] {
            do { _ = try await workspace.resolve(missing); XCTFail("Missing resource must be unavailable") }
            catch { XCTAssertEqual(error as? QuickActionFailure, .unavailable) }
        }
    }
    func testNativeApplicationBundleFallbackAndMissingApplication() async throws {
        let appURL = try XCTUnwrap(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder"))
        let action = QuickAction(kind: .application, displayName: "Finder", target: "file:///missing/Finder.app",
                                 bundleIdentifier: "com.apple.finder")
        let workspace = NativeQuickActionWorkspace()
        let resolved = try await workspace.resolve(action)
        XCTAssertEqual(URL(string: resolved.target), appURL)
        XCTAssertNotNil(resolved.bookmark)
        var missing = action; missing.bundleIdentifier = "invalid.stage20.missing"
        do { _ = try await workspace.resolve(missing); XCTFail("Removed app must be unavailable") }
        catch { XCTAssertEqual(error as? QuickActionFailure, .unavailable) }
    }
    func testDisabledActionDoesNotExecute() async throws {
        let workspace = Stage20Workspace()
        let (model, presentation) = fixture(workspace: workspace)
        defer { model.runner.stop(); presentation.reset() }
        let disabled = QuickAction(kind: .url, displayName: "Docs", target: "https://example.com", enabled: false)
        try model.store.save(disabled)
        model.runner.run(disabled)
        XCTAssertFalse(model.runner.canRun(disabled))
        XCTAssertTrue(workspace.opened.isEmpty)
    }
    func testStoppedExecutionCannotClearANewRunOfTheSameShortcut() async throws {
        let workspace = SuspendedStage20Workspace()
        let (model, presentation) = fixture(workspace: workspace)
        defer { model.runner.stop(); presentation.reset() }
        let action = QuickAction(kind: .url, displayName: "Docs", target: "https://example.com")
        try model.store.save(action)
        model.runner.run(action)
        for _ in 0..<1000 where workspace.pending.count < 1 { await Task.yield() }
        XCTAssertEqual(workspace.pending.count, 1)
        model.runner.stop()
        model.runner.run(action)
        for _ in 0..<1000 where workspace.pending.count < 2 { await Task.yield() }
        XCTAssertEqual(workspace.pending.count, 2)
        workspace.pending.removeFirst().resume()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(model.runner.running.contains(action.id), "Old cancellation must not clear the newer execution")
        workspace.pending.removeFirst().resume()
        await settle(model.runner, id: action.id)
        XCTAssertTrue(model.runner.succeeded.contains(action.id))
    }
    private func settle(_ runner: QuickActionRunner, id: UUID) async {
        for _ in 0..<1000 where runner.running.contains(id) { await Task.yield() }
        XCTAssertFalse(runner.running.contains(id))
    }
    private func fixture(workspace: Stage20Workspace = Stage20Workspace(),
                         shortcuts: any ShortcutService = CountingStage20Shortcuts(),
                         clock: TestAppClock = TestAppClock(now: Date(), automaticallyAdvances: false)) -> (QuickActionsModel, DynamicIslandPresentationModel) {
        let presentation = DynamicIslandPresentationModel(clock: clock)
        let store = QuickActionStore(preferences: preferences)
        let runner = QuickActionRunner(store: store, workspace: workspace, shortcuts: shortcuts,
                                       notifications: presentation.notificationCoordinator, clock: clock)
        let reminder = QuickReminderModel(service: MockReminderService(), workspace: workspace, store: store,
                                          notifications: presentation.notificationCoordinator, clock: clock)
        return (QuickActionsModel(store: store, runner: runner, reminder: reminder), presentation)
    }
}

@MainActor class Stage20Workspace: QuickActionWorkspace {
    var opened: [QuickAction] = []
    var failure: QuickActionFailure?
    var resolutions = 0
    var iconPreparations = 0
    func chooseTarget(for kind: QuickActionKind) async throws -> QuickAction? { nil }
    func resolve(_ action: QuickAction) throws -> QuickAction {
        resolutions += 1
        if let failure { throw failure }
        return action
    }
    func open(_ action: QuickAction) async throws {
        if let failure { throw failure }
        opened.append(action)
    }
    func prepareIcon(for action: QuickAction) { iconPreparations += 1 }
    func icon(for action: QuickAction) -> NSImage? { nil }
    func openReminderPrivacy() {}
}

@MainActor private final class SuspendedStage20Workspace: Stage20Workspace {
    var pending: [CheckedContinuation<Void, Never>] = []
    override func open(_ action: QuickAction) async throws {
        await withCheckedContinuation { pending.append($0) }
    }
}

actor CountingStage20Shortcuts: ShortcutService {
    var shortcuts: [ExistingShortcut]
    private(set) var listCount = 0
    private(set) var executions: [ExistingShortcut] = []
    init(shortcuts: [ExistingShortcut] = []) { self.shortcuts = shortcuts }
    func list() -> [ExistingShortcut] { listCount += 1; return shortcuts }
    func replace(_ shortcuts: [ExistingShortcut]) { self.shortcuts = shortcuts }
    func run(_ shortcut: ExistingShortcut) throws {
        guard shortcuts.filter({ $0 == shortcut }).count == 1 else { throw QuickActionFailure.shortcutMissing }
        executions.append(shortcut)
    }
}
