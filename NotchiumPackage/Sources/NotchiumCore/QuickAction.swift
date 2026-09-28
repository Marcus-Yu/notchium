import Foundation

public enum QuickActionKind: String, Codable, CaseIterable, Sendable {
    case shortcut, application, file, folder, url
    public var title: String {
        switch self {
        case .shortcut: "Apple Shortcut"
        case .application: "Application"
        case .file: "File"
        case .folder: "Folder"
        case .url: "Website"
        }
    }
    public var symbol: String {
        switch self {
        case .shortcut: "square.stack.3d.up"
        case .application: "app"
        case .file: "doc"
        case .folder: "folder"
        case .url: "globe"
        }
    }
}

public struct QuickAction: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: QuickActionKind
    public var displayName: String
    /// An exact Shortcuts name, or an absolute URL. Local resources also require a bookmark.
    public var target: String
    public var shortcutID: UUID?
    public var bookmark: Data?
    public var symbol: String?
    public var enabled: Bool
    public var pinnedToHome: Bool
    public var order: Int

    public init(id: UUID = UUID(), kind: QuickActionKind, displayName: String = "", target: String = "",
                bookmark: Data? = nil, shortcutID: UUID? = nil, symbol: String? = nil, enabled: Bool = true,
                pinnedToHome: Bool = false, order: Int = 0) {
        self.id = id; self.kind = kind; self.displayName = displayName; self.target = target
        self.shortcutID = shortcutID
        self.bookmark = bookmark; self.symbol = symbol; self.enabled = enabled
        self.pinnedToHome = pinnedToHome; self.order = order
    }

    public static func validatedWebURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

public struct ReminderList: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public enum ReminderAccess: Equatable, Sendable { case notDetermined, allowed, denied, restricted }

public struct ReminderDraft: Equatable, Sendable {
    public var title: String
    public var date: Date
    public var includesTime: Bool
    public init(title: String = "", date: Date, includesTime: Bool = false) {
        self.title = title; self.date = date; self.includesTime = includesTime
    }
    public func dueComponents(timeZone: TimeZone = .current) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let fields: Set<Calendar.Component> = includesTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        var components = calendar.dateComponents(fields, from: date)
        components.calendar = calendar
        if includesTime { components.timeZone = timeZone }
        return components
    }
    public static func nextHalfHour(after date: Date, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: date)
        let start = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        return calendar.date(byAdding: .minute, value: 30 - minute % 30, to: start) ?? date
    }
}

public struct ExistingShortcut: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}
