import Foundation
import NotchiumCore
import Observation
import ServiceManagement

@MainActor
@Observable
public final class LidAwakeController {
    public private(set) var isEnabled = false
    public private(set) var isActive = false
    public private(set) var needsApproval = false
    public private(set) var message = "Off. Ordinary Caffeine does not prevent lid-close sleep."
    @ObservationIgnored private var caffeineActive = false
    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastReply: ContinuousClock.Instant?
    @ObservationIgnored private let service = SMAppService.daemon(plistName: "com.marcusyu.notchium.lid-awake.plist")

    public init() {}

    public func enable() {
        guard DistributionProfile.current == .developerID else {
            message = "Closed-lid mode is available only in the direct-download edition."
            return
        }
        do {
            if service.status == .notRegistered { try service.register() }
            needsApproval = service.status == .requiresApproval
            guard service.status == .enabled else {
                message = needsApproval
                    ? "Approve Notchium in System Settings → General → Login Items & Extensions, then enable this toggle again."
                    : "The signed closed-lid helper is unavailable. Install the direct-download app to enable it."
                return
            }
            isEnabled = true
            message = "Ready. Closed-lid mode starts when Caffeine is active."
            reconcile()
        } catch {
            message = "Could not register the closed-lid helper: \(error.localizedDescription)"
        }
    }

    public func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }

    public func setCaffeineActive(_ active: Bool) {
        caffeineActive = active
        reconcile()
    }

    public func disable() {
        isEnabled = false
        stopLease()
    }

    public func removeHelper() async {
        disable()
        // Do not unregister a daemon before it confirms restoration. A failed or
        // disconnected helper stays registered so its watchdog can restore sleep.
        if service.status == .requiresApproval || service.status == .notRegistered {
            do { try await service.unregister(); needsApproval = false; message = "Closed-lid helper removed." }
            catch { message = "Could not remove the helper: \(error.localizedDescription)" }
            return
        }
        connectIfNeeded()
        guard let connection else { return }
        let token = generation
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ @Sendable _ in }) as? LidAwakeProtocol else { return }
        proxy.releaseLease { [weak self] success, detail in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                guard success else { self.message = detail; return }
                do {
                    try await self.service.unregister()
                    // An intentional teardown is not a helper failure.
                    self.connection?.invalidationHandler = nil
                    self.connection?.interruptionHandler = nil
                    self.connection?.invalidate()
                    self.connection = nil
                    self.needsApproval = false
                    self.message = "Closed-lid helper removed."
                } catch { self.message = "Could not remove the helper: \(error.localizedDescription)" }
            }
        }
    }

    private func reconcile() {
        // Disabled controllers have no lease. Preserve approval/failure guidance while
        // ordinary Caffeine snapshots arrive instead of replacing it with an Off message.
        guard isEnabled else { return }
        guard caffeineActive else { stopLease(); return }
        guard heartbeat == nil else { return }
        generation &+= 1
        let token = generation
        lastReply = .now
        connectIfNeeded()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let lastReply = self.lastReply, lastReply.duration(to: .now) > .seconds(10) {
                    self.connectionFailed()
                    return
                }
                self.renew(token: token)
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    private func connectIfNeeded() {
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: LidAwakeIdentity.service, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: LidAwakeProtocol.self)
            connection.setCodeSigningRequirement(LidAwakeIdentity.requirement(identifier: LidAwakeIdentity.service))
            // XPC calls these (and proxy error handlers) on its private queue: they must be
            // nonisolated and hop explicitly, or Swift 6 traps on entry off the main thread.
            let identity = ObjectIdentifier(connection)
            connection.invalidationHandler = { @Sendable [weak self] in
                Task { @MainActor in
                    // A replaced or intentionally torn-down connection is not a helper failure.
                    guard let self, self.connection.map(ObjectIdentifier.init) == identity else { return }
                    self.connectionFailed()
                }
            }
            connection.interruptionHandler = connection.invalidationHandler
            connection.resume()
            self.connection = connection
        }
    }

    private func renew(token: Int) {
        guard let connection else { return }
        let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.connectionFailed()
            }
        } as? LidAwakeProtocol
        proxy?.renew { [weak self] success, detail in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.lastReply = .now
                self.isActive = success
                self.message = detail
                if !success {
                    self.isEnabled = false
                    self.stopLease()
                    self.message = detail
                }
            }
        }
    }

    private func connectionFailed() {
        isEnabled = false
        stopLease()
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        connection = nil
        message = "Connection to the closed-lid helper failed. Its lease expires within 15 seconds."
    }

    private func stopLease() {
        generation &+= 1
        heartbeat?.cancel()
        heartbeat = nil
        isActive = false
        message = isEnabled ? "Ready. Closed-lid mode starts when Caffeine is active." : "Off. Restoring normal sleep if needed."
        let token = generation
        let proxy = connection?.remoteObjectProxyWithErrorHandler { @Sendable _ in } as? LidAwakeProtocol
        proxy?.releaseLease { [weak self] success, detail in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.message = success && self.isEnabled
                    ? "Ready. Closed-lid mode starts when Caffeine is active."
                    : detail
            }
        }
    }
}
