import Foundation
import NotchiumCore
import Synchronization

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
        let samples = TransferSampleBuffer()
        var flushTask: Task<Void, Never>?
        init(progress: Progress) { self.progress = progress }
    }

    private let folders: [URL]
    private var subscriptions: [Any] = []
    private var tracked: [ObjectIdentifier: Tracked] = [:]
    private var continuations: [UUID: AsyncStream<TransferSnapshot>.Continuation] = [:]
    private var subscriptionGeneration = 0
    /// Progress KVO can fire per chunk; the notch needs a few updates a second at most.
    private let flushInterval: Duration = .milliseconds(250)

    public init(folders: [URL]? = nil) {
        self.folders = folders
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
    }

    isolated deinit { stopObservation() }

    private var access: FeatureAvailability = .available

    /// Re-probes when previously denied, so a grant in System Settings is picked up.
    public func availability() async -> FeatureAvailability {
        if access != .available { probeAccess() }
        return access
    }

    public func updates() async -> AsyncStream<TransferSnapshot> {
        let token = UUID()
        let pair = AsyncStream<TransferSnapshot>.makeStream(bufferingPolicy: .unbounded)
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
        subscriptionGeneration &+= 1
        let generation = subscriptionGeneration
        probeAccess()
        for folder in folders {
            // The handler runs on the main thread (verified); it is still hopped explicitly.
            let token = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
                let box = ProgressBox(progress)
                let id = MainActor.assumeIsolated {
                    guard let self, self.subscriptionGeneration == generation else { return nil as String? }
                    return self.published(box.progress)
                }
                return { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.subscriptionGeneration == generation else { return }
                        self.unpublished(box.progress, id: id)
                    }
                }
            }
            subscriptions.append(token)
        }
    }

    private func removeObserver(_ token: UUID) {
        continuations[token] = nil
        guard continuations.isEmpty else { return }
        stopObservation()
    }

    private func stopObservation() {
        subscriptionGeneration &+= 1
        subscriptions.forEach(Progress.removeSubscriber)
        subscriptions.removeAll()
        tracked.values.forEach {
            $0.flushTask?.cancel()
            $0.observations.forEach { $0.invalidate() }
        }
        tracked.removeAll()
    }

    func published(_ progress: Progress) -> String {
        let key = ObjectIdentifier(progress)
        // Overlapping folder subscriptions must not give one progress proxy a new identity.
        if let entry = tracked[key] { return entry.id }
        let entry = Tracked(progress: progress)
        tracked[key] = entry
        let id = entry.id
        let startedAt = entry.startedAt
        let samples = entry.samples
        let capture: @Sendable (Progress) -> Void = { [weak self] progress in
            // KVO's value is read NOW, before a later publisher reset/unpublish or actor hop.
            // The small synchronized mailbox also preserves terminal evidence if unpublish
            // reaches the main actor before this callback's queued delivery.
            let snapshot = Self.snapshot(progress, id: id, phase: Self.phase(progress), startedAt: startedAt)
            // At most one queued actor delivery per proxy. KVO's terminal evidence is
            // still latched synchronously before unpublish, regardless of delivery order.
            guard samples.record(snapshot) else { return }
            Task { @MainActor [weak self] in self?.sampleReceived(key: key, id: id) }
        }
        entry.observations = [
            progress.observe(\.fractionCompleted) { progress, _ in capture(progress) },
            progress.observe(\.isFinished) { progress, _ in capture(progress) },
            progress.observe(\.isPaused) { progress, _ in capture(progress) },
            progress.observe(\.isCancelled) { progress, _ in capture(progress) }
        ]
        samples.record(Self.snapshot(progress, id: id, phase: Self.phase(progress), startedAt: startedAt))
        samples.deliveryHandled()
        send(entry, snapshot: Self.snapshot(progress, id: id,
            phase: progress.isPaused ? .paused : .active, startedAt: startedAt))
        return id
    }

    func unpublished(_ progress: Progress, id: String?) {
        let key = ObjectIdentifier(progress)
        guard let entry = tracked[key], entry.id == id else { return }
        let captured = entry.samples.latest
        // Final file metadata is read now: browsers can rename the temporary file before unpublishing.
        let current = Self.snapshot(progress, id: entry.id, phase: Self.phase(progress), startedAt: entry.startedAt)
        let fileURL = current.fileURL ?? captured?.fileURL
        let totalUnits = progress.totalUnitCount > 0 ? progress.totalUnitCount : captured?.totalBytes ?? 0
        let phase = Self.outcome(latched: captured?.phase, atUnpublish: current.phase,
                                 fileIsComplete: Self.fileIsComplete(at: fileURL, totalBytes: totalUnits))
        // Completion reports full counts even when the publisher reset them or never sent its last update.
        let evidence = captured?.phase == .completed ? captured : nil
        let done = phase == .completed
        let totalBytes = evidence?.totalBytes ?? current.totalBytes
        send(entry, snapshot: TransferSnapshot(id: entry.id, displayName: current.displayName,
            operation: current.operation, phase: phase,
            fraction: done ? (evidence?.fraction ?? current.fraction).map { _ in 1 } : current.fraction,
            completedBytes: done ? totalBytes : current.completedBytes,
            totalBytes: done ? totalBytes : current.totalBytes,
            estimatedTimeRemaining: current.estimatedTimeRemaining,
            fileURL: fileURL, startedAt: entry.startedAt, updatedAt: current.updatedAt))
        tracked[key] = nil
        entry.flushTask?.cancel()
        entry.observations.forEach { $0.invalidate() }
    }

    private func sampleReceived(key: ObjectIdentifier, id: String) {
        guard let entry = tracked[key], entry.id == id else { return }
        entry.samples.deliveryHandled()
        if entry.samples.latest?.phase.isTerminal == true {
            entry.flushTask?.cancel()
            entry.flushTask = nil
            // Capture the outcome now, but keep the existing UI completion point at unpublish.
            return
        }
        guard entry.flushTask == nil else { return }
        entry.flushTask = Task { @MainActor [weak self, flushInterval] in
            do { try await Task.sleep(for: flushInterval) } catch { return }
            // A task from a previous publication never flushes a reused progress object.
            guard let self, let entry = self.tracked[key], entry.id == id else { return }
            entry.flushTask = nil
            if entry.samples.latest?.phase.isTerminal != true { self.send(entry) }
        }
    }

    private func send(_ entry: Tracked, snapshot supplied: TransferSnapshot? = nil) {
        guard let snapshot = supplied ?? entry.samples.latest else { return }
        if let last = entry.lastSent, last.phase.isTerminal { return }
        // Unchanged whole-percent values are not worth an update; terminal events bypass throttling.
        if let last = entry.lastSent, last.phase == snapshot.phase,
           last.fraction.map({ Int($0 * 100) }) == snapshot.fraction.map({ Int($0 * 100) }) { return }
        entry.lastSent = snapshot
        continuations.values.forEach { $0.yield(snapshot) }
    }

    /// The single terminal gate. The first authoritative evidence wins and never changes:
    /// - completion: the publisher reported finished/full counts (latched from KVO, or read now);
    /// - cancellation: `isCancelled` before any completion;
    /// - failure: never; an unpublish carries no error.
    /// The publication ending is not evidence by itself. Firefox-based browsers running several
    /// downloads throttle their last update and unpublish finished downloads below 100% (traced),
    /// so the bytes on disk decide; a short or missing file is Stopped.
    nonisolated static func outcome(latched: TransferPhase?, atUnpublish current: TransferPhase,
                                    fileIsComplete: @autoclosure () -> Bool) -> TransferPhase {
        if let latched, latched.isTerminal { return latched }
        if current.isTerminal { return current }
        return fileIsComplete() ? .completed : .stopped
    }

    /// A regular file at the finished location holding exactly the published byte total.
    /// One read at unpublish; nothing polls.
    nonisolated static func fileIsComplete(at url: URL?, totalBytes: Int64) -> Bool {
        guard let url, totalBytes > 0 else { return false }
        return [TransferSnapshot.finishedFileURL(url), url].contains { candidate in
            let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values?.isRegularFile == true && values?.fileSize.map(Int64.init) == totalBytes
        }
    }

    nonisolated static func phase(_ progress: Progress) -> TransferPhase {
        let finished = progress.isFinished || progress.fractionCompleted >= 1
            || (progress.totalUnitCount > 0 && progress.completedUnitCount >= progress.totalUnitCount)
        if finished { return .completed }
        if progress.isCancelled { return .stopped }
        return progress.isPaused ? .paused : .active
    }

    /// `userInfo` is read directly: the typed accessors can be empty on a fresh proxy (verified).
    nonisolated static func snapshot(_ progress: Progress, id: String, phase: TransferPhase, startedAt: Date) -> TransferSnapshot {
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

/// A KVO callback can run before its main-actor delivery. Preserve immutable completion
/// evidence synchronously; presentation mutation still has exactly one main-actor path.
final class TransferSampleBuffer: Sendable {
    private struct State {
        var latest: TransferSnapshot?
        var deliveryPending = false
    }
    private let sample = Mutex(State())
    var latest: TransferSnapshot? { sample.withLock { $0.latest } }

    @discardableResult
    func record(_ incoming: TransferSnapshot) -> Bool {
        sample.withLock { state in
            guard state.latest?.phase.isTerminal != true else { return false }
            // Terminal evidence always latches; only progress samples are ordered by time.
            if !incoming.phase.isTerminal, let latest = state.latest, latest.updatedAt > incoming.updatedAt { return false }
            state.latest = incoming
            guard !state.deliveryPending else { return false }
            state.deliveryPending = true
            return true
        }
    }

    func deliveryHandled() { sample.withLock { $0.deliveryPending = false } }
}

extension TransferSnapshot {
    /// Browsers publish progress for an in-progress file ("X.dmg.download"); the finished
    /// file drops that suffix.
    public var finishedFileURL: URL? { fileURL.map(Self.finishedFileURL) }

    static func finishedFileURL(_ url: URL) -> URL {
        ["download", "crdownload", "part"].contains(url.pathExtension.lowercased())
            ? url.deletingPathExtension() : url
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
