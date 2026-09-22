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

extension EnvironmentValues {
    @Entry public var notchAudioPageVisible = false
}
