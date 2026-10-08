import Foundation

public enum HomeSectionID: String, Codable, CaseIterable, Identifiable, Sendable {
    case media, calendar, shortcuts
    public var id: Self { self }
    public var title: String {
        switch self {
        case .media: "Media"
        case .calendar: "Calendar"
        case .shortcuts: "Shortcuts"
        }
    }
}

/// Layout only: Media and Calendar retain their existing feature state owners.
public struct HomeConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var schemaVersion = currentVersion
    public var sectionOrder = HomeSectionID.allCases.map(\.rawValue)
    public var enabledSections = [HomeSectionID.media.rawValue, HomeSectionID.calendar.rawValue]
    public var shortcuts: [QuickAction] = []
    // Keep unsupported records intact when saving known items after an upgrade/downgrade.
    private var retainedShortcuts: [HomeJSONValue] = []

    public init() {}
    /// Home has fixed primary regions; legacy section order remains losslessly persisted.
    public var primarySections: [HomeSectionID] {
        [.media, .calendar].filter { enabledSections.contains($0.rawValue) }
    }
    public var showsShortcutRegion: Bool {
        enabledSections.contains(HomeSectionID.shortcuts.rawValue)
            && shortcuts.contains { $0.pinnedToHome && $0.enabled }
    }
    public mutating func normalize() {
        var seen: Set<String> = []
        sectionOrder = sectionOrder.filter { seen.insert($0).inserted }
        for section in HomeSectionID.allCases where !seen.contains(section.rawValue) {
            sectionOrder.append(section.rawValue)
        }
        seen.removeAll()
        enabledSections = enabledSections.filter { seen.insert($0).inserted }
        var ids: Set<UUID> = []
        shortcuts = shortcuts.sorted { $0.order < $1.order }.filter { ids.insert($0.id).inserted }
        for index in shortcuts.indices { shortcuts[index].order = index }
    }
    public mutating func resetLayout() {
        sectionOrder = HomeSectionID.allCases.map(\.rawValue)
        enabledSections = [HomeSectionID.media.rawValue, HomeSectionID.calendar.rawValue]
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, sectionOrder, enabledSections, shortcuts }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentVersion
        sectionOrder = (try? values.decode([String].self, forKey: .sectionOrder)) ?? HomeSectionID.allCases.map(\.rawValue)
        enabledSections = (try? values.decode([String].self, forKey: .enabledSections)) ?? ["media", "calendar"]
        let records = (try? values.decode([HomeJSONValue].self, forKey: .shortcuts)) ?? []
        for record in records {
            if let data = try? JSONEncoder().encode(record),
               let shortcut = try? JSONDecoder().decode(QuickAction.self, from: data) {
                shortcuts.append(shortcut)
            } else { retainedShortcuts.append(record) }
        }
        normalize()
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(sectionOrder, forKey: .sectionOrder)
        try values.encode(enabledSections, forKey: .enabledSections)
        let records = try shortcuts.map { try JSONDecoder().decode(HomeJSONValue.self, from: JSONEncoder().encode($0)) }
        try values.encode(records + retainedShortcuts, forKey: .shortcuts)
    }
}

/// Lossless JSON records let one bad or future shortcut leave its neighbors readable.
private enum HomeJSONValue: Codable, Equatable, Sendable {
    case object([String: HomeJSONValue]), array([HomeJSONValue]), string(String), number(Decimal), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Decimal.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([Self].self) { self = .array(array) }
        else { self = .object(try value.decode([String: Self].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .string(let string): try value.encode(string)
        case .number(let number): try value.encode(number)
        case .bool(let bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }
}
