import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation

@MainActor
@Observable
public final class CaffeineControlModel: NotchCaffeineControlling {
    public let lidAwake = LidAwakeController()
    public private(set) var mode: CaffeineMode = .off
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let service: any CaffeineService
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var operation: Task<Void, Never>?

    public init(service: any CaffeineService) {
        self.service = service
    }

    deinit {
        observation?.cancel()
        operation?.cancel()
    }

    public func start() {
        guard observation == nil else { return }
        observation = Task { [weak self, service] in
            for await snapshot in await service.updates() {
                guard !Task.isCancelled, let self else { return }
                self.mode = snapshot.mode
                self.lidAwake.setCaffeineActive(snapshot.mode.isActive)
            }
        }
    }

    public func stop() {
        observation?.cancel(); observation = nil
        operation?.cancel(); operation = nil
        service.shutdown()
        lidAwake.disable()
        mode = .off
        isBusy = false
    }

    public func cycleMode() {
        setMode(mode == .off ? .system : .off)
    }

    public func keepDisplayAwake() {
        setMode(.systemAndDisplay)
    }

    private func setMode(_ target: CaffeineMode) {
        guard !isBusy else { return }
        isBusy = true
        operation?.cancel()
        operation = Task { [weak self, service] in
            do {
                try await service.setMode(target)
                guard !Task.isCancelled, let self else { return }
                self.errorMessage = nil
                self.mode = target
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.errorMessage = "Could not change the keep-awake state."
            }
            self?.isBusy = false
        }
    }
}
