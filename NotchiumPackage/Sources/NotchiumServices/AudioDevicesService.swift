import AppKit
@preconcurrency import ApplicationServices
import CoreAudio
import Foundation
import NotchiumCore

/// Core Audio's public transport type, reduced to what presentation distinguishes.
public enum AudioOutputTransport: String, Equatable, Sendable {
    case builtIn, bluetooth, usb, display, airPlay, other

    init(coreAudio value: UInt32) {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: self = .display
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        default: self = .other
        }
    }
}

/// Battery information for an output device, classified by trustworthiness. Nothing here is
/// ever estimated: a component the source does not report is nil, never inferred.
public enum DeviceBatteryStatus: Equatable, Sendable {
    /// No supported macOS API reports battery for this device (e.g. AirPods L/R/case).
    case unsupported
    /// The source can report battery, but has no current reading for this connection.
    case unavailable
    case available(DeviceBatteryLevels)
}

public struct DeviceBatteryLevels: Equatable, Sendable {
    /// One aggregate level (single-battery headphones).
    public let single: Double?
    public let left: Double?
    public let right: Double?
    public let caseLevel: Double?
    public let isCharging: Bool?
    /// When the source measured these values; consumers reject old readings as stale.
    public let measuredAt: Date

    public init(single: Double? = nil, left: Double? = nil, right: Double? = nil,
                caseLevel: Double? = nil, isCharging: Bool? = nil, measuredAt: Date) {
        self.single = single
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.isCharging = isCharging
        self.measuredAt = measuredAt
    }
}

public struct AudioDevice: Identifiable, Equatable, Sendable {
    /// Core Audio object ID: valid for selection during this connection only.
    public let id: String
    /// Core Audio device UID: stable for the physical device across reconnects.
    public let uid: String?
    public let name: String
    public let isDefaultOutput: Bool
    public let volume: Double?
    public let isMuted: Bool?
    public let canSetVolume: Bool
    public let canSetMute: Bool
    public let transport: AudioOutputTransport
    public let battery: DeviceBatteryStatus

    public init(id: String, uid: String? = nil, name: String, isDefaultOutput: Bool,
                volume: Double? = nil, isMuted: Bool? = nil,
                canSetVolume: Bool = false, canSetMute: Bool = false,
                transport: AudioOutputTransport = .other,
                battery: DeviceBatteryStatus = .unsupported) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isDefaultOutput = isDefaultOutput
        self.volume = volume
        self.isMuted = isMuted
        self.canSetVolume = canSetVolume
        self.canSetMute = canSetMute
        self.transport = transport
        self.battery = battery
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
    func volumeCommands() async -> AsyncStream<AudioVolumeCommandEvent>
    func selectOutput(id: String) async throws
    func setVolume(_ volume: Double, deviceID: String) async throws
    func setMuted(_ muted: Bool, deviceID: String) async throws
}

public extension AudioDevicesService {
    /// Non-hardware implementations have no system input source.
    func volumeCommands() async -> AsyncStream<AudioVolumeCommandEvent> {
        AsyncStream { $0.finish() }
    }
}

/// Listens to HAL device, default-output, volume, and mute events.
@MainActor
public final class RealAudioDevicesService: AudioDevicesService, SystemFeedbackControlling {
    private struct Listener {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private struct OutputDetails {
        let uid: String?
        let name: String
        let volumeElements: [UInt32]
        let muteElements: [UInt32]
        var canSetVolume: Bool { !volumeElements.isEmpty }
        var canSetMute: Bool { !muteElements.isEmpty }
        let transport: AudioOutputTransport
    }
    private var systemListeners: [Listener] = []
    private var outputListeners: [Listener] = []
    private var deviceListeners: [Listener] = []
    private var observers: [UUID: AsyncStream<AudioDevicesSnapshot>.Continuation] = [:]
    private var commandObservers: [UUID: AsyncStream<AudioVolumeCommandEvent>.Continuation] = [:]
    private var feedbackObservers: [UUID: AsyncStream<VolumeReplacementStatus>.Continuation] = [:]
    private var replacementEnabled = false
    private var replacementFailure: VolumeReplacementFallback?
    private var feedbackStatus = VolumeReplacementStatus(mode: .disabled)
    private var monitorStarted = false
    private var monitorAttempted = false
    private var monitorRoute: VolumeInputGate.Route?
    private var suspended = false
    private var lifecycleObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private lazy var volumeKeyMonitor = SystemVolumeKeyMonitor(onCommand: { [weak self] command, reading in
        guard let self, !self.commandObservers.isEmpty else { return }
        let id = self.defaultOutputID()
        guard self.cachedOutputIDs.contains(id), reading == nil || reading?.deviceID == id else { return }
        let output = self.device(id, selected: id)
        // Publish only hardware truth; no requested scalar enters the presentation stream.
        let event = AudioVolumeCommandEvent(command: command, output: output, wasReplaced: reading != nil)
        self.commandObservers.values.forEach { $0.yield(event) }
    }, onFailure: { [weak self] reason in
        guard let self else { return }
        self.replacementFailure = reason
        self.monitorStarted = false
        self.monitorAttempted = false
        self.reconcileVolumeMonitor()
    })
    private var selectedID: AudioObjectID = kAudioObjectUnknown
    private var previous: AudioDevicesSnapshot?
    private var cachedOutputIDs: [AudioObjectID] = []
    private var outputDetails: [AudioObjectID: OutputDetails] = [:]
    private var generation = 0

    public init() {}
    isolated deinit { stopObservation() }
    public func availability() async -> FeatureAvailability { .available }

    public func volumeReplacementUpdates() -> AsyncStream<VolumeReplacementStatus> {
        let token = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            feedbackObservers[token] = continuation
            if systemListeners.isEmpty { start() }
            continuation.yield(feedbackStatus)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.feedbackObservers[token] = nil
                    self?.stopIfUnobserved()
                }
            }
        }
    }

    public func setVolumeReplacementEnabled(_ enabled: Bool, requestPermission: Bool) {
        replacementEnabled = enabled
        replacementFailure = nil
        monitorAttempted = false
        if enabled && requestPermission && !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        reconcileVolumeMonitor()
    }

    public func stopVolumeReplacement() {
        replacementEnabled = false
        replacementFailure = nil
        monitorAttempted = false
        reconcileVolumeMonitor()
    }

    private func reconcileVolumeMonitor() {
        let output = previous?.currentOutput
        let permitted = !replacementEnabled || (AXIsProcessTrusted() && CGPreflightPostEventAccess())
        let supportsMute = output?.canSetMute == true && output?.isMuted != nil
        let supportsVolume = output?.canSetVolume == true && output?.volume != nil
            && (output?.isMuted != true || supportsMute)
        var fallback = replacementFailure
        if suspended { fallback = .suspended }
        else if replacementEnabled && !permitted { fallback = .permissionRequired }
        else if replacementEnabled && !supportsVolume && !supportsMute { fallback = .unsupportedOutput }
        let route: VolumeInputGate.Route? = replacementEnabled && fallback == nil && !commandObservers.isEmpty
            ? output.flatMap { device in UInt32(device.id).map {
                .init(deviceID: $0, volume: supportsVolume, mute: supportsMute)
            } } : nil
        if suspended || commandObservers.isEmpty {
            volumeKeyMonitor.stop()
            monitorStarted = false
            monitorAttempted = false
            monitorRoute = nil
        } else if !monitorAttempted || monitorRoute != route {
            volumeKeyMonitor.stop()
            monitorStarted = false
            monitorAttempted = true
            monitorRoute = route
            monitorStarted = volumeKeyMonitor.start(route: route)
            if route != nil && !monitorStarted {
                replacementFailure = .tapUnavailable
                fallback = .tapUnavailable
                monitorRoute = nil
                monitorStarted = volumeKeyMonitor.start()
            }
        }
        let status = VolumeReplacementStatus(
            mode: !replacementEnabled ? .disabled : (monitorRoute != nil && monitorStarted ? .activeReplacement : .passive),
            fallback: replacementEnabled ? fallback : nil,
            canReplaceVolume: supportsVolume, canReplaceMute: supportsMute)
        guard status != feedbackStatus else { return }
        feedbackStatus = status
        feedbackObservers.values.forEach { $0.yield(status) }
    }

    private func observeLifecycle() {
        func observe(_ center: NotificationCenter, _ name: Notification.Name,
                     action: @escaping @MainActor @Sendable (RealAudioDevicesService) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { action(self) } }
            }
            lifecycleObservers.append((center, token))
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) {
            $0.suspended = true
            $0.reconcileVolumeMonitor()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) {
            $0.suspended = false
            $0.replacementFailure = nil
            $0.refresh(rebuildDevices: true)
        }
        observe(.default, NSApplication.didBecomeActiveNotification) {
            if $0.replacementFailure == .permissionRequired { $0.replacementFailure = nil }
            if !$0.monitorStarted { $0.monitorAttempted = false }
            $0.reconcileVolumeMonitor()
        }
    }

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

    public func volumeCommands() async -> AsyncStream<AudioVolumeCommandEvent> {
        let token = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            commandObservers[token] = continuation
            if systemListeners.isEmpty { start() }
            reconcileVolumeMonitor()
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.commandObservers[token] = nil
                    if self.commandObservers.isEmpty { self.reconcileVolumeMonitor() }
                    self.stopIfUnobserved()
                }
            }
        }
    }

    public func setVolume(_ volume: Double, deviceID: String) async throws {
        guard let id = UInt32(deviceID), id == defaultOutputID() else {
            throw ServiceFailure.unsupportedOperation(.audioDevices)
        }
        guard volume.isFinite, let state = CoreAudioOutputControls().read(id), state.supportsVolume else {
            throw ServiceFailure.unsupportedOperation(.audioDevices)
        }
        guard CoreAudioOutputControls().writeVolume(state.volumes.map { _ in min(max(volume, 0), 1) }, state: state) else {
            throw ServiceFailure.unavailable(.audioDevices)
        }
    }

    public func setMuted(_ muted: Bool, deviceID: String) async throws {
        guard let id = UInt32(deviceID), id == defaultOutputID(),
              let state = CoreAudioOutputControls().read(id), state.supportsMute else {
            throw ServiceFailure.unsupportedOperation(.audioDevices)
        }
        guard CoreAudioOutputControls().writeMute(muted, state: state) else {
            throw ServiceFailure.unavailable(.audioDevices)
        }
    }

    private func start() {
        generation &+= 1
        let system = AudioObjectID(kAudioObjectSystemObject)
        addListener(system, Self.address(kAudioHardwarePropertyDevices), to: &systemListeners)
        addListener(system, Self.address(kAudioHardwarePropertyDefaultOutputDevice), to: &systemListeners)
        observeLifecycle()
        refresh()
    }

    private func removeObserver(_ token: UUID) {
        observers[token] = nil
        stopIfUnobserved()
    }

    private func stopIfUnobserved() {
        guard observers.isEmpty, commandObservers.isEmpty, feedbackObservers.isEmpty else { return }
        stopObservation()
    }

    private func stopObservation() {
        generation &+= 1
        volumeKeyMonitor.stop()
        monitorStarted = false
        monitorAttempted = false
        monitorRoute = nil
        lifecycleObservers.forEach { $0.0.removeObserver($0.1) }
        lifecycleObservers = []
        systemListeners.forEach(Self.remove)
        outputListeners.forEach(Self.remove)
        deviceListeners.forEach(Self.remove)
        systemListeners.removeAll()
        outputListeners.removeAll()
        deviceListeners.removeAll()
        selectedID = kAudioObjectUnknown
        previous = nil
        cachedOutputIDs = []
        outputDetails = [:]
    }

    private func refresh(rebuildDevices: Bool = false) {
        guard !suspended, !observers.isEmpty || !commandObservers.isEmpty || !feedbackObservers.isEmpty else { return }
        let defaultID = defaultOutputID()
        // Hot-plug can report the new default output before the device-list change arrives.
        if rebuildDevices || cachedOutputIDs.isEmpty
            || (defaultID != selectedID && defaultID != kAudioObjectUnknown
                && !cachedOutputIDs.contains(defaultID)) {
            // Retained but unavailable HAL endpoints must keep an alive-state listener so
            // reconnection is observed even when their object ID and device list stay unchanged.
            let candidates = outputIDs(includeInactive: true)
            cachedOutputIDs = candidates.filter(Self.isAlive)
            deviceListeners.forEach(Self.remove)
            deviceListeners.removeAll()
            for id in candidates {
                addListener(id, Self.address(kAudioDevicePropertyDeviceIsAlive), to: &deviceListeners)
            }
            outputDetails = Dictionary(uniqueKeysWithValues: cachedOutputIDs.map { id in
                (id, OutputDetails(uid: Self.deviceUID(id), name: Self.name(id) ?? "Audio Output",
                                   volumeElements: CoreAudioOutputControls.writableElements(id, kAudioDevicePropertyVolumeScalar),
                                   muteElements: CoreAudioOutputControls.writableElements(id, kAudioDevicePropertyMute),
                                   transport: Self.transport(id)))
            })
        }
        let id = defaultID
        if id != selectedID {
            outputListeners.forEach(Self.remove)
            outputListeners.removeAll()
            selectedID = id
            replacementFailure = nil
            if !monitorStarted { monitorAttempted = false }
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
        let changed = next != previous
        previous = next
        reconcileVolumeMonitor()
        guard changed else { return }
        observers.values.forEach { $0.yield(next) }
    }

    private func addListener(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress,
                             to target: inout [Listener]) {
        var address = property
        let generation = generation
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.refresh(rebuildDevices: [kAudioHardwarePropertyDevices, kAudioDevicePropertyDeviceIsAlive]
                    .contains(property.mSelector))
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
        let outputs = cachedOutputIDs.map { device($0, selected: selected) }.sorted { a, b in
            a.isDefaultOutput == b.isDefaultOutput
                ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                : a.isDefaultOutput
        }
        return AudioDevicesSnapshot(availability: .available, outputs: outputs)
    }

    private func device(_ id: AudioObjectID, selected: AudioObjectID) -> AudioDevice {
        let details = outputDetails[id]
        // Core Audio exposes no battery property, and macOS has no supported public API for
        // AirPods/headphone battery; private Bluetooth sources are deliberately not used.
        return AudioDevice(id: String(id), uid: details?.uid, name: details?.name ?? "Audio Output",
                           isDefaultOutput: id == selected,
                           volume: Self.scalar(id, elements: details?.volumeElements ?? []), isMuted: Self.muted(id),
                           canSetVolume: details?.canSetVolume ?? false,
                           canSetMute: details?.canSetMute ?? false,
                           transport: details?.transport ?? .other)
    }

    private func defaultOutputID() -> AudioObjectID {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout.size(ofValue: id))
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                          0, nil, &size, &id) == noErr ? id : kAudioObjectUnknown
    }

    private func outputIDs(includeInactive: Bool = false) -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            Self.hasOutput(id)
                && (includeInactive || Self.isAlive(id))
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

    private static func isAlive(_ id: AudioObjectID) -> Bool {
        var address = Self.address(kAudioDevicePropertyDeviceIsAlive)
        var alive: UInt32 = 0
        var size: UInt32 = 4
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &alive) == noErr && alive != 0
    }

    private static func outputChannelCount(_ id: AudioObjectID) -> Int {
        CoreAudioOutputControls.channelCount(id)
    }

    private static func name(_ id: AudioObjectID) -> String? {
        var address = Self.address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func transport(_ id: AudioObjectID) -> AudioOutputTransport {
        var address = Self.address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return .other }
        return AudioOutputTransport(coreAudio: value)
    }

    private static func deviceUID(_ id: AudioObjectID) -> String? {
        ProcessTapSupport.stringProperty(id, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func scalar(_ id: AudioObjectID, elements: [UInt32]) -> Double? {
        if !elements.isEmpty { return CoreAudioOutputControls.observedVolume(id, elements: elements) }
        guard var address = controlAddress(id, kAudioDevicePropertyVolumeScalar) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr
            && value.isFinite && (0...1).contains(value) ? Double(value) : nil
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
