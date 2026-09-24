import SwiftUI

public struct NotchAudioHUD: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case volume, outputChanged }
    public let kind: Kind
    public let deviceName: String
    public let volume: Double?
    public let isMuted: Bool

    public init(kind: Kind, deviceName: String, volume: Double?, isMuted: Bool) {
        self.kind = kind
        self.deviceName = deviceName
        self.volume = volume
        self.isMuted = isMuted
    }
}

@MainActor public protocol NotchAudioRendering: AnyObject {
    func expandedAudio() -> AnyView
    func setPageVisible(_ visible: Bool)
}

public struct NotchAuxiliaryInteractionHandler: Equatable {
    private final class Storage {
        weak var model: DynamicIslandPresentationModel?
        init(model: DynamicIslandPresentationModel?) { self.model = model }
    }

    private let storage: Storage

    public init() { storage = Storage(model: nil) }

    @MainActor
    init(model: DynamicIslandPresentationModel) {
        storage = Storage(model: model)
    }

    @MainActor
    public func begin() {
        storage.model?.setAuxiliaryInteractionPresented(true)
    }

    @MainActor
    public func end(actionSelected: Bool) {
        storage.model?.endAuxiliaryInteraction(actionSelected: actionSelected)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage === rhs.storage
    }
}

extension EnvironmentValues {
    @Entry public var notchAudioPageVisible = false
    @Entry public var notchAuxiliaryInteraction = NotchAuxiliaryInteractionHandler()
}
