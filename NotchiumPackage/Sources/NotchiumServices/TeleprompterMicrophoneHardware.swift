import CoreAudio
import Foundation

/// Public metadata only. Enumerating choices never opens or records a microphone.
enum TeleprompterMicrophoneHardware {
    struct Device: Sendable {
        let objectID: AudioObjectID
        let microphone: TeleprompterMicrophone
    }

    static func devices() -> [Device] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let defaultInput: UInt32? = integer(system, selector: kAudioHardwarePropertyDefaultInputDevice)
        var address = property(kAudioHardwarePropertyDevices)
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &byteCount) == noErr,
              byteCount > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(byteCount) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &byteCount, &ids) == noErr else { return [] }
        return ids.compactMap { id -> Device? in
            guard integer(id, selector: kAudioDevicePropertyDeviceIsAlive) == 1,
                  integer(id, selector: kAudioDevicePropertyIsHidden) != 1,
                  hasInputStreams(id),
                  let uid = string(id, selector: kAudioDevicePropertyDeviceUID),
                  let name = string(id, selector: kAudioObjectPropertyName) else { return nil }
            return Device(objectID: id, microphone: .init(id: uid, name: name, isDefault: id == defaultInput))
        }.sorted {
            if $0.microphone.isDefault != $1.microphone.isDefault { return $0.microphone.isDefault }
            return $0.microphone.name.localizedStandardCompare($1.microphone.name) == .orderedAscending
        }
    }

    static func name(for objectID: AudioObjectID) -> String? {
        string(objectID, selector: kAudioObjectPropertyName)
    }

    private static func hasInputStreams(_ id: AudioObjectID) -> Bool {
        var address = property(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var byteCount: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &byteCount) == noErr && byteCount > 0
    }

    private static func integer(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = property(selector)
        var value: UInt32 = 0
        var byteCount = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &byteCount, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = property(selector)
        var value: Unmanaged<CFString>?
        var byteCount = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &byteCount, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func property(_ selector: AudioObjectPropertySelector,
                                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
