import Foundation

public struct NotchiumDisplayID: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

public struct NotchiumDisplayInsets: Equatable, Sendable {
    public let top: CGFloat
    public let leading: CGFloat
    public let bottom: CGFloat
    public let trailing: CGFloat

    public init(
        top: CGFloat = 0,
        leading: CGFloat = 0,
        bottom: CGFloat = 0,
        trailing: CGFloat = 0
    ) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

public struct NotchiumDisplaySnapshot: Equatable, Sendable {
    public let id: NotchiumDisplayID
    public let name: String
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaInsets: NotchiumDisplayInsets
    public let auxiliaryTopLeftArea: CGRect?
    public let auxiliaryTopRightArea: CGRect?
    public let isBuiltIn: Bool
    public let isPrimary: Bool
    public let backingScaleFactor: CGFloat

    public init(
        id: NotchiumDisplayID,
        name: String,
        frame: CGRect,
        visibleFrame: CGRect? = nil,
        safeAreaInsets: NotchiumDisplayInsets = NotchiumDisplayInsets(),
        auxiliaryTopLeftArea: CGRect? = nil,
        auxiliaryTopRightArea: CGRect? = nil,
        isBuiltIn: Bool,
        isPrimary: Bool,
        backingScaleFactor: CGFloat = 2
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame ?? frame
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.isBuiltIn = isBuiltIn
        self.isPrimary = isPrimary
        self.backingScaleFactor = backingScaleFactor
    }

    public var isEligiblePhysicalNotchDisplay: Bool {
        isBuiltIn && safeAreaInsets.top > 0
    }

    public var physicalNotchGap: CGRect? {
        guard
            let left = auxiliaryTopLeftArea,
            let right = auxiliaryTopRightArea,
            right.minX > left.maxX
        else {
            return nil
        }

        return CGRect(
            x: left.maxX,
            y: min(left.minY, right.minY),
            width: right.minX - left.maxX,
            height: max(left.height, right.height)
        )
    }
}

public enum NotchSurfaceMode: String, CaseIterable, Equatable, Sendable {
    case physicalNotch
    case virtualPill
}

public struct NotchShellPlacement: Equatable, Sendable {
    public let display: NotchiumDisplaySnapshot
    public let mode: NotchSurfaceMode

    public init(display: NotchiumDisplaySnapshot, mode: NotchSurfaceMode) {
        self.display = display
        self.mode = mode
    }
}

public enum NotchiumDisplaySelectionPolicy {
    public static func select(from displays: [NotchiumDisplaySnapshot]) -> NotchShellPlacement? {
        if let physicalDisplay = displays.first(where: \.isEligiblePhysicalNotchDisplay) {
            return NotchShellPlacement(display: physicalDisplay, mode: .physicalNotch)
        }

        guard let virtualDisplay = displays.first(where: \.isPrimary) ?? displays.first else {
            return nil
        }
        return NotchShellPlacement(display: virtualDisplay, mode: .virtualPill)
    }
}
