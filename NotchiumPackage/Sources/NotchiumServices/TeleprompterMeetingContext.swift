import CoreAudio
import Foundation

/// Status evidence only. A probable call is a suggestion, never proof of attendance.
public enum TeleprompterMeetingContext: Equatable, Sendable {
    case idle
    case probableCall(provider: String)
    /// Must be combined with calendar or an explicit meeting-join action by the feature owner.
    case browserUsingInput
    case unavailable
}

public struct TeleprompterAudioInputProcess: Equatable, Sendable {
    public let processID: Int32
    public let bundleID: String
    public let isRunningInput: Bool

    public init(processID: Int32, bundleID: String, isRunningInput: Bool) {
        self.processID = processID
        self.bundleID = bundleID
        self.isRunningInput = isRunningInput
    }
}

public enum TeleprompterMeetingClassifier {
    /// Avoids window titles, browser URLs, Accessibility, audio taps and recording permissions.
    public static func context(for processes: [TeleprompterAudioInputProcess],
                               excludingProcessID: Int32) -> TeleprompterMeetingContext {
        let active = processes.filter { $0.isRunningInput && $0.processID != excludingProcessID }
        let nativeClients = [("us.zoom.xos", "Zoom"), ("com.microsoft.teams2", "Microsoft Teams"),
                             ("com.microsoft.teams", "Microsoft Teams")]
        for (bundleID, provider) in nativeClients {
            if active.contains(where: { belongs($0.bundleID, to: bundleID) }) {
                return .probableCall(provider: provider)
            }
        }
        let browsers = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac",
                        "org.mozilla.firefox", "com.brave.Browser", "company.thebrowser.Browser",
                        "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]
        if active.contains(where: { process in browsers.contains { belongs(process.bundleID, to: $0) } }) {
            return .browserUsingInput
        }
        return .idle
    }

    private static func belongs(_ bundleID: String, to applicationID: String) -> Bool {
        bundleID == applicationID || bundleID.hasPrefix(applicationID + ".")
    }
}

public protocol TeleprompterMeetingContextService: Sendable {
    /// Subscribing observes process-input status only. Ending the stream removes all listeners.
    func updates() async -> AsyncStream<TeleprompterMeetingContext>
}

/// Core Audio listener installation and callbacks are serialized on the main actor. This
/// adapter reads metadata only and never creates a process tap or starts an input stream.
@MainActor
public final class RealTeleprompterMeetingContextService: TeleprompterMeetingContextService {
    private struct Listener {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private var systemListener: Listener?
    private var processListeners: [AudioObjectID: Listener] = [:]
    private var continuation: AsyncStream<TeleprompterMeetingContext>.Continuation?
    private var subscription: UUID?
    private var last: TeleprompterMeetingContext?
    private let ownProcessID: Int32

    public init(ownProcessID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.ownProcessID = ownProcessID
    }

    isolated deinit {
        if let subscription { stop(ifCurrent: subscription) }
    }

    public func updates() async -> AsyncStream<TeleprompterMeetingContext> {
        if let subscription { stop(ifCurrent: subscription) }
        let token = UUID()
        let stream = AsyncStream<TeleprompterMeetingContext>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
            subscription = token
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop(ifCurrent: token) }
            }
        }
        systemListener = listen(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyProcessObjectList)
        if systemListener == nil { publish(.unavailable) }
        else { refresh() }
        return stream
    }

    private func stop(ifCurrent token: UUID) {
        guard subscription == token else { return }
        subscription = nil
        if let systemListener { Self.remove(systemListener) }
        processListeners.values.forEach(Self.remove)
        systemListener = nil
        processListeners.removeAll()
        let previous = continuation
        continuation = nil
        last = nil
        previous?.finish()
    }

    private func refresh() {
        guard continuation != nil, let objects = processIDs() else {
            publish(.unavailable)
            return
        }
        let present = Set(objects)
        for object in processListeners.keys.filter({ !present.contains($0) }) {
            if let listener = processListeners.removeValue(forKey: object) { Self.remove(listener) }
        }
        for object in objects where processListeners[object] == nil {
            processListeners[object] = listen(object, selector: kAudioProcessPropertyIsRunningInput)
        }
        let processes = objects.compactMap { object -> TeleprompterAudioInputProcess? in
            guard let running: UInt32 = Self.read(object, selector: kAudioProcessPropertyIsRunningInput),
                  running == 1,
                  let pid: Int32 = Self.read(object, selector: kAudioProcessPropertyPID), pid > 0,
                  pid != ownProcessID, let bundleID = Self.bundleID(object) else { return nil }
            return TeleprompterAudioInputProcess(processID: pid, bundleID: bundleID, isRunningInput: true)
        }
        publish(TeleprompterMeetingClassifier.context(for: processes, excludingProcessID: ownProcessID))
    }

    private func publish(_ context: TeleprompterMeetingContext) {
        guard context != last else { return }
        last = context
        continuation?.yield(context)
    }

    private func processIDs() -> [AudioObjectID]? {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &byteCount) == noErr else { return nil }
        guard byteCount > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(byteCount) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &byteCount, &objects) == noErr else { return nil }
        return Array(objects.prefix(Int(byteCount) / MemoryLayout<AudioObjectID>.size))
    }

    private func listen(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> Listener? {
        var address = Self.address(selector)
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

    private static func read<T: FixedWidthInteger>(_ object: AudioObjectID,
                                                  selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func bundleID(_ object: AudioObjectID) -> String? {
        var address = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}

public struct MockTeleprompterMeetingContextService: TeleprompterMeetingContextService {
    public let context: TeleprompterMeetingContext

    public init(context: TeleprompterMeetingContext = .idle) { self.context = context }

    public func updates() async -> AsyncStream<TeleprompterMeetingContext> {
        AsyncStream { continuation in
            continuation.yield(context)
            continuation.finish()
        }
    }
}
