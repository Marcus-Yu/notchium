import AppKit
import Foundation
import NotchiumCore

/// Admission happens before application services are constructed. A replacement waits
/// for older copies to quit normally, so they cannot keep using a replaced app identity.
@MainActor
public final class ApplicationInstanceCoordinator {
    public enum Outcome: Equatable, Sendable {
        case ready, superseded, terminationRefused, timedOut
    }

    struct Instance: Hashable, Sendable {
        let processIdentifier: Int32
        let bundleIdentifier: String?
        let launchDate: Date?

        func isNewer(than other: Instance) -> Bool {
            let date = launchDate ?? .distantPast
            let otherDate = other.launchDate ?? .distantPast
            return date == otherDate ? processIdentifier > other.processIdentifier : date > otherDate
        }
    }

    private let current: Instance
    private let snapshots: @MainActor () -> [Instance]
    private let terminate: @MainActor (Instance) -> Bool
    private let clock: any AppClock
    private let timeout: Duration
    private let pollInterval: Duration

    public convenience init() {
        let application = NSRunningApplication.current
        let current = Self.snapshot(application)
        self.init(current: current, snapshots: {
            guard let identifier = current.bundleIdentifier else { return [] }
            return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .filter { !$0.isTerminated }.map { Self.snapshot($0) }
        }, terminate: { instance in
            guard let application = NSRunningApplication(processIdentifier: instance.processIdentifier),
                  application.bundleIdentifier == instance.bundleIdentifier,
                  application.launchDate == instance.launchDate else {
                // The old process has gone; never send a quit to a reused PID.
                return true
            }
            return application.isTerminated || application.terminate()
        })
    }

    init(current: Instance, snapshots: @escaping @MainActor () -> [Instance],
         terminate: @escaping @MainActor (Instance) -> Bool,
         clock: any AppClock = ContinuousAppClock(), timeout: Duration = .seconds(5),
         pollInterval: Duration = .milliseconds(50)) {
        precondition(timeout >= .zero && pollInterval > .zero)
        self.current = current
        self.snapshots = snapshots
        self.terminate = terminate
        self.clock = clock
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    public func waitForOlderInstancesToExit() async throws -> Outcome {
        var requested: Set<Instance> = []
        var remaining = timeout
        while true {
            try Task.checkCancellation()
            let peers = snapshots().filter {
                $0.bundleIdentifier == current.bundleIdentifier
                    && $0.processIdentifier != current.processIdentifier
            }
            // Every copy uses the same total ordering, including simultaneous launches.
            guard !peers.contains(where: { $0.isNewer(than: current) }) else { return .superseded }
            guard !peers.isEmpty else { return .ready }
            for peer in peers where requested.insert(peer).inserted {
                guard terminate(peer) else { return .terminationRefused }
            }
            guard remaining > .zero else { return .timedOut }
            let delay = min(pollInterval, remaining)
            try await clock.sleep(for: delay)
            remaining -= delay
        }
    }

    private static func snapshot(_ application: NSRunningApplication) -> Instance {
        Instance(processIdentifier: application.processIdentifier,
                 bundleIdentifier: application.bundleIdentifier, launchDate: application.launchDate)
    }
}
