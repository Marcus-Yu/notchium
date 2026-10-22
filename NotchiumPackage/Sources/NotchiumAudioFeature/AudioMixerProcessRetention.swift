import NotchiumCore
import NotchiumServices

/// Keeps recently audible rows independently of the live tap topology. A missing HAL
/// client can mean Pause, so the owning application's lifetime decides early removal.
@MainActor
final class AudioMixerProcessRetention {
    var onChange: (@MainActor ([AudioProducingProcess]) -> Void)?
    private let clock: any AppClock
    private var processes: [Int32: AudioProducingProcess] = [:]
    private var expiries: [Int32: Expiry] = [:]
    private var generation = 0
    private var lastSnapshot: [AudioProducingProcess] = []

    private struct Expiry {
        let generation: Int
        let task: Task<Void, Never>
    }

    init(clock: any AppClock) { self.clock = clock }

    isolated deinit { expiries.values.forEach { $0.task.cancel() } }

    func receive(_ activeProcesses: [AudioProducingProcess],
                 retainingMissing: (AudioProducingProcess) -> Bool) {
        var next: [Int32: AudioProducingProcess] = [:]
        for process in activeProcesses where process.isRunningOutput {
            cancelExpiry(for: process.id)
            next[process.id] = process
        }
        for process in processes.values where next[process.id] == nil {
            guard retainingMissing(process) else {
                cancelExpiry(for: process.id)
                continue
            }
            if expiries[process.id] == nil { scheduleExpiry(for: process.id) }
            next[process.id] = AudioProducingProcess(
                id: process.id, bundleID: process.bundleID,
                controllableOutputDeviceIDs: process.controllableOutputDeviceIDs,
                requiresAudioPermission: process.requiresAudioPermission,
                isRunningOutput: false)
        }
        processes = next
        publish()
    }

    func remove(processIDs: Set<Int32>) {
        for id in processIDs {
            cancelExpiry(for: id)
            processes[id] = nil
        }
        publish()
    }

    func reset() {
        expiries.values.forEach { $0.task.cancel() }
        expiries.removeAll()
        processes.removeAll()
        lastSnapshot = []
    }

    private func scheduleExpiry(for id: Int32) {
        generation &+= 1
        let generation = generation
        let task = Task { @concurrent [weak self, clock] in
            do { try await clock.sleep(for: .seconds(180)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.expire(id: id, generation: generation)
        }
        expiries[id] = Expiry(generation: generation, task: task)
    }

    private func expire(id: Int32, generation: Int) {
        guard expiries[id]?.generation == generation else { return }
        expiries[id] = nil
        processes[id] = nil
        publish()
    }

    private func cancelExpiry(for id: Int32) {
        expiries.removeValue(forKey: id)?.task.cancel()
    }

    private func publish() {
        let snapshot = processes.values.sorted { $0.id < $1.id }
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        onChange?(snapshot)
    }
}
