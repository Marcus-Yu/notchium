import CoreAudio
import Foundation
import NotchiumRealtimeAudio

public struct AppAudioMixTarget: Equatable, Sendable {
    public let processID: Int32
    public let bundleID: String
    public let volume: Double
    public let isMuted: Bool

    public init(processID: Int32, bundleID: String, volume: Double, isMuted: Bool) {
        self.processID = processID
        self.bundleID = bundleID
        self.volume = volume
        self.isMuted = isMuted
    }
}

public enum AppAudioMixerStatus: Equatable, Sendable {
    case inactive
    case running
    case permissionRequired
    case unavailable
}

public protocol AppAudioMixerService: Sendable {
    func apply(targets: [AppAudioMixTarget], outputDeviceID: String?) async -> AppAudioMixerStatus
    func stop() async
}

@MainActor
public final class RealAppAudioMixerService: AppAudioMixerService {
    private var engine: ProcessTapMixEngine?
    public init() {}

    public func apply(targets: [AppAudioMixTarget], outputDeviceID: String?) async -> AppAudioMixerStatus {
        let adjusted = targets
            .filter { $0.isMuted || $0.volume < 0.999 }
            .sorted { lhs, rhs in
                lhs.bundleID == rhs.bundleID ? lhs.processID < rhs.processID : lhs.bundleID < rhs.bundleID
            }
        guard !adjusted.isEmpty else {
            engine?.stop()
            engine = nil
            return .inactive
        }
        guard let outputDeviceID, let outputID = UInt32(outputDeviceID) else {
            engine?.stop()
            engine = nil
            return .unavailable
        }

        let topology = adjusted.map { ProcessTapMixEngine.Target(processID: $0.processID,
                                                                 bundleID: $0.bundleID) }
        if let engine, engine.matches(targets: topology, outputDeviceID: outputID) {
            engine.updateGains(adjusted)
            return .running
        }

        // Stopping the IOProc first releases mutedWhenTapped before any tap is destroyed.
        engine?.stop()
        engine = nil
        let replacement = ProcessTapMixEngine(targets: topology, outputDeviceID: outputID)
        do {
            try replacement.start(gains: adjusted)
            engine = replacement
            return .running
        } catch ProcessTapMixError.permissionDenied {
            replacement.stop()
            return .permissionRequired
        } catch {
            replacement.stop()
            return .unavailable
        }
    }

    public func stop() async {
        engine?.stop()
        engine = nil
    }
}

public actor MockAppAudioMixerService: AppAudioMixerService {
    public private(set) var targets: [AppAudioMixTarget] = []
    public private(set) var outputDeviceID: String?
    public var status: AppAudioMixerStatus
    public init(status: AppAudioMixerStatus = .running) { self.status = status }
    public func apply(targets: [AppAudioMixTarget], outputDeviceID: String?) -> AppAudioMixerStatus {
        self.targets = targets.filter { $0.isMuted || $0.volume < 0.999 }
        self.outputDeviceID = outputDeviceID
        return self.targets.isEmpty ? .inactive : status
    }
    public func stop() { targets = []; outputDeviceID = nil }
}

private enum ProcessTapMixError: Error {
    case permissionDenied
    case coreAudio(OSStatus)
    case unsupportedFormat
    case processUnavailable
}

/// Immutable topology with preallocated atomic gain slots. Only gain atomics are touched in place.
/// This object is reachable only through `RealAppAudioMixerService` on MainActor. The HAL block
/// captures only immutable scalars and the stable C slot pointer, never this object.
private final class ProcessTapMixEngine: @unchecked Sendable {
    struct Target: Equatable, Hashable {
        let processID: Int32
        let bundleID: String
    }

    private let targets: [Target]
    private let outputDeviceID: AudioObjectID
    private var tapIDs: [AudioObjectID] = []
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var deviceStarted = false
    private var slots: UnsafeMutablePointer<NTAudioGainSlot>?

    init(targets: [Target], outputDeviceID: AudioObjectID) {
        self.targets = targets
        self.outputDeviceID = outputDeviceID
    }

    func matches(targets: [Target], outputDeviceID: AudioObjectID) -> Bool {
        self.targets == targets && self.outputDeviceID == outputDeviceID
    }

    func start(gains: [AppAudioMixTarget]) throws {
        guard tapIDs.isEmpty else { updateGains(gains); return }
        do {
            let outputUID = try Self.stringProperty(outputDeviceID, kAudioDevicePropertyDeviceUID)
            var descriptions: [CATapDescription] = []
            for target in targets {
                guard let process = try AudioHardwareSystem.shared.process(for: target.processID) else {
                    throw ProcessTapMixError.processUnavailable
                }
                let description = CATapDescription(processes: [process.id], deviceUID: outputUID, stream: 0)
                description.name = "Notchium \(target.bundleID)"
                description.isPrivate = true
                description.muteBehavior = .mutedWhenTapped
                description.isProcessRestoreEnabled = true
                description.bundleIDs = [target.bundleID]
                var tapID = AudioObjectID(kAudioObjectUnknown)
                try Self.check(AudioHardwareCreateProcessTap(description, &tapID))
                tapIDs.append(tapID)
                descriptions.append(description)
            }

            guard let firstTap = tapIDs.first else { return }
            let tapFormat = try Self.format(firstTap, selector: kAudioTapPropertyFormat,
                                            scope: kAudioObjectPropertyScopeGlobal)
            guard ProcessTapSupport.isMixerInputFormat(tapFormat) else {
                throw ProcessTapMixError.unsupportedFormat
            }
            let inputNI = tapFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0

            let subdevice: [String: Any] = [
                kAudioSubDeviceUIDKey: outputUID,
                kAudioSubDeviceInputChannelsKey: 0,
            ]
            let subtaps: [[String: Any]] = descriptions.map {
                [kAudioSubTapUIDKey: $0.uuid.uuidString,
                 kAudioSubTapDriftCompensationKey: true]
            }
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Notchium App Mixer",
                kAudioAggregateDeviceUIDKey: NotchiumAudioInfrastructure.appMixerDeviceUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceSubDeviceListKey: [subdevice],
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: subtaps,
            ]
            try Self.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary,
                                                               &aggregateDeviceID))

            let outputFormat = try Self.format(aggregateDeviceID,
                                               selector: kAudioDevicePropertyStreamFormat,
                                               scope: kAudioDevicePropertyScopeOutput)
            try Self.validateFloat32(outputFormat)
            guard outputFormat.mChannelsPerFrame >= 2 else { throw ProcessTapMixError.unsupportedFormat }
            let outputNI = outputFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0

            let allocated = UnsafeMutablePointer<NTAudioGainSlot>.allocate(capacity: targets.count)
            NTAudioGainSlotsInitialize(allocated, UInt32(targets.count))
            slots = allocated
            updateGains(gains)

            let slotCount = UInt32(targets.count)
            try Self.check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, nil) {
                _, inputData, _, outputData, _ in
                NTAudioMixFloat32(inputData, outputData, allocated, slotCount, inputNI, outputNI)
            })
            guard let ioProcID else { throw ProcessTapMixError.coreAudio(-1) }
            try Self.check(AudioDeviceStart(aggregateDeviceID, ioProcID))
            deviceStarted = true
        } catch {
            stop()
            throw error
        }
    }

    func updateGains(_ gains: [AppAudioMixTarget]) {
        guard let slots else { return }
        let byIdentity = Dictionary(uniqueKeysWithValues: gains.map {
            (Target(processID: $0.processID, bundleID: $0.bundleID), $0)
        })
        for (index, target) in targets.enumerated() {
            let setting = byIdentity[target]
            let gain = setting?.isMuted == true ? 0 : Float(min(max(setting?.volume ?? 1, 0), 1))
            NTAudioGainSlotSet(slots.advanced(by: index), gain)
        }
    }

    func stop() {
        if deviceStarted, aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
        }
        deviceStarted = false
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        ioProcID = nil
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        for tapID in tapIDs.reversed() where tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapIDs.removeAll()
        slots?.deallocate()
        slots = nil
    }

    deinit { stop() }

    private static func validateFloat32(_ format: AudioStreamBasicDescription) throws {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              format.mBytesPerFrame > 0 else { throw ProcessTapMixError.unsupportedFormat }
    }

    private static func format(_ object: AudioObjectID, selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value))
        return value
    }

    private static func stringProperty(_ object: AudioObjectID,
                                       _ selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value))
        guard let value else { throw ProcessTapMixError.coreAudio(-1) }
        return value.takeRetainedValue() as String
    }

    private static func check(_ status: OSStatus) throws {
        guard status != noErr else { return }
        if status == kAudioDevicePermissionsError || status == OSStatus(0x7065726D) {
            throw ProcessTapMixError.permissionDenied
        }
        throw ProcessTapMixError.coreAudio(status)
    }
}
