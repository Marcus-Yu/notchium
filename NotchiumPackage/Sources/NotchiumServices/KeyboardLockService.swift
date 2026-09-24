import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import NotchiumCore
import Synchronization

public struct KeyboardLockPolicy: Equatable, Sendable {
    public let emergencyChord: String
    public let emergencyHoldDuration: Duration
    public let mouseRemainsUsable: Bool
    public let unlockOnTapFailure: Bool

    public init(
        emergencyChord: String,
        emergencyHoldDuration: Duration,
        mouseRemainsUsable: Bool,
        unlockOnTapFailure: Bool
    ) {
        self.emergencyChord = emergencyChord
        self.emergencyHoldDuration = emergencyHoldDuration
        self.mouseRemainsUsable = mouseRemainsUsable
        self.unlockOnTapFailure = unlockOnTapFailure
    }

    public static let productDefault = KeyboardLockPolicy(
        emergencyChord: "Command–Option–Escape",
        emergencyHoldDuration: .seconds(2),
        mouseRemainsUsable: true,
        unlockOnTapFailure: true
    )
}

public enum KeyboardLockIssue: Equatable, Sendable {
    case permissionsRequired(Set<PermissionKind>)
    case eventTapUnavailable
    case eventTapDisabled
    case secureInputEnabled
}

public struct KeyboardLockSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    public let isLocked: Bool
    public let emergencyUnlockStartedAt: Date?
    public let issue: KeyboardLockIssue?

    public init(
        availability: FeatureAvailability,
        isLocked: Bool = false,
        emergencyUnlockStartedAt: Date? = nil,
        issue: KeyboardLockIssue? = nil
    ) {
        self.availability = availability
        self.isLocked = isLocked
        self.emergencyUnlockStartedAt = emergencyUnlockStartedAt
        self.issue = issue
    }
}

public enum KeyboardLockFailure: Error, Equatable, Sendable {
    case permissionsRequired(Set<PermissionKind>)
    case eventTapUnavailable
    case secureInputEnabled
}

public protocol KeyboardLockService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<KeyboardLockSnapshot>
    func lock(policy: KeyboardLockPolicy) async throws
    func unlock() async
    func openPermissionSettings(for permissions: Set<PermissionKind>)
    func shutdown()
}

/// `UserDefaults` is documented as thread-safe. This wrapper makes that contract explicit to
/// Swift's strict concurrency checker; access that mutates the request marker is additionally
/// serialized by `RealKeyboardLockService.state`.
private final class SendableUserDefaults: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}

/// Core Foundation event-tap handles are immutable references. Their lifecycle is serialized by
/// the service mutex and teardown is always dispatched to the main run loop.
private final class KeyboardEventTapResources: @unchecked Sendable {
    let tap: CFMachPort
    let source: CFRunLoopSource
    var maintenance: Timer?

    init(tap: CFMachPort, source: CFRunLoopSource) {
        self.tap = tap
        self.source = source
    }
}

public final class RealKeyboardLockService: KeyboardLockService {
    private struct State {
        var isLocked = false
        var resources: KeyboardEventTapResources?
        var commandIsDown = false
        var optionIsDown = false
        var escapeIsDown = false
        var emergencyUnlockStartedAt: ContinuousClock.Instant?
        var emergencyUnlockDisplayStartedAt: Date?
        var emergencyHoldDuration: Duration = .seconds(2)
        var chordGeneration = 0
        var issue: KeyboardLockIssue?
        var needsPublication = false
        var continuations: [UUID: AsyncStream<KeyboardLockSnapshot>.Continuation] = [:]
        let preferences: SendableUserDefaults
    }

    private static let escapeKeyCode: Int64 = 53
    private static let requestKey = "keyboardLock.didRequestPermissions"

    private let state: Mutex<State>

    public init(preferences: UserDefaults = .standard) {
        state = Mutex(State(preferences: SendableUserDefaults(preferences)))
    }

    deinit { shutdown() }

    public func availability() async -> FeatureAvailability { .available }

    public func updates() async -> AsyncStream<KeyboardLockSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            let snapshot = state.withLock { state -> KeyboardLockSnapshot in
                state.continuations[id] = continuation
                return Self.snapshot(from: state)
            }
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.continuations[id] = nil }
            }
        }
    }

    public func lock(policy: KeyboardLockPolicy) async throws {
        try await MainActor.run { try activate(policy: policy) }
    }

    /// Installation and teardown share the callback's run loop, preventing overlapping taps
    /// and shutdown racing a partially installed tap.
    @MainActor private func activate(policy: KeyboardLockPolicy) throws {
        try Task.checkCancellation()
#if DEBUG
        Self.debugLog("KeyboardLock requested")
#endif
        if state.withLock({ $0.resources != nil }) { maintainLock() }
        if state.withLock({ $0.isLocked }) { return }

        var isTrusted = AXIsProcessTrusted()
        let shouldRequest = !isTrusted && state.withLock { state -> Bool in
            guard !state.preferences.value.bool(forKey: Self.requestKey) else { return false }
            state.preferences.value.set(true, forKey: Self.requestKey)
            return true
        }
        if shouldRequest {
            let options = [
                "AXTrustedCheckOptionPrompt": true,
            ] as CFDictionary
            isTrusted = AXIsProcessTrustedWithOptions(options)
        }
#if DEBUG
        Self.debugLog("Accessibility trusted: \(isTrusted)")
#endif
        guard isTrusted else {
            let missing: Set<PermissionKind> = [.accessibility]
            publishIssue(.permissionsRequired(missing))
            throw KeyboardLockFailure.permissionsRequired(missing)
        }

        guard !IsSecureEventInputEnabled() else {
            publishIssue(.secureInputEnabled)
            throw KeyboardLockFailure.secureInputEnabled
        }

        let mask = Self.eventMask
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyboardLockEventTapCallback,
            userInfo: refcon
        )
#if DEBUG
        Self.debugLog("CGEventTap created: \(tap != nil)")
#endif
        guard let tap else {
#if DEBUG
            Self.debugLog("CGEventTap enabled: false")
#endif
            publishIssue(.eventTapUnavailable)
            throw KeyboardLockFailure.eventTapUnavailable
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
#if DEBUG
            Self.debugLog("CGEventTap enabled: false")
#endif
            CFMachPortInvalidate(tap)
            publishIssue(.eventTapUnavailable)
            throw KeyboardLockFailure.eventTapUnavailable
        }
        let resources = KeyboardEventTapResources(tap: tap, source: source)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let isEnabled = CGEvent.tapIsEnabled(tap: tap)
#if DEBUG
        Self.debugLog("CGEventTap enabled: \(isEnabled)")
#endif
        guard isEnabled, Self.hasActiveKeyboardFilter() else {
            tearDown(resources)
            publishIssue(.eventTapUnavailable)
            throw KeyboardLockFailure.eventTapUnavailable
        }

        state.withLock { state in
            state.isLocked = true
            state.resources = resources
            state.commandIsDown = false
            state.optionIsDown = false
            state.escapeIsDown = false
            state.emergencyUnlockStartedAt = nil
            state.emergencyUnlockDisplayStartedAt = nil
            state.emergencyHoldDuration = policy.emergencyHoldDuration
            state.needsPublication = false
            state.issue = nil
            state.chordGeneration &+= 1
        }
#if DEBUG
        Self.debugLog("KeyboardLock ACTIVE")
#endif
        let maintenance = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.maintainLock()
        }
        resources.maintenance = maintenance
        RunLoop.main.add(maintenance, forMode: .common)
        publishCurrentSnapshot()
    }

    public func unlock() async { shutdown() }

    public func openPermissionSettings(for _: Set<PermissionKind>) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    public func shutdown() {
        if Thread.isMainThread {
            disable()
        } else {
            DispatchQueue.main.sync { self.disable() }
        }
    }

    private func disable() {
        let result = state.withLock { state -> (KeyboardEventTapResources?, Bool) in
            let resources = state.resources
            let changed = state.isLocked || state.resources != nil || state.issue != nil
            state.isLocked = false
            state.resources = nil
            state.commandIsDown = false
            state.optionIsDown = false
            state.escapeIsDown = false
            state.emergencyUnlockStartedAt = nil
            state.emergencyUnlockDisplayStartedAt = nil
            state.issue = nil
            state.chordGeneration &+= 1
            return (resources, changed)
        }
#if DEBUG
        if result.1 { Self.debugLog("KeyboardLock DISABLED") }
#endif
        if result.1 { publishCurrentSnapshot() }
        tearDown(result.0)
    }

    func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recoverDisabledTap(type: type)
            return Unmanaged.passUnretained(event)
        }

        let shouldSuppress = state.withLock { state -> Bool in
            guard state.isLocked else { return false }
            guard type == .keyDown || type == .keyUp || type == .flagsChanged else { return false }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if type == .keyDown, keyCode == Self.escapeKeyCode { state.escapeIsDown = true }
            if type == .keyUp, keyCode == Self.escapeKeyCode { state.escapeIsDown = false }
            state.commandIsDown = event.flags.contains(.maskCommand)
            state.optionIsDown = event.flags.contains(.maskAlternate)
            let chordHeld = state.commandIsDown && state.optionIsDown && state.escapeIsDown
            let wasHeld = state.emergencyUnlockStartedAt != nil
            if chordHeld != wasHeld {
                state.emergencyUnlockStartedAt = chordHeld ? ContinuousClock.now : nil
                state.emergencyUnlockDisplayStartedAt = nil
                state.chordGeneration &+= 1
                state.needsPublication = true
            }
            return true
        }
        return shouldSuppress ? nil : Unmanaged.passUnretained(event)
    }

    /// All allocation, publishing, diagnostics and emergency completion happen outside
    /// the event callback. The callback only updates scalar state and filters events.
    private func maintainLock() {
        let resources = state.withLock { $0.resources }
        guard let resources else { return }
        if IsSecureEventInputEnabled() {
            failOpen(issue: .secureInputEnabled)
            return
        }
        guard AXIsProcessTrusted(), CGEvent.tapIsEnabled(tap: resources.tap),
              state.withLock({ $0.isLocked }) else {
            failOpen()
            return
        }
        let update = state.withLock { state -> (Bool, Int) in
            let changed = state.needsPublication
            state.needsPublication = false
            if changed, let start = state.emergencyUnlockStartedAt {
                state.emergencyUnlockDisplayStartedAt = Date.now.addingTimeInterval(
                    -start.duration(to: .now).timeInterval
                )
            }
            return (changed, state.chordGeneration)
        }
        if update.0 { publishCurrentSnapshot() }
        completeEmergencyUnlock(generation: update.1)
    }

    private func completeEmergencyUnlock(generation: Int) {
        let shouldUnlock = state.withLock { state -> Bool in
            guard state.isLocked,
                  state.chordGeneration == generation,
                  state.commandIsDown,
                  state.optionIsDown,
                  state.escapeIsDown,
                  let startedAt = state.emergencyUnlockStartedAt
            else { return false }
            return startedAt.duration(to: ContinuousClock.now) >= state.emergencyHoldDuration
        }
        if shouldUnlock {
#if DEBUG
            Self.debugLog("Emergency unlock triggered")
#endif
            shutdown()
        }
    }

    private func recoverDisabledTap(type: CGEventType) {
        let resources = state.withLock { state in
            state.isLocked ? state.resources : nil
        }
        guard let resources else { return }

        CGEvent.tapEnable(tap: resources.tap, enable: true)
        if !CGEvent.tapIsEnabled(tap: resources.tap) {
            // Stop filtering immediately; the maintenance timer publishes and tears down.
            state.withLock { $0.isLocked = false }
        }
    }

    private func failOpen(issue: KeyboardLockIssue = .eventTapDisabled) {
        let resources = state.withLock { state -> KeyboardEventTapResources? in
            let resources = state.resources
            state.isLocked = false
            state.resources = nil
            state.commandIsDown = false
            state.optionIsDown = false
            state.escapeIsDown = false
            state.emergencyUnlockStartedAt = nil
            state.emergencyUnlockDisplayStartedAt = nil
            state.issue = issue
            state.chordGeneration &+= 1
            return resources
        }
#if DEBUG
        Self.debugLog("KeyboardLock FAILED: event tap disabled, Accessibility revoked, or Secure Input enabled")
        Self.debugLog("KeyboardLock DISABLED")
#endif
        tearDown(resources)
        publishCurrentSnapshot()
    }

    private func publishIssue(_ issue: KeyboardLockIssue) {
#if DEBUG
        Self.debugLog("KeyboardLock FAILED: \(issue)")
#endif
        state.withLock { state in
            state.issue = issue
        }
        publishCurrentSnapshot()
    }

    private func tearDown(_ resources: KeyboardEventTapResources?) {
        guard let resources else { return }
        resources.maintenance?.invalidate()
        resources.maintenance = nil
        CGEvent.tapEnable(tap: resources.tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), resources.source, .commonModes)
        CFMachPortInvalidate(resources.tap)
    }

    /// macOS can silently remove unauthorized event types from the requested mask.
    /// An enabled tap alone therefore does not prove all keyboard events are filtered.
    private static func hasActiveKeyboardFilter() -> Bool {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return false }
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(count, &taps, &count) == .success else { return false }
        return taps.contains {
            $0.tappingProcess == ProcessInfo.processInfo.processIdentifier
                && $0.tapPoint == .cgSessionEventTap
                && $0.options == .defaultTap
                && $0.enabled
                && $0.eventsOfInterest & eventMask == eventMask
        }
    }

    private static var eventMask: CGEventMask {
        [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(0) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
    }

    private static func snapshot(from state: borrowing State) -> KeyboardLockSnapshot {
        KeyboardLockSnapshot(
            availability: .available,
            isLocked: state.isLocked,
            emergencyUnlockStartedAt: state.emergencyUnlockDisplayStartedAt,
            issue: state.issue
        )
    }

    private func publishCurrentSnapshot() {
        let emission = state.withLock { state in
            (Self.snapshot(from: state), Array(state.continuations.values))
        }
        for continuation in emission.1 { continuation.yield(emission.0) }
    }

#if DEBUG
    private static func debugLog(_ message: String) {
        print("[KeyboardLock] \(message)")
    }
#endif
}

private let keyboardLockEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<RealKeyboardLockService>.fromOpaque(userInfo).takeUnretainedValue()
    return service.handleTapEvent(type: type, event: event)
}

public final class MockKeyboardLockService: KeyboardLockService {
    private struct State {
        var snapshot: KeyboardLockSnapshot
        var continuations: [UUID: AsyncStream<KeyboardLockSnapshot>.Continuation] = [:]
    }

    private let state: Mutex<State>

    public init(
        snapshot: KeyboardLockSnapshot = KeyboardLockSnapshot(availability: .available)
    ) {
        state = Mutex(State(snapshot: snapshot))
    }

    public func availability() async -> FeatureAvailability {
        state.withLock { $0.snapshot.availability }
    }

    public func updates() async -> AsyncStream<KeyboardLockSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            let snapshot = state.withLock { state -> KeyboardLockSnapshot in
                state.continuations[id] = continuation
                return state.snapshot
            }
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.continuations[id] = nil }
            }
        }
    }

    public func lock(policy: KeyboardLockPolicy) async throws { setLocked(true) }
    public func unlock() async { setLocked(false) }
    public func openPermissionSettings(for permissions: Set<PermissionKind>) {}
    public func shutdown() { setLocked(false) }

    public func publish(_ snapshot: KeyboardLockSnapshot) {
        let emission = state.withLock { state in
            state.snapshot = snapshot
            return (state.snapshot, Array(state.continuations.values))
        }
        for continuation in emission.1 { continuation.yield(emission.0) }
    }

    private func setLocked(_ locked: Bool) {
        let availability = state.withLock { $0.snapshot.availability }
        publish(KeyboardLockSnapshot(availability: availability, isLocked: locked))
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
