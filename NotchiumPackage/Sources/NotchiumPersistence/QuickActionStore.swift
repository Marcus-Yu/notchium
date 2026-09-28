import Foundation
import NotchiumCore
import Observation

@MainActor @Observable public final class QuickActionStore {
    public static let homeCapacity = 4
    public private(set) var actions: [QuickAction]
    public var showOnHome: Bool { didSet { preferences.set(showOnHome, forKey: "quickActions.showOnHome") } }
    public var reminderListID: String { didSet { preferences.set(reminderListID, forKey: "quickActions.reminderListID") } }
    public private(set) var error: String?
    @ObservationIgnored private let preferences: UserDefaults
    public init(preferences: UserDefaults) {
        self.preferences = preferences
        showOnHome = preferences.bool(forKey: "quickActions.showOnHome")
        reminderListID = preferences.string(forKey: "quickActions.reminderListID") ?? ""
        if let data = preferences.data(forKey: "quickActions.v1") {
            do { actions = try JSONDecoder().decode([QuickAction].self, from: data).sorted { $0.order < $1.order } }
            catch { actions = []; self.error = "Couldn’t read saved actions. Restart before making changes." }
        } else { actions = [] }
    }
    public var pinned: [QuickAction] { Array(actions.filter { $0.pinnedToHome && $0.enabled }.prefix(Self.homeCapacity)) }
    public func save(_ action: QuickAction) throws {
        var next = actions
        if let index = next.firstIndex(where: { $0.id == action.id }) { next[index] = action }
        else { next.append(action) }
        guard next.filter(\.pinnedToHome).count <= Self.homeCapacity else { throw StoreFailure.pinLimit }
        try commit(next)
    }
    public func remove(_ id: UUID) throws { try commit(actions.filter { $0.id != id }) }
    public func move(from source: IndexSet, to destination: Int) throws {
        var next = actions
        let moving = source.sorted().map { next[$0] }
        for index in source.sorted(by: >) { next.remove(at: index) }
        next.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        try commit(next)
    }
    private func commit(_ next: [QuickAction]) throws {
        guard error == nil else { throw StoreFailure.unreadable }
        let ordered = next.enumerated().map { index, action in var action = action; action.order = index; return action }
        preferences.set(try JSONEncoder().encode(ordered), forKey: "quickActions.v1")
        actions = ordered
    }
    public enum StoreFailure: LocalizedError {
        case pinLimit, unreadable
        public var errorDescription: String? {
            switch self {
            case .pinLimit: "Home can show up to four pinned actions. Unpin an action first."
            case .unreadable: "Saved actions could not be read. Restart before making changes."
            }
        }
    }
}
