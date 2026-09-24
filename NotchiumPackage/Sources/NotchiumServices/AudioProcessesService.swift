import CoreAudio
import Foundation

public struct AudioProducingProcess: Identifiable, Equatable, Sendable {
    public let id: Int32
    public let bundleID: String?
    public let controllableOutputDeviceIDs: [String]

    public init(id: Int32, bundleID: String?, controllableOutputDeviceIDs: [String] = []) {
        self.id = id
        self.bundleID = bundleID
        self.controllableOutputDeviceIDs = controllableOutputDeviceIDs
    }

    public func isControllable(on outputDeviceID: String?) -> Bool {
        guard let outputDeviceID else { return false }
        return controllableOutputDeviceIDs.contains(outputDeviceID)
    }
}

public protocol AudioProcessesService: Sendable {
    /// Subscribing starts HAL process observation; terminating the stream removes it.
    func updates() async -> AsyncStream<[AudioProducingProcess]>
}

@MainActor
public final class RealAudioProcessesService: AudioProcessesService {
    private struct TapRoute: Hashable {
        let processObjectID: AudioObjectID
        let outputDeviceID: AudioObjectID
    }

    private struct Listener {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var systemListener: Listener?
    private var processListeners: [AudioObjectID: [Listener]] = [:]
    private var verifiedTapRoutes: Set<TapRoute> = []
    private var observer: AsyncStream<[AudioProducingProcess]>.Continuation?
    private var observerID: UUID?
    private var last: [AudioProducingProcess] = []

    public init() {}

    public func updates() async -> AsyncStream<[AudioProducingProcess]> {
        let token = UUID()
        observer?.finish()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observer = continuation
            observerID = token
            start()
            continuation.yield(last)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop(ifCurrent: token) }
            }
        }
    }

    private func start() {
        guard systemListener == nil else { return }
        systemListener = listen(AudioObjectID(kAudioObjectSystemObject),
                                selector: kAudioHardwarePropertyProcessObjectList)
        refresh()
    }

    private func stop(ifCurrent token: UUID) {
        guard observerID == token else { return }
        if let systemListener { Self.remove(systemListener) }
        processListeners.values.joined().forEach(Self.remove)
        systemListener = nil
        processListeners.removeAll()
        verifiedTapRoutes.removeAll()
        observer = nil
        observerID = nil
        last = []
    }

    private func refresh() {
        guard observer != nil else { return }
        let objects = processIDs()
        let present = Set(objects)
        for id in processListeners.keys.filter({ !present.contains($0) }) {
            processListeners[id]?.forEach(Self.remove)
            processListeners[id] = nil
            verifiedTapRoutes = verifiedTapRoutes.filter { $0.processObjectID != id }
        }
        for id in objects where processListeners[id] == nil {
            processListeners[id] = [
                listen(id, selector: kAudioProcessPropertyIsRunningOutput),
                listen(id, selector: kAudioProcessPropertyDevices,
                       scope: kAudioObjectPropertyScopeOutput),
            ].compactMap { $0 }
        }
        let active = objects.compactMap { object -> AudioProducingProcess? in
            guard Self.readUInt(object, kAudioProcessPropertyIsRunningOutput) == 1,
                  let pid = Self.readInt(object, kAudioProcessPropertyPID), pid > 0,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let bundleID = Self.bundleID(object), !bundleID.isEmpty else { return nil }
            let controllableOutputs = Self.readObjectIDs(object, kAudioProcessPropertyDevices,
                                                         scope: kAudioObjectPropertyScopeOutput)
                .filter { verifyTapRoute(processObjectID: object, outputDeviceID: $0) }
                .map(String.init)
                .sorted()
            guard !controllableOutputs.isEmpty else { return nil }
            return AudioProducingProcess(id: pid, bundleID: bundleID,
                                         controllableOutputDeviceIDs: controllableOutputs)
        }.sorted { $0.id < $1.id }
        guard active != last else { return }
        last = active
        observer?.yield(active)
    }

    private func processIDs() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private func listen(_ object: AudioObjectID, selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Listener? {
        var address = Self.address(selector, scope: scope)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return nil }
        return Listener(object: object, address: address, block: block)
    }

    private static func remove(_ listener: Listener) {
        var address = listener.address
        AudioObjectRemovePropertyListenerBlock(listener.object, &address, .main, listener.block)
    }

    private static func readUInt(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func readObjectIDs(_ object: AudioObjectID,
                                      _ selector: AudioObjectPropertySelector,
                                      scope: AudioObjectPropertyScope) -> [AudioObjectID] {
        var address = Self.address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioObjectID>.size else { return [] }
        var values = [AudioObjectID](repeating: kAudioObjectUnknown,
                                    count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &values) == noErr else {
            return []
        }
        return values.filter { $0 != kAudioObjectUnknown }
    }

    private func verifyTapRoute(processObjectID: AudioObjectID,
                                outputDeviceID: AudioObjectID) -> Bool {
        let route = TapRoute(processObjectID: processObjectID, outputDeviceID: outputDeviceID)
        if verifiedTapRoutes.contains(route) { return true }
        guard AudioDeviceVisibility.isUserVisible(
            uid: ProcessTapSupport.stringProperty(outputDeviceID,
                                                   selector: kAudioDevicePropertyDeviceUID)
        ), ProcessTapSupport.canCreateTap(processObjectID: processObjectID,
                                          deviceID: outputDeviceID) else {
            return false
        }
        verifiedTapRoutes.insert(route)
        return true
    }

    private static func readInt(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
        var address = Self.address(selector)
        var value: Int32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func bundleID(_ object: AudioObjectID) -> String? {
        var address = Self.address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
            ? value?.takeRetainedValue() as String? : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}

public struct MockAudioProcessesService: AudioProcessesService {
    public let processes: [AudioProducingProcess]
    public init(processes: [AudioProducingProcess] = []) { self.processes = processes }
    public func updates() async -> AsyncStream<[AudioProducingProcess]> {
        AsyncStream { continuation in continuation.yield(processes); continuation.finish() }
    }
}
