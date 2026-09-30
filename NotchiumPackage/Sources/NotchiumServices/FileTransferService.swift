import Foundation
import NotchiumCore

/// What the publishing process says it is doing. Anything else is `.other`.
public enum TransferOperation: String, Equatable, Sendable {
    case downloading, copying, receiving, decompressing, other
}

public enum TransferPhase: Equatable, Sendable {
    case active
    case paused
    case completed
    /// Only sources that report an error use this; published file progress never does.
    case failed(String?)
    /// Unpublished before completion (cancelled, or the publishing app quit/stopped).
    case stopped

    public var isTerminal: Bool {
        switch self {
        case .active, .paused: false
        case .completed, .failed, .stopped: true
        }
    }
}

/// One file operation as reported by its publisher. Fields the OS does not expose stay nil.
public struct TransferSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let operation: TransferOperation
    public let phase: TransferPhase
    /// Nil when the publisher reports no measurable total (shown as indeterminate).
    public let fraction: Double?
    public let completedBytes: Int64?
    public let totalBytes: Int64?
    /// Only when the publisher supplies it; never computed from guesses.
    public let estimatedTimeRemaining: TimeInterval?
    public let fileURL: URL?
    public let startedAt: Date
    public let updatedAt: Date

    public init(id: String, displayName: String, operation: TransferOperation, phase: TransferPhase,
                fraction: Double?, completedBytes: Int64? = nil, totalBytes: Int64? = nil,
                estimatedTimeRemaining: TimeInterval? = nil, fileURL: URL? = nil,
                startedAt: Date, updatedAt: Date) {
        self.id = id
        self.displayName = displayName
        self.operation = operation
        self.phase = phase
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.fileURL = fileURL
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var destinationFolder: URL? { fileURL?.deletingLastPathComponent() }
}

public protocol FileTransferService: Sendable {
    func availability() async -> FeatureAvailability
    func updates() async -> AsyncStream<TransferSnapshot>
}

/// Observes file-operation progress that other processes publish through the supported
/// `NSProgress` file-subscription API: Finder copies into, browser downloads to, and AirDrop
/// receives into the observed folders. There is no public API for arbitrary Finder
/// operations elsewhere, and nothing here polls file sizes or scans directories.
@MainActor
public final class RealFileTransferService: FileTransferService {
    private final class Tracked {
        let id = UUID().uuidString
        let progress: Progress
        let startedAt = Date()
        var observations: [NSKeyValueObservation] = []
        var lastSent: TransferSnapshot?
        var flushScheduled = false
        init(progress: Progress) { self.progress = progress }
    }

    private let folders: [URL]
    private var subscriptions: [Any] = []
    private var tracked: [ObjectIdentifier: Tracked] = [:]
    private var continuations: [UUID: AsyncStream<TransferSnapshot>.Continuation] = [:]
    /// Progress KVO can fire per chunk; the notch needs a few updates a second at most.
    private let flushInterval: Duration = .milliseconds(250)

    public init(folders: [URL]? = nil) {
        self.folders = folders
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
    }

    private var access: FeatureAvailability = .available

    /// Re-probes when previously denied, so a grant in System Settings is picked up.
    public func availability() async -> FeatureAvailability {
        if access != .available { probeAccess() }
        return access
    }

    public func updates() async -> AsyncStream<TransferSnapshot> {
        let token = UUID()
        let pair = AsyncStream<TransferSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(16))
        continuations[token] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.removeObserver(token) }
        }
        if subscriptions.isEmpty { subscribe() }
        return pair.stream
    }

    /// Progress subscription itself needs no folder access, but acting on a finished transfer
    /// (Show in Finder, Add to Shelf) reads the folder. That legitimate read-only access is made
    /// when monitoring starts, so macOS asks once, up front, instead of at a random later click.
    private func probeAccess() {
        access = .available
        for folder in folders {
            do { _ = try FileManager.default.contentsOfDirectory(atPath: folder.path) }
            catch {
                let code = (error as NSError).code
                access = code == NSFileReadNoPermissionError || code == Int(EPERM)
                    ? .unavailable(.permissionDenied) : .unavailable(.temporarilyUnavailable)
            }
        }
    }

    private func subscribe() {
        probeAccess()
        for folder in folders {
            // The handler runs on the main thread (verified); it is still hopped explicitly.
            let token = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
                let box = ProgressBox(progress)
                MainActor.assumeIsolated { self?.published(box.progress) }
                return { [weak self] in
                    MainActor.assumeIsolated { self?.unpublished(box.progress) }
                }
            }
            subscriptions.append(token)
        }
    }

    private func removeObserver(_ token: UUID) {
        continuations[token] = nil
        guard continuations.isEmpty else { return }
        subscriptions.forEach(Progress.removeSubscriber)
        subscriptions.removeAll()
        tracked.values.forEach { $0.observations.forEach { $0.invalidate() } }
        tracked.removeAll()
    }

    private func published(_ progress: Progress) {
        let entry = Tracked(progress: progress)
        tracked[ObjectIdentifier(progress)] = entry
        entry.observations.append(progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let box = ProgressBox(progress)
            Task { @MainActor [weak self] in self?.scheduleFlush(box.progress) }
        })
        entry.observations.append(progress.observe(\.isPaused) { [weak self] progress, _ in
            let box = ProgressBox(progress)
            Task { @MainActor [weak self] in self?.scheduleFlush(box.progress) }
        })
        send(entry, phase: progress.isPaused ? .paused : .active)
    }

    private func unpublished(_ progress: Progress) {
        guard let entry = tracked.removeValue(forKey: ObjectIdentifier(progress)) else { return }
        entry.observations.forEach { $0.invalidate() }
        let finished = progress.isFinished || progress.fractionCompleted >= 0.999
            || (progress.totalUnitCount > 0 && progress.completedUnitCount >= progress.totalUnitCount)
        send(entry, phase: finished ? .completed : .stopped)
    }

    private func scheduleFlush(_ progress: Progress) {
        guard let entry = tracked[ObjectIdentifier(progress)], !entry.flushScheduled else { return }
        entry.flushScheduled = true
        Task { @MainActor [weak self, flushInterval] in
            try? await Task.sleep(for: flushInterval)
            guard let self, let entry = self.tracked[ObjectIdentifier(progress)] else { return }
            entry.flushScheduled = false
            self.send(entry, phase: progress.isPaused ? .paused : .active)
        }
    }

    private func send(_ entry: Tracked, phase: TransferPhase) {
        let snapshot = Self.snapshot(entry.progress, id: entry.id, phase: phase, startedAt: entry.startedAt)
        // Unchanged whole-percent values are not worth an update.
        if let last = entry.lastSent, last.phase == snapshot.phase,
           last.fraction.map({ Int($0 * 100) }) == snapshot.fraction.map({ Int($0 * 100) }) { return }
        entry.lastSent = snapshot
        continuations.values.forEach { $0.yield(snapshot) }
    }

    /// `userInfo` is read directly: the typed accessors can be empty on a fresh proxy (verified).
    static func snapshot(_ progress: Progress, id: String, phase: TransferPhase, startedAt: Date) -> TransferSnapshot {
        let fileURL = progress.userInfo[.fileURLKey] as? URL
        let kind = progress.userInfo[.fileOperationKindKey] as? Progress.FileOperationKind
        let operation: TransferOperation = switch kind {
        case .downloading?: .downloading
        case .copying?: .copying
        case .receiving?: .receiving
        case .decompressingAfterDownloading?: .decompressing
        default: .other
        }
        let determinate = progress.totalUnitCount > 0 && !progress.isIndeterminate
        let isBytes = progress.kind == .file
        let name = fileURL.map { $0.deletingPathExtension().pathExtension == "download"
            ? $0.deletingPathExtension().lastPathComponent : $0.lastPathComponent }
        return TransferSnapshot(
            id: id, displayName: name ?? progress.localizedDescription ?? "File",
            operation: operation, phase: phase,
            fraction: determinate ? progress.fractionCompleted : nil,
            completedBytes: determinate && isBytes ? progress.completedUnitCount : nil,
            totalBytes: determinate && isBytes ? progress.totalUnitCount : nil,
            estimatedTimeRemaining: progress.estimatedTimeRemaining,
            fileURL: fileURL, startedAt: startedAt, updatedAt: Date())
    }
}

/// Progress proxies are delivered and observed on the main thread; the box only carries one
/// across the Sendable-checked callback boundary.
private struct ProgressBox: @unchecked Sendable {
    let progress: Progress
    init(_ progress: Progress) { self.progress = progress }
}

public struct MockFileTransferService: FileTransferService {
    public let snapshots: [TransferSnapshot]
    public init(snapshots: [TransferSnapshot] = []) { self.snapshots = snapshots }
    public func availability() async -> FeatureAvailability { .available }
    public func updates() async -> AsyncStream<TransferSnapshot> {
        AsyncStream { continuation in
            snapshots.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}
