import Foundation
import NotchiumCore
import Observation

/// One authoritative, versioned Home record; Stage 11 preference keys are migration inputs only.
@MainActor @Observable public final class QuickActionStore {
    public static let configurationKey = "home.configuration.v1"
    public private(set) var configuration: HomeConfiguration
    public var actions: [QuickAction] { configuration.shortcuts }
    public var showOnHome: Bool {
        get { configuration.enabledSections.contains(HomeSectionID.shortcuts.rawValue) }
        set { try? setSectionEnabled(.shortcuts, enabled: newValue) }
    }
    public var reminderListID: String { didSet { preferences.set(reminderListID, forKey: "quickActions.reminderListID") } }
    public private(set) var error: String?
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var isReadOnly = false

    public init(preferences: UserDefaults) {
        self.preferences = preferences
        reminderListID = preferences.string(forKey: "quickActions.reminderListID") ?? ""
        configuration = HomeConfiguration()
        if let data = preferences.data(forKey: Self.configurationKey) {
            do {
                configuration = try JSONDecoder().decode(HomeConfiguration.self, from: data)
                if configuration.schemaVersion > HomeConfiguration.currentVersion {
                    isReadOnly = true
                    error = "Home was saved by a newer Notchium version. Update Notchium to customize it."
                }
            } catch { recover(data, key: Self.configurationKey) }
        } else if let data = preferences.data(forKey: "quickActions.v1") {
            do {
                // Decode through the per-item resilient Home schema, keeping unknown records.
                let records = try JSONSerialization.jsonObject(with: data)
                guard records is [Any] else { throw StoreFailure.unreadable }
                let migrated = try JSONSerialization.data(withJSONObject: ["shortcuts": records])
                configuration = try JSONDecoder().decode(HomeConfiguration.self, from: migrated)
                if preferences.bool(forKey: "quickActions.showOnHome") {
                    configuration.enabledSections.append(HomeSectionID.shortcuts.rawValue)
                }
                try commit(configuration)
            } catch { recover(data, key: "quickActions.v1") }
        }
    }
    public var pinned: [QuickAction] { actions.filter { $0.pinnedToHome && $0.enabled } }

    public func save(_ action: QuickAction) throws {
        var next = configuration
        if let index = next.shortcuts.firstIndex(where: { $0.id == action.id }) {
            var edited = action
            edited.order = next.shortcuts[index].order
            next.shortcuts[index] = edited
        }
        else {
            var appended = action
            appended.order = next.shortcuts.count
            next.shortcuts.append(appended)
        }
        try commit(next)
    }
    public func remove(_ id: UUID) throws {
        var next = configuration
        next.shortcuts.removeAll { $0.id == id }
        for index in next.shortcuts.indices { next.shortcuts[index].order = index }
        try commit(next)
    }
    public func move(from source: IndexSet, to destination: Int) throws {
        var next = configuration
        guard source.allSatisfy({ next.shortcuts.indices.contains($0) }),
              (0...next.shortcuts.count).contains(destination) else { return }
        let moving = source.sorted().map { next.shortcuts[$0] }
        for index in source.sorted(by: >) { next.shortcuts.remove(at: index) }
        next.shortcuts.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        for index in next.shortcuts.indices { next.shortcuts[index].order = index }
        try commit(next)
    }
    public func setSectionEnabled(_ id: HomeSectionID, enabled: Bool) throws {
        var next = configuration
        next.enabledSections.removeAll { $0 == id.rawValue }
        if enabled { next.enabledSections.append(id.rawValue) }
        try commit(next)
    }
    public func resetHomeLayout() throws {
        var next = configuration
        next.resetLayout()
        try commit(next)
    }
    private func commit(_ next: HomeConfiguration) throws {
        guard !isReadOnly else { throw StoreFailure.unreadable }
        var normalized = next
        normalized.normalize()
        preferences.set(try JSONEncoder().encode(normalized), forKey: Self.configurationKey)
        configuration = normalized
    }
    private func recover(_ data: Data, key: String) {
        // Keep the original bytes for recovery, while allowing the clean defaults to be edited.
        if preferences.data(forKey: "\(key).recovery") == nil { preferences.set(data, forKey: "\(key).recovery") }
        configuration = HomeConfiguration()
        error = "Home settings couldn’t be read. Defaults were restored; the original data was kept."
        try? commit(configuration)
    }
    public enum StoreFailure: LocalizedError {
        case unreadable
        public var errorDescription: String? { "This Home configuration can’t be changed by this version of Notchium." }
    }
}
