import AppKit
import SwiftUI

public struct NotchAudioHUD: Equatable, Sendable {
    /// `outputChanged`: a device connected or became the active output (shown as "Connected").
    /// `deviceDisconnected`: the active output or a wearable went away.
    public enum Kind: Equatable, Sendable { case volume, outputChanged, deviceDisconnected }
    public let kind: Kind
    public let deviceName: String
    public let volume: Double?
    public let isMuted: Bool
    public let deviceStyle: NotchDeviceStyle
    /// Stable device identity, so a different device is never treated as a repeat.
    public let deviceID: String?
    /// Only a fresh, source-reported aggregate level; nil means "do not show a battery".
    public let battery: NotchDeviceBattery?

    public init(kind: Kind, deviceName: String, volume: Double?, isMuted: Bool,
                deviceStyle: NotchDeviceStyle = .speaker, deviceID: String? = nil,
                battery: NotchDeviceBattery? = nil) {
        self.kind = kind
        self.deviceName = deviceName
        self.volume = volume
        self.isMuted = isMuted
        self.deviceStyle = deviceStyle
        self.deviceID = deviceID
        self.battery = battery
    }

    public var isDeviceTransition: Bool { kind != .volume }
}

public struct NotchDeviceBattery: Equatable, Sendable {
    public let level: Double
    public let isCharging: Bool
    public init(level: Double, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
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
    public func begin() { begin(source: "feature") }

    @MainActor
    public func begin(source: String) {
        storage.model?.setAuxiliaryInteractionPresented(true, source: source)
    }

    @MainActor
    public func end(actionSelected: Bool) { end(actionSelected: actionSelected, source: "feature") }

    @MainActor
    public func end(actionSelected: Bool, source: String) {
        storage.model?.endAuxiliaryInteraction(actionSelected: actionSelected, source: source)
    }

    @MainActor
    public func handleEscape() { storage.model?.handleEscape() }

    @MainActor
    public func beginNativeSharing(in window: NSWindow?, source: String) {
        begin(source: source)
        (window as? NotchPanel)?.setNativeSharingPresented(true, source: source)
    }

    @MainActor
    public func endNativeSharing(in window: NSWindow?, source: String,
                                 returnsToOpenSession: Bool = false) {
        (window as? NotchPanel)?.setNativeSharingPresented(false, source: source)
        storage.model?.endAuxiliaryInteraction(actionSelected: false, source: source,
                                              returnsToOpenSession: returnsToOpenSession)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage === rhs.storage
    }
}

extension EnvironmentValues {
    @Entry public var notchAudioPageVisible = false
    @Entry public var notchAuxiliaryInteraction = NotchAuxiliaryInteractionHandler()
}
