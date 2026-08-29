import Foundation
import NotchiumCore
@testable import NotchiumDynamicIsland

actor ControlledAppClock: AppClock {
    private struct Sleeper {
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var currentDate = Date(timeIntervalSince1970: 0)
    private var sleepers: [UUID: Sleeper] = [:]

    func now() -> Date {
        currentDate
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = Sleeper(continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func releaseAll() {
        let pending = sleepers.values
        sleepers.removeAll()
        for sleeper in pending {
            sleeper.continuation.resume()
        }
    }

    func pendingCount() -> Int {
        sleepers.count
    }

    private func cancel(id: UUID) {
        guard let sleeper = sleepers.removeValue(forKey: id) else { return }
        sleeper.continuation.resume(throwing: CancellationError())
    }
}

func builtInDisplay(
    id: UInt32 = 1,
    frame: CGRect = CGRect(x: 0, y: 0, width: 1512, height: 982),
    includeAuxiliaryAreas: Bool = true,
    primary: Bool = true
) -> NotchiumDisplaySnapshot {
    NotchiumDisplaySnapshot(
        id: NotchiumDisplayID(rawValue: id),
        name: "Built-in \(id)",
        frame: frame,
        safeAreaInsets: NotchiumDisplayInsets(top: 38),
        auxiliaryTopLeftArea: includeAuxiliaryAreas
            ? CGRect(x: frame.minX, y: frame.maxY - 38, width: 650, height: 38)
            : nil,
        auxiliaryTopRightArea: includeAuxiliaryAreas
            ? CGRect(x: frame.minX + 862, y: frame.maxY - 38, width: 650, height: 38)
            : nil,
        isBuiltIn: true,
        isPrimary: primary
    )
}

func externalDisplay(
    id: UInt32 = 2,
    frame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900),
    primary: Bool = true
) -> NotchiumDisplaySnapshot {
    NotchiumDisplaySnapshot(
        id: NotchiumDisplayID(rawValue: id),
        name: "External \(id)",
        frame: frame,
        isBuiltIn: false,
        isPrimary: primary
    )
}

func waitForPendingSleep(
    _ clock: ControlledAppClock,
    count: Int = 1
) async {
    for _ in 0..<100 {
        if await clock.pendingCount() >= count { return }
        await Task.yield()
    }
}

@MainActor
func drainMainActorTasks() async {
    for _ in 0..<10 {
        await Task.yield()
    }
}
