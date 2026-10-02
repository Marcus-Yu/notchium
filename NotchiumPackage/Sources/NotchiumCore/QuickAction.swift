import Foundation

public enum QuickActionKind: String, Codable, CaseIterable, Sendable {
    case shortcut, application, file, folder, url, systemAction
    public var title: String {
        switch self {
        case .shortcut: "Apple Shortcut"
        case .application: "Application"
        case .file: "File"
        case .folder: "Folder"
        case .url: "URL"
        case .systemAction: "System Action"
        }
    }
    public var symbol: String {
        switch self {
        case .shortcut: "square.stack.3d.up"
        case .application: "app"
        case .file: "doc"
        case .folder: "folder"
        case .url: "globe"
        case .systemAction: "gearshape"
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
    public var bundleIdentifier: String?
    public var bookmark: Data?
    public var symbol: String?
    public var enabled: Bool
    public var pinnedToHome: Bool
    public var order: Int

    public init(id: UUID = UUID(), kind: QuickActionKind, displayName: String = "", target: String = "",
                bookmark: Data? = nil, shortcutID: UUID? = nil, symbol: String? = nil, enabled: Bool = true,
                pinnedToHome: Bool = false, order: Int = 0, bundleIdentifier: String? = nil) {
        self.id = id; self.kind = kind; self.displayName = displayName; self.target = target
        self.shortcutID = shortcutID
        self.bundleIdentifier = bundleIdentifier
        self.bookmark = bookmark; self.symbol = symbol; self.enabled = enabled
        self.pinnedToHome = pinnedToHome; self.order = order
    }

    public static func validatedWebURL(_ text: String) -> URL? {
        guard let url = validatedURL(text), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    public static func validatedURL(_ text: String) -> URL? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              input.removingPercentEncoding != nil,
              let components = URLComponents(string: input), let scheme = components.scheme?.lowercased(),
              !["file", "javascript", "data", "vbscript", "shell", "ssh", "telnet"].contains(scheme),
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        if scheme == "https" || scheme == "http" {
            guard let host = components.host, !host.isEmpty else { return nil }
        } else {
            guard !(components.host ?? "").isEmpty || !components.path.isEmpty else { return nil }
        }
        return url
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, displayName, target, shortcutID, bundleIdentifier, bookmark, symbol, enabled, pinnedToHome, order
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(QuickActionKind.self, forKey: .kind)
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName) ?? kind.title
        target = try values.decodeIfPresent(String.self, forKey: .target) ?? ""
        shortcutID = try values.decodeIfPresent(UUID.self, forKey: .shortcutID)
        bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        bookmark = try values.decodeIfPresent(Data.self, forKey: .bookmark)
        symbol = try values.decodeIfPresent(String.self, forKey: .symbol)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        pinnedToHome = try values.decodeIfPresent(Bool.self, forKey: .pinnedToHome) ?? false
        order = try values.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
}

public enum NativeHomeAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case systemSettings, downloads, desktop
    public var id: Self { self }
    public var title: String {
        switch self {
        case .systemSettings: "Open System Settings"
        case .downloads: "Open Downloads"
        case .desktop: "Open Desktop"
        }
    }
    public var symbol: String {
        switch self {
        case .systemSettings: "gearshape"
        case .downloads: "arrow.down.circle"
        case .desktop: "desktopcomputer"
        }
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

public struct ExistingShortcut: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}
