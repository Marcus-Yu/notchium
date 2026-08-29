#if DEBUG
import Foundation
import Observation

public enum NotchDebugDisplaySource: String, CaseIterable, Sendable {
    case live
    case builtInMock
    case externalMock
}

public enum NotchDebugSurfaceMode: String, CaseIterable, Sendable {
    case automatic
    case physical
    case virtual
}

@MainActor
@Observable
public final class NotchShellDebugModel {
    public var displaySource: NotchDebugDisplaySource = .live { didSet { changed() } }
    public var surfaceMode: NotchDebugSurfaceMode = .automatic { didSet { changed() } }
    public var presentation: NotchStableState = .collapsed { didSet { changed() } }
    public var appearance: NotchAppearanceOverride = .system { didSet { changed() } }
    public var reduceMotion: NotchAccessibilityOverride = .system { didSet { changed() } }
    public var reduceTransparency: NotchAccessibilityOverride = .system { didSet { changed() } }
    public private(set) var revision = 0

    public init(arguments: [String] = CommandLine.arguments) {
        apply(arguments: arguments)
    }

    public var renderConfiguration: NotchShellRenderConfiguration {
        NotchShellRenderConfiguration(
            appearance: appearance,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        )
    }

    public func resetToAutomatic() {
        displaySource = .live
        surfaceMode = .automatic
        presentation = .collapsed
        appearance = .system
        reduceMotion = .system
        reduceTransparency = .system
    }

    public func snapshots(live: [NotchiumDisplaySnapshot]) -> [NotchiumDisplaySnapshot] {
        switch displaySource {
        case .live:
            live
        case .builtInMock:
            [Self.builtInFixture(projectedOnto: live.first)]
        case .externalMock:
            [Self.externalFixture(projectedOnto: live.first)]
        }
    }

    public func override(placement: NotchShellPlacement?) -> NotchShellPlacement? {
        guard let placement else { return nil }
        switch surfaceMode {
        case .automatic:
            return placement
        case .physical:
            return NotchShellPlacement(display: placement.display, mode: .physicalNotch)
        case .virtual:
            return NotchShellPlacement(display: placement.display, mode: .virtualPill)
        }
    }

    public static let builtInFixture = NotchiumDisplaySnapshot(
        id: NotchiumDisplayID(rawValue: 1),
        name: "Built-in mock display",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: NotchiumDisplayInsets(top: 38),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 650, height: 38),
        auxiliaryTopRightArea: CGRect(x: 862, y: 944, width: 650, height: 38),
        isBuiltIn: true,
        isPrimary: true
    )

    public static let externalFixture = NotchiumDisplaySnapshot(
        id: NotchiumDisplayID(rawValue: 2),
        name: "External mock display",
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        isBuiltIn: false,
        isPrimary: true
    )

    private static func builtInFixture(
        projectedOnto liveDisplay: NotchiumDisplaySnapshot?
    ) -> NotchiumDisplaySnapshot {
        guard let liveDisplay else { return builtInFixture }

        let frame = liveDisplay.frame
        let safeAreaTop = min(38, frame.height)
        let notchWidth = min(212, max(1, frame.width * 0.15))
        let notchMinX = frame.midX - notchWidth / 2
        let notchMaxX = frame.midX + notchWidth / 2
        let auxiliaryY = frame.maxY - safeAreaTop

        return NotchiumDisplaySnapshot(
            id: builtInFixture.id,
            name: builtInFixture.name,
            frame: frame,
            visibleFrame: liveDisplay.visibleFrame,
            safeAreaInsets: NotchiumDisplayInsets(top: safeAreaTop),
            auxiliaryTopLeftArea: CGRect(
                x: frame.minX,
                y: auxiliaryY,
                width: max(0, notchMinX - frame.minX),
                height: safeAreaTop
            ),
            auxiliaryTopRightArea: CGRect(
                x: notchMaxX,
                y: auxiliaryY,
                width: max(0, frame.maxX - notchMaxX),
                height: safeAreaTop
            ),
            isBuiltIn: true,
            isPrimary: true,
            backingScaleFactor: liveDisplay.backingScaleFactor
        )
    }

    private static func externalFixture(
        projectedOnto liveDisplay: NotchiumDisplaySnapshot?
    ) -> NotchiumDisplaySnapshot {
        guard let liveDisplay else { return externalFixture }

        return NotchiumDisplaySnapshot(
            id: externalFixture.id,
            name: externalFixture.name,
            frame: liveDisplay.frame,
            visibleFrame: liveDisplay.visibleFrame,
            isBuiltIn: false,
            isPrimary: true,
            backingScaleFactor: liveDisplay.backingScaleFactor
        )
    }

    private func apply(arguments: [String]) {
        for (index, argument) in arguments.enumerated() {
            guard index + 1 < arguments.count else { continue }
            let value = arguments[index + 1]
            switch argument {
            case "--notchium-display":
                displaySource = NotchDebugDisplaySource(rawValue: value) ?? displaySource
            case "--notchium-surface":
                surfaceMode = NotchDebugSurfaceMode(rawValue: value) ?? surfaceMode
            case "--notchium-presentation":
                presentation = NotchStableState(rawValue: value) ?? presentation
            case "--notchium-appearance":
                appearance = NotchAppearanceOverride(rawValue: value) ?? appearance
            case "--notchium-reduce-motion":
                reduceMotion = NotchAccessibilityOverride(rawValue: value) ?? reduceMotion
            case "--notchium-reduce-transparency":
                reduceTransparency = NotchAccessibilityOverride(rawValue: value) ?? reduceTransparency
            default:
                continue
            }
        }
        revision = 0
    }

    private func changed() {
        revision &+= 1
    }
}
#endif
