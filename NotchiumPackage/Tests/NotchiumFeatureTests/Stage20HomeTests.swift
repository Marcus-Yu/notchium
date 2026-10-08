import XCTest
import NotchiumCore
import NotchiumPersistence

@MainActor final class Stage20HomeTests: XCTestCase {
    private var preferences: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        suite = "Stage20.Home.\(UUID())"
        preferences = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws { preferences.removePersistentDomain(forName: suite) }

    func testAuxiliaryRegionRequiresVisiblePinsAndKeepsLegacyLayoutData() throws {
        let store = QuickActionStore(preferences: preferences)
        try store.setSectionEnabled(.shortcuts, enabled: true)
        XCTAssertFalse(store.configuration.showsShortcutRegion, "Enabling an empty region must reserve no space")
        let action = QuickAction(kind: .url, displayName: "Docs", target: "https://example.com", pinnedToHome: true)
        try store.save(action)
        XCTAssertTrue(store.configuration.showsShortcutRegion)
        XCTAssertEqual(store.configuration.primarySections, [.media, .calendar])
        XCTAssertEqual(QuickActionStore(preferences: preferences).configuration, store.configuration)

        var edited = action
        edited.enabled = false
        try store.save(edited)
        XCTAssertFalse(store.configuration.showsShortcutRegion)
        edited.enabled = true; edited.pinnedToHome = false
        try store.save(edited)
        XCTAssertFalse(store.configuration.showsShortcutRegion)
        edited.pinnedToHome = true
        try store.save(edited)
        try store.setSectionEnabled(.shortcuts, enabled: false)
        XCTAssertFalse(store.configuration.showsShortcutRegion)
        try store.setSectionEnabled(.shortcuts, enabled: true)
        XCTAssertTrue(store.configuration.showsShortcutRegion)
        try store.remove(action.id)
        XCTAssertFalse(store.configuration.showsShortcutRegion)
        XCTAssertEqual(store.configuration.primarySections, [.media, .calendar])
    }

    func testDefaultsHideReorderRelaunchAndResetKeepShortcuts() throws {
        let store = QuickActionStore(preferences: preferences)
        XCTAssertEqual(store.configuration.enabledSections, ["media", "calendar"])
        let action = QuickAction(kind: .url, displayName: "Docs", target: "https://example.com", pinnedToHome: true)
        try store.save(action)
        try store.setSectionEnabled(.calendar, enabled: false)
        XCTAssertEqual(store.configuration.primarySections, [.media])
        try store.setSectionEnabled(.calendar, enabled: true)
        try store.setSectionEnabled(.shortcuts, enabled: true)
        let restored = QuickActionStore(preferences: preferences)
        XCTAssertEqual(restored.configuration.enabledSections, ["media", "calendar", "shortcuts"])
        XCTAssertEqual(restored.actions, [action])
        try restored.resetHomeLayout()
        XCTAssertEqual(restored.configuration.enabledSections, ["media", "calendar"])
        XCTAssertEqual(restored.actions, [action])
        XCTAssertEqual(QuickActionStore(preferences: preferences).configuration, restored.configuration)
    }
    func testAllSectionsMayBeHiddenWithoutDuplicateIDs() throws {
        let store = QuickActionStore(preferences: preferences)
        for section in HomeSectionID.allCases {
            try store.setSectionEnabled(section, enabled: true)
            try store.setSectionEnabled(section, enabled: true)
            try store.setSectionEnabled(section, enabled: false)
        }
        XCTAssertTrue(store.configuration.enabledSections.isEmpty)
        XCTAssertEqual(store.configuration.sectionOrder, HomeSectionID.allCases.map(\.rawValue))
    }
    func testMissingFieldsFutureSectionsAndMalformedItemsAreIndependent() throws {
        let valid = QuickAction(kind: .url, displayName: "Docs", target: "https://example.com")
        let record = try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid))
        let future: [String: Any] = ["id": UUID().uuidString, "kind": "futureAction", "payload": "kept"]
        let object: [String: Any] = ["sectionOrder": ["calendar", "futureSection", "calendar", "media"],
                                  "enabledSections": ["futureSection", "calendar", "media"],
                                  "shortcuts": [record, future, ["kind": "file"], "bad item"]]
        preferences.set(try JSONSerialization.data(withJSONObject: object), forKey: QuickActionStore.configurationKey)
        let store = QuickActionStore(preferences: preferences)
        XCTAssertEqual(store.configuration.sectionOrder, ["calendar", "futureSection", "media", "shortcuts"])
        XCTAssertEqual(store.configuration.primarySections, [.media, .calendar], "Legacy order never moves the fixed regions")
        XCTAssertEqual(store.actions, [valid])
        try store.setSectionEnabled(.media, enabled: false)
        let encoded = try XCTUnwrap(preferences.data(forKey: QuickActionStore.configurationKey))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual((saved["shortcuts"] as? [Any])?.count, 4, "Unsupported items must survive an edit")
        XCTAssertTrue(store.configuration.sectionOrder.contains("futureSection"))
    }
    func testOldShortcutFieldsReceiveDefaults() throws {
        let id = UUID()
        let data = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "kind": "url", "target": "https://example.com"])
        let action = try JSONDecoder().decode(QuickAction.self, from: data)
        XCTAssertEqual(action.id, id)
        XCTAssertTrue(action.enabled)
        XCTAssertFalse(action.pinnedToHome)
        XCTAssertEqual(action.order, 0)
    }
    func testDuplicateShortcutIDsAreNormalized() throws {
        var configuration = HomeConfiguration()
        let action = QuickAction(kind: .url, order: 20)
        configuration.shortcuts = [action, action]
        configuration.normalize()
        XCTAssertEqual(configuration.shortcuts.count, 1)
        XCTAssertEqual(configuration.shortcuts[0].order, 0)
    }
    func testCorruptHomeFallsBackAndKeepsRecoveryBytes() throws {
        let broken = Data("broken".utf8)
        preferences.set(broken, forKey: QuickActionStore.configurationKey)
        let store = QuickActionStore(preferences: preferences)
        XCTAssertEqual(store.configuration.primarySections, [.media, .calendar])
        XCTAssertNotNil(store.error)
        XCTAssertEqual(preferences.data(forKey: "\(QuickActionStore.configurationKey).recovery"), broken)
        try store.save(QuickAction(kind: .url, displayName: "Recovered", target: "https://example.com"))
        XCTAssertEqual(QuickActionStore(preferences: preferences).actions.count, 1)
    }
    func testFutureSchemaDoesNotOverwriteStoredData() throws {
        let data = Data("{\"schemaVersion\":999}".utf8)
        preferences.set(data, forKey: QuickActionStore.configurationKey)
        let store = QuickActionStore(preferences: preferences)
        XCTAssertEqual(store.configuration.primarySections, [.media, .calendar])
        XCTAssertThrowsError(try store.resetHomeLayout())
        XCTAssertEqual(preferences.data(forKey: QuickActionStore.configurationKey), data)
    }
    func testStage11MigrationPreservesActionsVisibilityAndReminderPreference() throws {
        let action = QuickAction(kind: .shortcut, displayName: "Morning", target: "Morning", shortcutID: UUID(), pinnedToHome: true)
        preferences.set(try JSONEncoder().encode([action]), forKey: "quickActions.v1")
        preferences.set(true, forKey: "quickActions.showOnHome")
        preferences.set("reminder-list", forKey: "quickActions.reminderListID")
        let store = QuickActionStore(preferences: preferences)
        XCTAssertEqual(store.actions, [action])
        XCTAssertTrue(store.showOnHome)
        XCTAssertEqual(store.reminderListID, "reminder-list")
        XCTAssertNotNil(preferences.data(forKey: QuickActionStore.configurationKey))
        preferences.set(false, forKey: "quickActions.showOnHome")
        XCTAssertTrue(QuickActionStore(preferences: preferences).showOnHome, "Legacy keys become migration inputs only")
    }
    func testShortcutCRUDAndDenseOrderingPersist() throws {
        let store = QuickActionStore(preferences: preferences)
        let actions = (0..<40).map {
            QuickAction(kind: .url, displayName: "Site \($0)", target: "https://example.com/\($0)", pinnedToHome: true)
        }
        for action in actions { try store.save(action) }
        XCTAssertEqual(store.pinned.count, 40)
        try store.move(from: IndexSet([2, 3]), to: 0)
        XCTAssertEqual(Array(store.actions.prefix(2)).map(\.id), [actions[2].id, actions[3].id])
        var edited = store.actions[0]; edited.displayName = "Edited"; edited.symbol = "star"
        try store.save(edited)
        try store.remove(actions[0].id)
        let restored = QuickActionStore(preferences: preferences)
        XCTAssertEqual(restored.actions[0].displayName, "Edited")
        XCTAssertEqual(restored.actions[0].symbol, "star")
        XCTAssertEqual(restored.actions.map(\.order), Array(0..<39))
        XCTAssertFalse(restored.actions.contains { $0.id == actions[0].id })
    }
}
