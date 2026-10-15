import Foundation
import Observation

public enum NotchDisplaySelection: String, Codable, CaseIterable, Sendable {
    case builtIn
    case all
    case selected
}

public struct NotchDisplayPreferences: Codable, Equatable, Sendable {
    public var selection: NotchDisplaySelection = .builtIn
    public var selectedDisplayKey: String?
    public var selectedDisplayName: String?
    public var createsNotch = false

    public init() {}
}

/// User choices survive reconnects through Core Graphics UUIDs, never screen order or names.
@MainActor
@Observable
public final class NotchDisplaySettings {
    public var preferences: NotchDisplayPreferences {
        didSet {
            guard preferences != oldValue, let data = try? JSONEncoder().encode(preferences) else { return }
            storage?.set(data, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "notchium.display.preferences.v1"
    @ObservationIgnored private let storage: UserDefaults?

    public init(storage: UserDefaults? = nil) {
        self.storage = storage
        preferences = storage?.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(NotchDisplayPreferences.self, from: $0) }
            ?? NotchDisplayPreferences()
    }
}

extension NotchiumDisplaySnapshot {
    public var selectionKey: String {
        persistentID.map { "uuid:\($0.uuidString)" } ?? "display:\(id.rawValue)"
    }
}

enum NotchDisplayPlacementPolicy {
    static func placements(
        displays: [NotchiumDisplaySnapshot], preferences: NotchDisplayPreferences
    ) -> [NotchShellPlacement] {
        // Keep the built-in display first even when an external monitor owns the menu bar.
        let preferred = displays.first(where: \.isBuiltIn)
            ?? displays.first(where: \.isPrimary) ?? displays.first
        let selected: [NotchiumDisplaySnapshot]
        switch preferences.selection {
        case .builtIn:
            selected = preferred.map { [$0] } ?? []
        case .all:
            selected = preferred.map { first in [first] + displays.filter { $0.id != first.id } } ?? []
        case .selected:
            // A disconnected saved monitor falls back without overwriting the saved choice.
            selected = (displays.first { $0.selectionKey == preferences.selectedDisplayKey } ?? preferred)
                .map { [$0] } ?? []
        }
        let reference = displays.first { $0.isBuiltIn && $0.isEligiblePhysicalNotchDisplay }
        return selected.map { display in
            if display.isEligiblePhysicalNotchDisplay, display.physicalNotchGap != nil {
                return NotchShellPlacement(display: display, mode: .physicalNotch)
            }
            return NotchShellPlacement(
                display: display,
                mode: preferences.createsNotch ? .simulatedNotch : .virtualPill,
                simulatedNotchSize: preferences.createsNotch
                    ? simulatedSize(display: display, reference: reference) : nil
            )
        }
    }

    private static func simulatedSize(
        display: NotchiumDisplaySnapshot, reference: NotchiumDisplaySnapshot?
    ) -> CGSize {
        // Match the notch-to-screen proportions in logical points, independent of Retina scale.
        let referenceFrame = reference?.frame.size ?? CGSize(width: 1512, height: 982)
        let referenceNotch = CGSize(width: reference?.physicalNotchGap?.width ?? 212,
                                   height: reference?.safeAreaInsets.top ?? 38)
        return CGSize(
            width: max(1, display.frame.width * referenceNotch.width / max(1, referenceFrame.width)),
            height: max(1, display.frame.height * referenceNotch.height / max(1, referenceFrame.height))
        )
    }
}
