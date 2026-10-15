import Foundation

/// Environmental policy only; activity ranking and page navigation have separate owners.
/// The one normalized classification every presentation consumer reads.
public enum NotchPresentationContext: Equatable, Sendable {
    case normal
    /// A fullscreen Space that is not playing media: Notchium behaves normally.
    case fullscreenApp
    /// Fullscreen whose app keeps the display awake (video playback): routine notices stay quiet.
    case immersiveMedia
    /// Menu bar and Dock/process switching locked away (slideshows, kiosks): essentials only.
    case presentationLike
    case sleeping
}

/// Public system evidence projected by the AppKit boundary. No app names or window titles.
struct DisplayInteractionEvidence: Equatable, Sendable {
    var pointerLocation: CGPoint?
    var frontmostDisplayID: NotchiumDisplayID?
    var fullscreenDisplayID: NotchiumDisplayID?
    var isFullscreen = false
    var isImmersiveMedia = false
    var isPresentationLike = false
}

public struct DisplayPresentationState: Equatable, Sendable {
    public private(set) var topologyGeneration: UInt64 = 0
    public private(set) var availableDisplays: [NotchiumDisplaySnapshot] = []
    public private(set) var ownedDisplayID: NotchiumDisplayID?
    public private(set) var presentationContext: NotchPresentationContext = .normal
    public private(set) var sleeping = false
    public var preferences = NotchDisplayPreferences()

    public var geometry: NotchiumDisplaySnapshot? {
        availableDisplays.first { $0.id == ownedDisplayID }
    }

    public var shellPlacements: [NotchShellPlacement] {
        NotchDisplayPlacementPolicy.placements(displays: availableDisplays, preferences: preferences)
    }

    public var shellPlacement: NotchShellPlacement? {
        shellPlacements.first
    }

    mutating func rebuild(_ displays: [NotchiumDisplaySnapshot], evidence: DisplayInteractionEvidence) {
        if displays != availableDisplays {
            topologyGeneration &+= 1
            availableDisplays = displays
        }
        resolve(evidence)
    }

    mutating func resolve(_ evidence: DisplayInteractionEvidence) {
        ownedDisplayID = shellPlacement?.display.id
        presentationContext = context(for: ownedDisplayID, evidence: evidence)
    }

    func context(for displayID: NotchiumDisplayID?, evidence: DisplayInteractionEvidence) -> NotchPresentationContext {
        if sleeping { return .sleeping }
        // System presentation options describe the active application. Apply them only to
        // its display; fullscreen on a different monitor must not quiet this desktop.
        let contextDisplay = evidence.fullscreenDisplayID ?? evidence.frontmostDisplayID
        guard contextDisplay == displayID, displayID != nil else { return .normal }
        if evidence.isPresentationLike { return .presentationLike }
        if evidence.isImmersiveMedia { return .immersiveMedia }
        if evidence.isFullscreen { return .fullscreenApp }
        return .normal
    }

    mutating func setSleeping(_ sleeping: Bool, evidence: DisplayInteractionEvidence) {
        guard self.sleeping != sleeping else { return }
        self.sleeping = sleeping
        // Invalidates evidence captured before sleep, including when geometry is unchanged.
        topologyGeneration &+= 1
        resolve(evidence)
    }
}
