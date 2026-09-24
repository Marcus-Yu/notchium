import Foundation

/// The serial queue owns power state, connection ownership, and the lease deadline.
final class Helper: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.marcusyu.notchium.lid-awake.power")
    private let power = PowerOverride()
    private var owner: UUID?
    private var deadline: ContinuousClock.Instant?
    private var timer: DispatchSourceTimer?
    private var signalSource: DispatchSourceSignal?

    override init() {
        super.init()
        queue.sync { try? power.recover() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.checkLease() }
        timer.resume()
        self.timer = timer
        signal(SIGTERM, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        signalSource.setEventHandler { [weak self] in
            guard let self else { exit(0) }
            do { try self.power.restore(); exit(0) } catch { exit(1) }
        }
        signalSource.resume()
        self.signalSource = signalSource
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(LidAwakeIdentity.requirement(identifier: "com.marcusyu.notchium"))
        let id = UUID()
        connection.exportedInterface = NSXPCInterface(with: LidAwakeProtocol.self)
        connection.exportedObject = Client(helper: self, id: id)
        connection.invalidationHandler = { [weak self] in self?.release(id: id, reply: { _, _ in }) }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume()
        return true
    }

    func renew(id: UUID, reply: @escaping @Sendable (Bool, String) -> Void) {
        queue.async {
            guard self.owner == nil || self.owner == id else {
                reply(false, "Another Notchium session owns closed-lid mode.")
                return
            }
            do {
                try self.power.acquire()
                self.owner = id
                self.deadline = .now + .seconds(15)
                reply(true, "Closed-lid keep-awake is active.")
            } catch {
                self.owner = nil
                self.deadline = nil
                try? self.power.restore()
                reply(false, (error as? PowerOverride.Failure)?.rawValue ?? "Closed-lid mode could not start.")
            }
        }
    }

    func release(id: UUID, reply: @escaping @Sendable (Bool, String) -> Void) {
        queue.async {
            guard self.owner == nil || self.owner == id else { reply(false, "Another session owns the lease."); return }
            self.owner = nil
            self.deadline = nil
            do { try self.power.restore(); reply(true, "Normal sleep restored.") }
            catch { reply(false, "Could not restore sleep; the helper will keep retrying.") }
        }
    }

    private func checkLease() {
        if deadline == nil || ContinuousClock.now >= deadline! || !power.safeToKeepAwake {
            owner = nil
            deadline = nil
            try? power.restore()
        }
    }
}

private final class Client: NSObject, LidAwakeProtocol {
    let helper: Helper
    let id: UUID
    init(helper: Helper, id: UUID) { self.helper = helper; self.id = id }
    func renew(reply: @escaping @Sendable (Bool, String) -> Void) { helper.renew(id: id, reply: reply) }
    func releaseLease(reply: @escaping @Sendable (Bool, String) -> Void) { helper.release(id: id, reply: reply) }
}

guard geteuid() == 0 else { exit(1) }
let helper = Helper()
let listener = NSXPCListener(machServiceName: LidAwakeIdentity.service)
listener.delegate = helper
listener.resume()
RunLoop.current.run()
