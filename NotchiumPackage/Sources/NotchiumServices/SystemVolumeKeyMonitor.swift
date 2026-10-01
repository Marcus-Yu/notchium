import AppKit
import IOKit.hidsystem

public enum AudioVolumeCommand: Equatable, Sendable {
    case up, down

    /// AUX_CONTROL_BUTTONS packs the key in the high word and down/up in the flags byte.
    /// The low repeat bit is deliberately ignored: held-key repeats are presentation events.
    public init?(systemDefinedSubtype: Int, data1: Int) {
        guard systemDefinedSubtype == Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
              (data1 >> 8) & 0xff == Int(NX_KEYDOWN) else { return nil }
        switch (data1 >> 16) & 0xffff {
        case Int(NX_KEYTYPE_SOUND_UP): self = .up
        case Int(NX_KEYTYPE_SOUND_DOWN): self = .down
        default: return nil
        }
    }

    public func isUnchangedBoundary(volume: Double?) -> Bool {
        guard let volume else { return false }
        return self == .down ? volume == 0 : volume == 1
    }
}

/// Input intent plus a fresh HAL reading; an event can exist without a snapshot change.
public struct AudioVolumeCommandEvent: Sendable {
    public let command: AudioVolumeCommand
    public let output: AudioDevice

    public init(command: AudioVolumeCommand, output: AudioDevice) {
        self.command = command
        self.output = output
    }
}

/// One passive system-defined event tap covers both foreground and background input.
/// It never consumes keys, changes audio, requests permission, or suppresses the native HUD.
@MainActor
final class SystemVolumeKeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onCommand: @MainActor (AudioVolumeCommand) -> Void

    init(onCommand: @escaping @MainActor (AudioVolumeCommand) -> Void) {
        self.onCommand = onCommand
    }

    isolated deinit { stop() }

    func start() {
        guard tap == nil else { return }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << NX_SYSDEFINED,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                // The sole run-loop source is installed on the main loop below; removal and
                // object lifetime are main-actor owned, so the unretained pointer stays valid.
                MainActor.assumeIsolated {
                    let monitor = Unmanaged<SystemVolumeKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    } else if type.rawValue == UInt32(NX_SYSDEFINED),
                              let keyEvent = NSEvent(cgEvent: event),
                              let command = AudioVolumeCommand(systemDefinedSubtype: Int(keyEvent.subtype.rawValue),
                                                               data1: keyEvent.data1) {
                        // Leave the event callback immediately; HAL reads run after dispatch.
                        Task { @MainActor [weak monitor] in
                            guard let monitor, monitor.tap != nil else { return }
                            monitor.onCommand(command)
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }
}
