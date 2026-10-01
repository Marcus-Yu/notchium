import Foundation
import Intents
import Security
import NotchiumCore

/// Whether macOS Focus is on. The public API reports on/off only: never which Focus.
public struct FocusSnapshot: Equatable, Sendable {
    public let availability: FeatureAvailability
    /// Nil until macOS has answered (or when Focus status is unavailable).
    public let isFocused: Bool?

    public init(availability: FeatureAvailability, isFocused: Bool? = nil) {
        self.availability = availability
        self.isFocused = isFocused
    }
}

public protocol FocusService: Sendable {
    func availability() async -> FeatureAvailability
    /// Current value first, then changes only.
    func updates() async -> AsyncStream<FocusSnapshot>
}

/// `INFocusStatusCenter` is the only supported source. macOS answers it only for apps signed with
/// the Communication Notifications capability: without that entitlement the authorization request
/// is never answered and `isFocused` reads a constant `false` (verified on macOS 27). Unentitled
/// builds therefore report Focus as unavailable instead of polling a value that cannot change.
/// The status posts no change notification on macOS, so one cached property is re-read every
/// few seconds once access is granted.
@MainActor
public final class RealFocusService: FocusService {
    nonisolated public static let entitlement = "com.apple.developer.usernotifications.communication"
    private let interval: Duration
    private let isEntitled: Bool

    public init(interval: Duration = .seconds(4), isEntitled: Bool = RealFocusService.hasEntitlement()) {
        self.interval = interval
        self.isEntitled = isEntitled
    }

    nonisolated public static func hasEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) else { return false }
        return (value as? Bool) == true
    }

    public func availability() async -> FeatureAvailability {
        guard isEntitled else { return .unavailable(.unsupportedDistribution) }
        return Self.availability(INFocusStatusCenter.default.authorizationStatus)
    }

    public func updates() async -> AsyncStream<FocusSnapshot> {
        guard isEntitled else {
            return AsyncStream { continuation in
                continuation.yield(FocusSnapshot(availability: .unavailable(.unsupportedDistribution)))
                continuation.finish()
            }
        }
        let center = INFocusStatusCenter.default
        // The answer arrives through polling; the request itself is never awaited.
        if center.authorizationStatus == .notDetermined { center.requestAuthorization { _ in } }
        let interval = interval
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                var last: FocusSnapshot?
                while !Task.isCancelled {
                    let status = center.authorizationStatus
                    let snapshot = FocusSnapshot(availability: Self.availability(status),
                                                 isFocused: status == .authorized ? center.focusStatus.isFocused : nil)
                    if snapshot != last {
                        last = snapshot
                        continuation.yield(snapshot)
                    }
                    do { try await Task.sleep(for: interval) } catch { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated static func availability(_ status: INFocusStatusAuthorizationStatus) -> FeatureAvailability {
        switch status {
        case .authorized: .available
        case .denied: .unavailable(.permissionDenied)
        case .restricted: .unavailable(.permissionRestricted)
        case .notDetermined: .unavailable(.permissionNotDetermined)
        @unknown default: .unavailable(.temporarilyUnavailable)
        }
    }
}

/// Test double: values pushed with `send` reach every subscriber.
public final class MockFocusService: FocusService, @unchecked Sendable {
    private let lock = NSLock()
    private var current: FocusSnapshot
    private var continuations: [UUID: AsyncStream<FocusSnapshot>.Continuation] = [:]

    public init(snapshot: FocusSnapshot = FocusSnapshot(availability: .available, isFocused: false)) {
        current = snapshot
    }

    public func availability() async -> FeatureAvailability {
        lock.withLock { current.availability }
    }

    public func updates() async -> AsyncStream<FocusSnapshot> {
        let (stream, continuation) = AsyncStream<FocusSnapshot>.makeStream()
        let id = UUID()
        let first = lock.withLock {
            continuations[id] = continuation
            return current
        }
        continuation.yield(first)
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            _ = self.lock.withLock { self.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    public func send(isFocused: Bool) {
        let (snapshot, targets) = lock.withLock {
            current = FocusSnapshot(availability: .available, isFocused: isFocused)
            return (current, Array(continuations.values))
        }
        targets.forEach { $0.yield(snapshot) }
    }
}
