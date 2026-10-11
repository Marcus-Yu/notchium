import AppKit
import ApplicationServices
import CoreAudio
import IOKit.hidsystem
import XCTest
@testable import NotchiumServices

/// Explicit opt-in only. Uses a small volume step on the built-in speakers and restores
/// every original channel and mute value. Synthetic event evidence is not a physical-key claim.
@MainActor
final class VolumeReplacementHardwareTests: XCTestCase {
    func testActiveTapChangesBuiltInVolumeOnceAndSuppressesTheOriginalEvent() async throws {
        guard ProcessInfo.processInfo.environment["NOTCHIUM_VERIFY_SYSTEM_FEEDBACK"] == "1" else {
            throw XCTSkip("Set NOTCHIUM_VERIFY_SYSTEM_FEEDBACK=1 for hardware qualification")
        }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw XCTSkip("Accessibility unavailable") }
        let service = RealAudioDevicesService()
        let snapshots = await service.updates()
        var iterator = snapshots.makeAsyncIterator()
        let first = await iterator.next()
        let output = try XCTUnwrap(first?.currentOutput)
        guard output.transport == .builtIn else { throw XCTSkip("Qualification changes only built-in speakers") }
        let hardware = CoreAudioOutputControls()
        let id = hardware.defaultOutputID()
        let original = try XCTUnwrap(hardware.read(id))
        let volume = try XCTUnwrap(original.volume)
        guard original.supportsVolume, original.supportsMute else {
            throw XCTSkip("Writable volume and mute controls required")
        }
        let key = volume >= 1.0 / 64 ? NX_KEYTYPE_SOUND_DOWN : NX_KEYTYPE_SOUND_UP
        let expected = volume + (key == NX_KEYTYPE_SOUND_DOWN ? -1.0 / 64 : 1.0 / 64)
        defer {
            _ = hardware.writeVolume(original.volumes, state: original)
            _ = hardware.writeMute(original.muted ?? false, state: original)
        }
        let done = expectation(description: "Verified command")
        var readings: [VolumeHardwareState] = []
        var failures: [VolumeReplacementFallback] = []
        let monitor = SystemVolumeKeyMonitor(onCommand: { _, state in
            if let state { readings.append(state); done.fulfill() }
        }, onFailure: { failures.append($0); done.fulfill() })
        guard monitor.start(route: .init(deviceID: id, volume: true, mute: true)) else {
            throw XCTSkip("Active HID tap unavailable")
        }
        defer { monitor.stop() }

        // A downstream observer verifies the accepted event never reaches native handling.
        let counter = DownstreamVolumeCounter()
        let tap = try XCTUnwrap(CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(1) << NX_SYSDEFINED,
            callback: { _, type, event, context in
                guard type.rawValue == UInt32(NX_SYSDEFINED), let context else { return Unmanaged.passUnretained(event) }
                MainActor.assumeIsolated {
                    let counter = Unmanaged<DownstreamVolumeCounter>.fromOpaque(context).takeUnretainedValue()
                    if event.getIntegerValueField(.eventSourceUserData) == DownstreamVolumeCounter.marker {
                        counter.count += 1
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(counter).toOpaque()))
        let source = try XCTUnwrap(CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0))
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        defer {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(tap)
        }
        let input = try XCTUnwrap(NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: [.option, .shift], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
            data1: Int(key) << 16 | Int(NX_KEYDOWN) << 8, data2: -1)?.cgEvent)
        input.setIntegerValueField(.eventSourceUserData, value: DownstreamVolumeCounter.marker)
        input.post(tap: .cghidEventTap)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(readings.count, 1)
        let actual = try XCTUnwrap(hardware.read(id)?.volume)
        XCTAssertEqual(actual, expected, accuracy: 0.001, "One fine step, never two")
        XCTAssertEqual(readings.last?.volume, actual)
        XCTAssertEqual(counter.count, 0, "Accepted event is suppressed before native handling")
    }

    func testMuteAndHeldRepeatChangeHardwareOnlyOnce() async throws {
        let (hardware, original) = try await supportedHardware()
        let done = expectation(description: "Mute commands read back")
        done.expectedFulfillmentCount = 2
        var readings: [VolumeHardwareState] = []
        let monitor = SystemVolumeKeyMonitor(onCommand: { _, state in
            if let state { readings.append(state); done.fulfill() }
        }, onFailure: { _ in XCTFail("Mute replacement failed"); done.fulfill() })
        defer {
            monitor.stop()
            _ = hardware.writeMute(original.muted ?? false, state: original)
        }
        guard monitor.start(route: .init(deviceID: original.deviceID, volume: false, mute: true)) else {
            throw XCTSkip("Active HID tap unavailable")
        }
        try event(NX_KEYTYPE_MUTE).post(tap: .cghidEventTap)
        try event(NX_KEYTYPE_MUTE, repeated: true).post(tap: .cghidEventTap)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(readings.count, 2)
        XCTAssertTrue(readings.allSatisfy { $0.muted == !(original.muted ?? false) })
        XCTAssertEqual(hardware.read(original.deviceID)?.muted, !(original.muted ?? false))
    }

    func testRejectedBeforeWriteReplaysOnceWithoutRecapture() async throws {
        let (hardware, original) = try await supportedHardware()
        let replayed = expectation(description: "One marked replay reached the session")
        let counter = DownstreamVolumeCounter()
        let tap = try XCTUnwrap(CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(1) << NX_SYSDEFINED,
            callback: { _, type, event, context in
                guard type.rawValue == UInt32(NX_SYSDEFINED), let context,
                      VolumeEventReplayGuard.isReplay(event.getIntegerValueField(.eventSourceUserData)) else {
                    return Unmanaged.passUnretained(event)
                }
                MainActor.assumeIsolated {
                    let counter = Unmanaged<DownstreamVolumeCounter>.fromOpaque(context).takeUnretainedValue()
                    counter.count += 1
                    counter.onEvent?()
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(counter).toOpaque()))
        counter.onEvent = { replayed.fulfill() }
        let source = try XCTUnwrap(CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0))
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        var failures: [VolumeReplacementFallback] = []
        let monitor = SystemVolumeKeyMonitor(onCommand: { _, _ in XCTFail("Stale route must not write") },
                                            onFailure: { failures.append($0) })
        defer {
            monitor.stop()
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(tap)
            _ = hardware.writeVolume(original.volumes, state: original)
            _ = hardware.writeMute(original.muted ?? false, state: original)
        }
        guard monitor.start(route: .init(deviceID: UInt32.max, volume: true, mute: true)) else {
            throw XCTSkip("Active HID tap unavailable")
        }
        try event(NX_KEYTYPE_MUTE).post(tap: .cghidEventTap)
        await fulfillment(of: [replayed], timeout: 3)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(counter.count, 1, "Replay bypasses its originating tap and cannot loop")
        XCTAssertEqual(failures, [.operationFailed])
    }

    func testServiceStopsInterceptionWhenItsLastCommandSubscriberEnds() async throws {
        _ = try await supportedHardware()
        let service = RealAudioDevicesService()
        let statuses = service.volumeReplacementUpdates()
        let commands = await service.volumeCommands()
        let consumer = Task { for await _ in commands {} }
        let active = expectation(description: "Service active")
        let stopped = expectation(description: "Last command subscriber ends interception")
        let watcher = Task {
            var sawActive = false
            for await status in statuses {
                if status.mode == .activeReplacement, !sawActive {
                    sawActive = true
                    active.fulfill()
                } else if sawActive, status.mode == .passive {
                    stopped.fulfill()
                    break
                }
            }
        }
        defer { consumer.cancel(); watcher.cancel(); service.stopVolumeReplacement() }
        service.setVolumeReplacementEnabled(true, requestPermission: false)
        await fulfillment(of: [active], timeout: 3)
        consumer.cancel()
        await fulfillment(of: [stopped], timeout: 3)
    }

    private func supportedHardware() async throws -> (CoreAudioOutputControls, VolumeHardwareState) {
        guard ProcessInfo.processInfo.environment["NOTCHIUM_VERIFY_SYSTEM_FEEDBACK"] == "1" else {
            throw XCTSkip("Set NOTCHIUM_VERIFY_SYSTEM_FEEDBACK=1 for hardware qualification")
        }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw XCTSkip("Accessibility unavailable") }
        let service = RealAudioDevicesService()
        let stream = await service.updates()
        var iterator = stream.makeAsyncIterator()
        let snapshot = await iterator.next()
        let transport = snapshot?.currentOutput?.transport
        guard transport == .builtIn || (transport == .bluetooth
            && ProcessInfo.processInfo.environment["NOTCHIUM_VERIFY_SYSTEM_FEEDBACK_BLUETOOTH"] == "1") else {
            throw XCTSkip("Built-in speakers or explicitly opted-in Bluetooth output required")
        }
        let hardware = CoreAudioOutputControls()
        let state = try XCTUnwrap(hardware.read(hardware.defaultOutputID()))
        guard state.supportsVolume, state.supportsMute else { throw XCTSkip("Writable controls required") }
        return (hardware, state)
    }

    private func event(_ key: Int32, repeated: Bool = false) throws -> CGEvent {
        try XCTUnwrap(NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
            data1: Int(key) << 16 | Int(NX_KEYDOWN) << 8 | (repeated ? 1 : 0), data2: -1)?.cgEvent)
    }
}

@MainActor
private final class DownstreamVolumeCounter {
    nonisolated static let marker: Int64 = 0x4e6f746368544553
    var count = 0
    var onEvent: (() -> Void)?
}
