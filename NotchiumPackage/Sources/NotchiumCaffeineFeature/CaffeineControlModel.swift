import Foundation
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation

@MainActor
@Observable
public final class CaffeineControlModel: NotchCaffeineControlling {
    public let pressInteraction = CaffeinePressInteraction()
    public let lidAwake = LidAwakeController()
    public private(set) var mode: CaffeineMode = .off
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    public private(set) var selectedDuration: CaffeineDuration?
    public private(set) var expiresAt: Date?

    public var needsClosedLidApproval: Bool { lidAwake.needsApproval }
    public var statusMessage: String? {
        errorMessage ?? (mode.isActive && automaticallyEnableClosedLid && !lidAwake.isActive ? lidAwake.message : nil)
    }

    @ObservationIgnored private let service: any CaffeineService
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private let automaticallyEnableClosedLid: Bool
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var expiryGeneration = 0

    public init(service: any CaffeineService, clock: any AppClock = ContinuousAppClock(),
                automaticallyEnableClosedLid: Bool = false) {
        self.service = service
        self.clock = clock
        self.automaticallyEnableClosedLid = automaticallyEnableClosedLid
    }

    deinit {
        observation?.cancel()
        operation?.cancel()
        expiryTask?.cancel()
    }

    public func start() {
        guard observation == nil else { return }
        observation = Task { [weak self, service] in
            for await snapshot in await service.updates() {
                guard !Task.isCancelled, let self else { return }
                self.mode = snapshot.mode
                self.lidAwake.setCaffeineActive(snapshot.mode.isActive)
                if !snapshot.mode.isActive { self.cancelExpiry() }
            }
        }
    }

    public func stop() {
        pressInteraction.cancel()
        observation?.cancel(); observation = nil
        operation?.cancel(); operation = nil
        cancelExpiry()
        service.shutdown()
        lidAwake.disable()
        mode = .off
        isBusy = false
    }

    public func cycleMode() {
        setMode(mode == .off ? .systemAndDisplay : .off)
    }

    public func keepDisplayAwake() {
        setMode(.systemAndDisplay)
    }

    public func keepAwake(for duration: CaffeineDuration) {
        setMode(.systemAndDisplay, duration: duration)
    }

    public func openClosedLidApproval() { lidAwake.openApprovalSettings() }

    private func setMode(_ target: CaffeineMode, duration: CaffeineDuration? = nil) {
        guard !isBusy else { return }
        isBusy = true
        operation?.cancel()
        operation = Task { [weak self, service] in
            do {
                if self?.mode != target { try await service.setMode(target) }
                guard !Task.isCancelled, let self else { return }
                self.errorMessage = nil
                self.mode = target
                self.lidAwake.setCaffeineActive(target.isActive)
                if target.isActive, self.automaticallyEnableClosedLid, !self.lidAwake.isEnabled {
                    let approvalAlreadyPending = self.lidAwake.needsApproval
                    self.lidAwake.enable()
                    if self.lidAwake.needsApproval, !approvalAlreadyPending {
                        self.lidAwake.openApprovalSettings()
                    }
                }
                self.scheduleExpiry(target.isActive ? duration : nil)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.errorMessage = "Could not change the keep-awake state."
            }
            self?.isBusy = false
        }
    }

    private func cancelExpiry() {
        expiryGeneration &+= 1
        expiryTask?.cancel(); expiryTask = nil
        selectedDuration = nil
        expiresAt = nil
    }

    private func scheduleExpiry(_ duration: CaffeineDuration?) {
        cancelExpiry()
        guard let duration else { return }
        selectedDuration = duration
        let generation = expiryGeneration
        expiryTask = Task { [weak self, clock] in
            let now = await clock.now()
            guard !Task.isCancelled, self?.expiryGeneration == generation else { return }
            self?.expiresAt = now.addingTimeInterval(TimeInterval(duration.rawValue * 60))
            do { try await clock.sleep(for: duration.duration) } catch { return }
            // A pending replacement must finish before the old deadline can turn it off.
            await self?.operation?.value
            guard let self, !Task.isCancelled, self.expiryGeneration == generation else { return }
            self.setMode(.off)
        }
    }
}
