import CoreAudio
import Foundation

/// Stateless HAL access shared by the device service and its serial hardware-key worker.
/// Core Audio object IDs are revalidated against the default route before every operation.
struct CoreAudioOutputControls: VolumeKeyHardware {
    func defaultOutputID() -> UInt32 {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        return Self.value(AudioObjectID(kAudioObjectSystemObject), address: &address, initial: UInt32(0)) ?? 0
    }

    func read(_ deviceID: UInt32) -> VolumeHardwareState? {
        guard deviceID != 0 else { return nil }
        let volumeElements = Self.writableElements(deviceID, kAudioDevicePropertyVolumeScalar)
        let values = volumeElements.compactMap { element -> Double? in
            var address = Self.address(kAudioDevicePropertyVolumeScalar, element: element)
            guard let value: Float32 = Self.value(deviceID, address: &address, initial: Float32(0)),
                  value.isFinite, (0...1).contains(value) else { return nil }
            return Double(value)
        }
        let muteElements = Self.writableElements(deviceID, kAudioDevicePropertyMute)
        let mutes = muteElements.compactMap { element -> Bool? in
            var address = Self.address(kAudioDevicePropertyMute, element: element)
            return Self.value(deviceID, address: &address, initial: UInt32(0)).map { $0 != 0 }
        }
        return VolumeHardwareState(deviceID: deviceID, volumeElements: volumeElements,
            volumes: values.count == volumeElements.count ? values : [], muteElements: muteElements,
            muted: !mutes.isEmpty && mutes.count == muteElements.count ? mutes.contains(true) : nil)
    }

    func writeVolume(_ values: [Double], state: VolumeHardwareState) -> Bool {
        guard values.count == state.volumeElements.count, !values.isEmpty else { return false }
        for (element, scalar) in zip(state.volumeElements, values) {
            guard scalar.isFinite, (0...1).contains(scalar) else { return false }
            var value = Float32(scalar)
            var address = Self.address(kAudioDevicePropertyVolumeScalar, element: element)
            guard AudioObjectSetPropertyData(state.deviceID, &address, 0, nil, 4, &value) == noErr else { return false }
        }
        return true
    }

    func writeMute(_ muted: Bool, state: VolumeHardwareState) -> Bool {
        guard state.supportsMute else { return false }
        for element in state.muteElements {
            var value: UInt32 = muted ? 1 : 0
            var address = Self.address(kAudioDevicePropertyMute, element: element)
            guard AudioObjectSetPropertyData(state.deviceID, &address, 0, nil, 4, &value) == noErr else { return false }
        }
        return true
    }

    static func writableElements(_ id: UInt32, _ selector: UInt32) -> [UInt32] {
        func writable(_ element: UInt32) -> Bool {
            var address = Self.address(selector, element: element)
            var settable = DarwinBoolean(false)
            return AudioObjectHasProperty(id, &address)
                && AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
        }
        if writable(kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        let channels = channelCount(id)
        guard channels > 0, channels <= 32 else { return [] }
        let elements = (1...UInt32(channels)).filter(writable)
        return elements.count == channels ? elements : []
    }

    static func channelCount(_ id: UInt32) -> Int {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func value<T>(_ id: UInt32, address: inout AudioObjectPropertyAddress, initial: T) -> T? {
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr ? pointer.pointee : nil
        }
    }

    private static func address(_ selector: UInt32, scope: UInt32 = kAudioDevicePropertyScopeOutput,
                                element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: element)
    }
}
