import AppKit
import ApplicationServices
import IOKit.hidsystem
import Synchronization

public enum AudioVolumeCommand: Equatable, Sendable {
    case up, down, mute

    public init?(systemDefinedSubtype: Int, data1: Int) {
        guard let input = VolumeKeyInput(subtype: systemDefinedSubtype, data1: data1, flags: []),
              input.isDown else { return nil }
        self = input.key.command
    }

    public func isUnchangedBoundary(volume: Double?) -> Bool {
        guard let volume else { return false }
        switch self {
        case .down: return volume == 0
        case .up: return volume == 1
        case .mute: return false
        }
    }
}

public struct AudioVolumeCommandEvent: Sendable {
    public let command: AudioVolumeCommand
    public let output: AudioDevice
    public let wasReplaced: Bool
    public init(command: AudioVolumeCommand, output: AudioDevice, wasReplaced: Bool = false) {
        self.command = command
        self.output = output
        self.wasReplaced = wasReplaced
    }
}

private extension VolumeHardwareKey {
    var command: AudioVolumeCommand {
        switch self { case .up: .up; case .down: .down; case .mute: .mute }
    }
}

struct VolumeKeyInput: Sendable {
    let key: VolumeHardwareKey
    let isDown: Bool
    let repeated: Bool
    let fine: Bool
    let eligibleModifiers: Bool

    init?(subtype: Int, data1: Int, flags: CGEventFlags) {
        guard subtype == Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
              let key = VolumeHardwareKey(rawValue: (data1 >> 16) & 0xffff),
              [Int(NX_KEYDOWN), Int(NX_KEYUP)].contains((data1 >> 8) & 0xff) else { return nil }
        self.key = key
        isDown = (data1 >> 8) & 0xff == Int(NX_KEYDOWN)
        repeated = data1 & 1 != 0
        fine = flags.contains([.maskShift, .maskAlternate])
        let modifiers = flags.intersection([.maskShift, .maskAlternate, .maskControl, .maskCommand])
        // Preserve Option's Sound settings shortcut and Shift's native feedback-sound behavior.
        eligibleModifiers = modifiers.isEmpty || (fine && modifiers == [.maskShift, .maskAlternate] && key != .mute)
    }
}

/// The copied event is handed to one serial worker and never shared with its original owner.
/// A mutex makes replay idempotent if failure and teardown handling converge.
private final class OwnedVolumeEvent: @unchecked Sendable {
    private let event: CGEvent
    private let replayGuard = SingleVolumeReplay()
    init?(_ original: CGEvent) {
        guard let copy = original.copy() else { return nil }
        event = copy
    }
    func replay() {
        guard replayGuard.claim() else { return }
        event.setIntegerValueField(.eventSourceUserData, value: VolumeEventReplayGuard.marker)
        event.post(tap: .cghidEventTap)
    }
}

/// Operation state is exclusively queue confined. Only the synchronized input gate crosses
/// executors. The queue drains accepted input even after the monitor is torn down.
private final class VolumeKeyWorker: @unchecked Sendable {
    let gate = VolumeInputGate()
    private let queue = DispatchQueue(label: "app.notchium.volume-keys", qos: .userInteractive)
    private var operation = VolumeKeyOperation()
    private let failed = Mutex(false)
    private let onCommand: @MainActor @Sendable (AudioVolumeCommand, VolumeHardwareState?) -> Void
    private let onFailure: @MainActor @Sendable (VolumeReplacementFallback) -> Void

    init(onCommand: @escaping @MainActor @Sendable (AudioVolumeCommand, VolumeHardwareState?) -> Void,
         onFailure: @escaping @MainActor @Sendable (VolumeReplacementFallback) -> Void) {
        self.onCommand = onCommand
        self.onFailure = onFailure
    }

    func fail(_ reason: VolumeReplacementFallback) {
        guard failed.withLock({ if $0 { return false }; $0 = true; return true }) else { return }
        gate.invalidate()
        DispatchQueue.main.async { [self] in if gate.isLive { onFailure(reason) } }
    }

    func handle(_ event: CGEvent, input: VolumeKeyInput) -> Bool {
        guard input.isDown, input.eligibleModifiers, gate.supports(input.key) else { return false }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            fail(.permissionRequired)
            return false
        }
        guard let owned = OwnedVolumeEvent(event) else { return false }
        guard let (route, generation) = gate.reserve(input.key) else {
            fail(.operationFailed) // bounded queue exhausted: stop accepting input immediately
            return false
        }
        queue.async { [self] in
            defer { gate.complete() }
            guard gate.isCurrent(generation) else {
                owned.replay()
                return
            }
            guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
                fail(.permissionRequired)
                owned.replay()
                return
            }
            let result = operation.apply(input.key, fine: input.fine, repeated: input.repeated,
                                         deviceID: route.deviceID, hardware: CoreAudioOutputControls())
            switch result {
            case let .applied(state):
                DispatchQueue.main.async { [self] in
                    guard gate.isCurrent(generation) else { return }
                    onCommand(input.key.command, state)
                }
            case .notApplied:
                fail(.operationFailed)
                owned.replay()
            case .uncertain:
                // HAL may have changed hardware even when the call or readback failed.
                fail(.operationFailed)
            }
        }
        return true
    }

    @MainActor func passive(_ key: VolumeHardwareKey) { if gate.isLive { onCommand(key.command, nil) } }
}

/// Exactly one tap: passive session observation OR opt-in active HID filtering. Its context
/// stays retained until source removal and Mach-port invalidation on the main run loop.
@MainActor
final class SystemVolumeKeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var worker: VolumeKeyWorker?
    private let onCommand: @MainActor @Sendable (AudioVolumeCommand, VolumeHardwareState?) -> Void
    private let onFailure: @MainActor @Sendable (VolumeReplacementFallback) -> Void

    init(onCommand: @escaping @MainActor @Sendable (AudioVolumeCommand, VolumeHardwareState?) -> Void,
         onFailure: @escaping @MainActor @Sendable (VolumeReplacementFallback) -> Void) {
        self.onCommand = onCommand
        self.onFailure = onFailure
    }
    isolated deinit { stop() }

    @discardableResult
    func start(route: VolumeInputGate.Route? = nil) -> Bool {
        stop()
        let worker = VolumeKeyWorker(onCommand: onCommand, onFailure: onFailure)
        worker.gate.configure(route)
        let active = route != nil
        guard let tap = CGEvent.tapCreate(
            tap: active ? .cghidEventTap : .cgSessionEventTap,
            place: .headInsertEventTap, options: active ? .defaultTap : .listenOnly,
            eventsOfInterest: CGEventMask(1) << NX_SYSDEFINED,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let worker = Unmanaged<VolumeKeyWorker>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    worker.fail(.tapDisabled)
                    return Unmanaged.passUnretained(event)
                }
                guard type.rawValue == UInt32(NX_SYSDEFINED),
                      !VolumeEventReplayGuard.isReplay(event.getIntegerValueField(.eventSourceUserData)),
                      let native = NSEvent(cgEvent: event),
                      let input = VolumeKeyInput(subtype: Int(native.subtype.rawValue), data1: native.data1,
                                                 flags: event.flags) else { return Unmanaged.passUnretained(event) }
                if worker.handle(event, input: input) { return nil }
                if input.isDown {
                    // Observation only; the service reads HAL after the callback has returned.
                    DispatchQueue.main.async { [worker] in worker.passive(input.key) }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(worker).toOpaque()
        ) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        self.worker = worker
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else { stop(); return false }
        return true
    }

    func stop() {
        worker?.gate.close()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); CFRunLoopSourceInvalidate(source) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        worker = nil
    }
}
