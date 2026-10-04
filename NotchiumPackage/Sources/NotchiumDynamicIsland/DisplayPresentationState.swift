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
    private var directDisplayID: NotchiumDisplayID?

    public var geometry: NotchiumDisplaySnapshot? {
        availableDisplays.first { $0.id == ownedDisplayID }
    }

    /// Stage 21 does not synthesize hardware on an external/notchless screen.
    public var shellPlacement: NotchShellPlacement? {
        guard let geometry, geometry.isBuiltIn,
              geometry.isEligiblePhysicalNotchDisplay, geometry.physicalNotchGap != nil else { return nil }
        return .init(display: geometry, mode: .physicalNotch)
    }

    mutating func rebuild(_ displays: [NotchiumDisplaySnapshot], evidence: DisplayInteractionEvidence) {
        // Online CG IDs may be reused for a different physical monitor. A changed public
        // UUID invalidates the prior owner's lease even if its numeric ID was recycled.
        if let previous = geometry,
           let replacement = displays.first(where: { $0.id == previous.id }),
           previous.persistentID != replacement.persistentID {
            directDisplayID = nil
            ownedDisplayID = nil
        }
        if displays != availableDisplays {
            topologyGeneration &+= 1
            availableDisplays = displays
        }
        if !displays.contains(where: { $0.id == directDisplayID }) { directDisplayID = nil }
        resolve(evidence)
    }

    mutating func interact(on displayID: NotchiumDisplayID, evidence: DisplayInteractionEvidence) {
        guard availableDisplays.contains(where: { $0.id == displayID }) else { return }
        directDisplayID = displayID
        resolve(evidence)
    }

    mutating func releaseDirectOwnership() { directDisplayID = nil }

    mutating func resolve(_ evidence: DisplayInteractionEvidence) {
        let pointer = evidence.pointerLocation.flatMap { point in
            availableDisplays.first { $0.frame.contains(point) }?.id
        }
        let candidates = [directDisplayID, pointer, evidence.frontmostDisplayID,
                          ownedDisplayID, availableDisplays.first(where: \.isPrimary)?.id,
                          availableDisplays.first?.id]
        ownedDisplayID = candidates.compactMap { $0 }.first { id in
            availableDisplays.contains { $0.id == id }
        }
        if sleeping { presentationContext = .sleeping; return }
        // System presentation options describe the active application. Apply them only to
        // its display; fullscreen on a different monitor must not quiet this desktop.
        let contextDisplay = evidence.fullscreenDisplayID ?? evidence.frontmostDisplayID
        guard contextDisplay == ownedDisplayID, ownedDisplayID != nil else {
            presentationContext = .normal
            return
        }
        if evidence.isPresentationLike { presentationContext = .presentationLike }
        else if evidence.isImmersiveMedia { presentationContext = .immersiveMedia }
        else if evidence.isFullscreen { presentationContext = .fullscreenApp }
        else { presentationContext = .normal }
    }

    mutating func setSleeping(_ sleeping: Bool, evidence: DisplayInteractionEvidence) {
        guard self.sleeping != sleeping else { return }
        self.sleeping = sleeping
        // Invalidates evidence captured before sleep, including when geometry is unchanged.
        topologyGeneration &+= 1
        resolve(evidence)
    }
}
