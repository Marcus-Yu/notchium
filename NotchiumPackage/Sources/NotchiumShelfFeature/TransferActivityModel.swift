import Foundation
import NotchiumDynamicIsland
import NotchiumServices
import Observation

/// Owns transfer truth from the transfer service and projects it as ONE activity identity:
/// persistent while anything runs (primary transfer + "+N"), then one brief result that
/// morphs in place. Results of individual transfers while others still run appear only in
/// the expanded list, so they never interrupt.
@MainActor
@Observable
public final class TransferActivityModel {
    public private(set) var active: [TransferSnapshot] = []
    /// Finished this session, newest first (bounded), for Reveal / Add to Shelf.
    public private(set) var recent: [TransferSnapshot] = []
    /// The finished file of each completed transfer, resolved once at completion (never in a
    /// view body), and absent when the file is gone.
    public private(set) var finishedFiles: [String: URL] = [:]

    static let key = "transfer"
    static let recentLimit = 5

    @ObservationIgnored private let notifications: NotificationCoordinator
    @ObservationIgnored private var finishedIDs: Set<String> = []
    @ObservationIgnored private var latestUpdates: [String: Date] = [:]
    @ObservationIgnored private var batchResults: [TransferPhase] = []

    public init(notifications: NotificationCoordinator) {
        self.notifications = notifications
    }

    public func receive(_ snapshot: TransferSnapshot) {
        // A late progress sample after completion must not resurrect the transfer.
        guard !finishedIDs.contains(snapshot.id) else { return }
        guard latestUpdates[snapshot.id].map({ $0 <= snapshot.updatedAt }) ?? true else { return }
        latestUpdates[snapshot.id] = snapshot.updatedAt
        if snapshot.phase.isTerminal {
            finishedIDs.insert(snapshot.id)
            latestUpdates[snapshot.id] = nil
            active.removeAll { $0.id == snapshot.id }
            recent.insert(snapshot, at: 0)
            if recent.count > Self.recentLimit {
                recent.removeLast(recent.count - Self.recentLimit)
                finishedFiles = finishedFiles.filter { id, _ in recent.contains { $0.id == id } }
            }
            if snapshot.phase == .completed, let url = snapshot.finishedFileURL,
               FileManager.default.fileExists(atPath: url.path) {
                finishedFiles[snapshot.id] = url
            }
            batchResults.append(snapshot.phase)
        } else if let index = active.firstIndex(where: { $0.id == snapshot.id }) {
            active[index] = snapshot
        } else {
            active.append(snapshot)
            active.sort { $0.startedAt < $1.startedAt }
        }
        publish()
    }

    public func clearRecent() {
        recent.removeAll()
        finishedFiles.removeAll()
    }

    /// Completed transfers can hand off their UI representation without touching the file
    /// or interrupting another running transfer's stable activity identity.
    func consumeReference(to url: URL) {
        let ids = Set(finishedFiles.compactMap { id, file in
            file.standardizedFileURL == url.standardizedFileURL ? id : nil
        })
        let consumesLatestResult = recent.first.map { ids.contains($0.id) } ?? false
        recent.removeAll { ids.contains($0.id) }
        finishedFiles = finishedFiles.filter { !ids.contains($0.key) }
        if active.isEmpty, consumesLatestResult {
            notifications.dismiss(coalescingKey: Self.key)
        }
    }

    /// Stopping the feature removes its activity; nothing about transfers is persisted.
    func reset() {
        active.removeAll()
        batchResults.removeAll()
        finishedIDs.removeAll()
        latestUpdates.removeAll()
        notifications.dismiss(coalescingKey: Self.key)
    }

    private func publish() {
        if let primary = active.first {
            notifications.present(Self.activeNotification(primary: primary, others: active.count - 1))
        } else if !batchResults.isEmpty {
            notifications.present(Self.resultNotification(batchResults))
            batchResults.removeAll()
        }
    }

    static func activeNotification(primary: TransferSnapshot, others: Int) -> NotchNotification {
        let percent = primary.fraction.map { "\(Int(($0 * 100).rounded(.down)))%" }
        let label = (percent ?? "\(primary.operation.verb)…") + (others > 0 ? " +\(others)" : "")
        return NotchNotification(
            kind: .transferActive, dismissible: false, coalescingKey: key, action: .shelf,
            presentationStyle: .compact,
            content: .compact(.init(glyph: .symbol(primary.operation.symbol),
                                    title: "\(primary.operation.verb) \(primary.displayName)",
                                    showsTitle: false, trailing: .progress(primary.fraction, label: label))),
            lifetime: .persistent, minimal: .progress(primary.fraction))
    }

    /// Honest outcome for the batch: any failure is a failure, unfinished is "Stopped".
    static func resultNotification(_ results: [TransferPhase]) -> NotchNotification {
        let failed = results.contains { if case .failed = $0 { true } else { false } }
        let completed = results.allSatisfy { $0 == .completed }
        let (symbol, text, tint, title): (String, String, NotchCompactActivity.Tint, String) =
            failed ? ("exclamationmark.circle.fill", "Failed", .warning, "Transfer failed")
            : completed ? ("checkmark.circle.fill", "Done", .primary, "Transfer complete")
            : ("xmark.circle.fill", "Stopped", .muted, "Transfer stopped")
        return NotchNotification(
            kind: failed ? .transferFailed : .transferFinished, coalescingKey: key, action: .shelf,
            presentationStyle: .compact,
            content: .compact(.init(glyph: .symbol(symbol), title: title, showsTitle: false,
                                    trailing: .text(text), tint: tint)))
    }
}

extension TransferOperation {
    var symbol: String {
        switch self {
        case .downloading, .receiving: "arrow.down.circle.fill"
        case .copying: "doc.on.doc.fill"
        case .decompressing: "archivebox.fill"
        case .other: "doc.fill"
        }
    }

    var verb: String {
        switch self {
        case .downloading: "Downloading"
        case .copying: "Copying"
        case .receiving: "Receiving"
        case .decompressing: "Expanding"
        case .other: "Transferring"
        }
    }
}
