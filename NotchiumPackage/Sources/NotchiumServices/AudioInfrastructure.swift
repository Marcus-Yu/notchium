import CoreAudio
import Foundation

enum NotchiumAudioInfrastructure {
    static let appMixerDeviceUID = "com.marcusyu.notchium.app-mixer"
    static let legacyAppMixerDeviceUIDPrefix = "\(appMixerDeviceUID)."
    static let spotifyTapDeviceUIDPrefix = "com.marcusyu.notchium.spotify-tap."

    static func ownsAudioDevice(uid: String?) -> Bool {
        guard let uid else { return false }
        return uid == appMixerDeviceUID
            || uid.hasPrefix(legacyAppMixerDeviceUIDPrefix)
            || uid.hasPrefix(spotifyTapDeviceUIDPrefix)
    }
}

enum AudioDeviceVisibility {
    static func isUserVisible(uid: String?) -> Bool {
        !NotchiumAudioInfrastructure.ownsAudioDevice(uid: uid)
    }
}

enum ProcessTapSupport {
    static func isMixerInputFormat(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mBitsPerChannel == 32
            && format.mBytesPerFrame > 0
            && format.mChannelsPerFrame == 2
    }

    static func canCreateTap(processObjectID: AudioObjectID, deviceID: AudioObjectID) -> Bool {
        guard let deviceUID = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) else {
            return false
        }
        let description = CATapDescription(processes: [processObjectID],
                                           deviceUID: deviceUID,
                                           stream: 0)
        description.name = "Notchium Eligibility Probe"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.isProcessRestoreEnabled = false

        var tapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return false }
        defer { AudioHardwareDestroyProcessTap(tapID) }

        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr else {
            return false
        }
        return isMixerInputFormat(format)
    }

    static func stringProperty(_ object: AudioObjectID,
                               selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value?.takeRetainedValue() as String?
    }
}
