import CoreAudio
import Foundation
import NotchiumCore

public struct AudioDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isDefaultOutput: Bool
    public let volume: Double?
    public let isMuted: Bool?
    public let canSetVolume: Bool
    public let canSetMute: Bool

    public init(id: String, name: String, isDefaultOutput: Bool,
                volume: Double? = nil, isMuted: Bool? = nil,
                canSetVolume: Bool = false, canSetMute: Bool = false) {
        self.id = id
        self.name = name
        self.isDefaultOutput = isDefaultOutput
        self.volume = volume
        self.isMuted = isMuted
        self.canSetVolume = canSetVolume
        self.canSetMute = canSetMute
    }
}

public struct AudioDevicesSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let outputs: [AudioDevice]
    public var currentOutput: AudioDevice? { outputs.first(where: \.isDefaultOutput) }

    public init(availability: FeatureAvailability, outputs: [AudioDevice] = []) {
        self.availability = availability
        self.outputs = outputs
    }
}

public protocol AudioDevicesService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<AudioDevicesSnapshot>
    func selectOutput(id: String) async throws
    func setVolume(_ volume: Double, deviceID: String) async throws
    func setMuted(_ muted: Bool, deviceID: String) async throws
}

/// Listens to HAL device, default-output, volume, and mute events.
@MainActor
public final class RealAudioDevicesService: AudioDevicesService {
    private struct Listener {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private struct OutputDetails {
        let name: String
        let canSetVolume: Bool
        let canSetMute: Bool
    }
    private var systemListeners: [Listener] = []
    private var outputListeners: [Listener] = []
    private var observers: [UUID: AsyncStream<AudioDevicesSnapshot>.Continuation] = [:]
    private var selectedID: AudioObjectID = kAudioObjectUnknown
    private var previous: AudioDevicesSnapshot?
    private var cachedOutputIDs: [AudioObjectID] = []
    private var outputDetails: [AudioObjectID: OutputDetails] = [:]

    public init() {}
    public func availability() async -> FeatureAvailability { .available }

    public func updates() async -> AsyncStream<AudioDevicesSnapshot> {
        let token = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observers[token] = continuation
            if systemListeners.isEmpty { start() }
            continuation.yield(previous ?? snapshot())
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.removeObserver(token) }
            }
        }
    }

    public func selectOutput(id: String) async throws {
        guard let id = UInt32(id), cachedOutputIDs.contains(id) else {
            throw ServiceFailure.unsupportedOperation(.audioDevices)
        }
        var value = id
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value)
        guard status == noErr else { throw ServiceFailure.unavailable(.audioDevices) }
    }

    public func setVolume(_ volume: Double, deviceID: String) async throws {
        guard let id = UInt32(deviceID), id == defaultOutputID() else {
            throw ServiceFailure.unsupportedOperation(.audioDevices)
        }
        var value = Float32(min(max(volume, 0), 1))
        let addresses = Self.writableControlAddresses(id, kAudioDevicePropertyVolumeScalar)
        guard !addresses.isEmpty else { throw ServiceFailure.unsupportedOperation(.audioDevices) }
        for var address in addresses {
            guard AudioObjectSetPropertyData(id, &address, 0, nil,
                                             UInt32(MemoryLayout.size(ofValue: value)), &value) == noErr else {
                throw ServiceFailure.unavailable(.audioDevices)
            }
        }
    }

    public func setMuted(_ muted: Bool, deviceID: String) async throws {
        guard let id = UInt32(deviceID), id == defaultOutputID() else {
            throw ServiceFailure.unsupportedOperation(.audioDevices)
        }
        var value: UInt32 = muted ? 1 : 0
        let addresses = Self.writableControlAddresses(id, kAudioDevicePropertyMute)
        guard !addresses.isEmpty else { throw ServiceFailure.unsupportedOperation(.audioDevices) }
        for var address in addresses {
            guard AudioObjectSetPropertyData(id, &address, 0, nil,
                                             UInt32(MemoryLayout.size(ofValue: value)), &value) == noErr else {
                throw ServiceFailure.unavailable(.audioDevices)
            }
        }
    }

    private func start() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        addListener(system, Self.address(kAudioHardwarePropertyDevices), to: &systemListeners)
        addListener(system, Self.address(kAudioHardwarePropertyDefaultOutputDevice), to: &systemListeners)
        refresh()
    }

    private func removeObserver(_ token: UUID) {
        observers[token] = nil
        guard observers.isEmpty else { return }
        systemListeners.forEach(Self.remove)
        outputListeners.forEach(Self.remove)
        systemListeners.removeAll()
        outputListeners.removeAll()
        selectedID = kAudioObjectUnknown
        previous = nil
        cachedOutputIDs = []
        outputDetails = [:]
    }

    private func refresh(rebuildDevices: Bool = false) {
        if rebuildDevices || cachedOutputIDs.isEmpty {
            cachedOutputIDs = outputIDs()
            outputDetails = Dictionary(uniqueKeysWithValues: cachedOutputIDs.map { id in
                (id, OutputDetails(name: Self.name(id) ?? "Audio Output",
                                   canSetVolume: !Self.writableControlAddresses(id, kAudioDevicePropertyVolumeScalar).isEmpty,
                                   canSetMute: !Self.writableControlAddresses(id, kAudioDevicePropertyMute).isEmpty))
            })
        }
        let id = defaultOutputID()
        if id != selectedID {
            outputListeners.forEach(Self.remove)
            outputListeners.removeAll()
            selectedID = id
            if id != kAudioObjectUnknown {
                for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                    for element in 0...min(Self.outputChannelCount(id), 32) {
                        var address = Self.address(selector, scope: kAudioDevicePropertyScopeOutput,
                                                   element: AudioObjectPropertyElement(element))
                        if AudioObjectHasProperty(id, &address) {
                            addListener(id, address, to: &outputListeners)
                        }
                    }
                }
            }
        }
        let next = snapshot()
        guard next != previous else { return }
        previous = next
        observers.values.forEach { $0.yield(next) }
    }

    private func addListener(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress,
                             to target: inout [Listener]) {
        var address = property
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh(rebuildDevices: property.mSelector == kAudioHardwarePropertyDevices)
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            target.append(Listener(object: object, address: address, block: block))
        }
    }

    private static func remove(_ listener: Listener) {
        var address = listener.address
        AudioObjectRemovePropertyListenerBlock(listener.object, &address, .main, listener.block)
    }

    private func snapshot() -> AudioDevicesSnapshot {
        let selected = defaultOutputID()
        let outputs = cachedOutputIDs.map { id in
            let details = outputDetails[id]
            return AudioDevice(id: String(id), name: details?.name ?? "Audio Output",
                        isDefaultOutput: id == selected,
                        volume: Self.scalar(id), isMuted: Self.muted(id),
                        canSetVolume: details?.canSetVolume ?? false,
                        canSetMute: details?.canSetMute ?? false)
        }.sorted { a, b in
            a.isDefaultOutput == b.isDefaultOutput
                ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                : a.isDefaultOutput
        }
        return AudioDevicesSnapshot(availability: .available, outputs: outputs)
    }

    private func defaultOutputID() -> AudioObjectID {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout.size(ofValue: id))
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                          0, nil, &size, &id) == noErr ? id : kAudioObjectUnknown
    }

    private func outputIDs() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            Self.hasOutput(id)
                && AudioDeviceVisibility.isUserVisible(uid: Self.deviceUID(id))
        }
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration,
                                   scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return false }
        return UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
            .contains { $0.mNumberChannels > 0 }
    }

    private static func writableControlAddresses(_ id: AudioObjectID,
                                                 _ selector: AudioObjectPropertySelector) -> [AudioObjectPropertyAddress] {
        if let master = controlAddress(id, selector, writable: true),
           master.mElement == kAudioObjectPropertyElementMain { return [master] }
        let channels = min(outputChannelCount(id), 32)
        guard channels > 0 else { return [] }
        let addresses = (1...channels).compactMap { element -> AudioObjectPropertyAddress? in
            var address = Self.address(selector,
                                       scope: kAudioDevicePropertyScopeOutput,
                                       element: AudioObjectPropertyElement(element))
            var settable = DarwinBoolean(false)
            return AudioObjectHasProperty(id, &address)
                && AudioObjectIsPropertySettable(id, &address, &settable) == noErr
                && settable.boolValue ? address : nil
        }
        return addresses.count == channels ? addresses : []
    }

    private static func outputChannelCount(_ id: AudioObjectID) -> Int {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration,
                                   scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func name(_ id: AudioObjectID) -> String? {
        var address = Self.address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func deviceUID(_ id: AudioObjectID) -> String? {
        ProcessTapSupport.stringProperty(id, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func scalar(_ id: AudioObjectID) -> Double? {
        guard var address = controlAddress(id, kAudioDevicePropertyVolumeScalar) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr
            ? Double(value) : nil
    }

    private static func muted(_ id: AudioObjectID) -> Bool? {
        guard var address = controlAddress(id, kAudioDevicePropertyMute) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr
            ? value != 0 : nil
    }

    private static func controlAddress(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                       writable: Bool = false) -> AudioObjectPropertyAddress? {
        for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)] {
            var address = Self.address(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
            guard AudioObjectHasProperty(id, &address) else { continue }
            if !writable { return address }
            var settable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue {
                return address
            }
        }
        return nil
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
}

public struct MockAudioDevicesService: AudioDevicesService {
    public let snapshot: AudioDevicesSnapshot
    public init(snapshot: AudioDevicesSnapshot = AudioDevicesSnapshot(availability: .available)) {
        self.snapshot = snapshot
    }
    public func availability() async -> FeatureAvailability { snapshot.availability }
    public func updates() async -> AsyncStream<AudioDevicesSnapshot> { oneShotStream(snapshot) }
    public func selectOutput(id: String) async throws {}
    public func setVolume(_ volume: Double, deviceID: String) async throws {}
    public func setMuted(_ muted: Bool, deviceID: String) async throws {}
}
