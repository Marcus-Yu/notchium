import Foundation
import NotchiumDynamicIsland
import NotchiumServices
import Observation

/// Owns this session's captures and projects them as one transient activity. Rapid
/// captures update that activity (latest thumbnail + count) instead of replaying entry.
@MainActor
@Observable
public final class ScreenshotActivityModel {
    public private(set) var recent: [ScreenshotCapture] = []

    static let key = "screenshot"
    static let recentLimit = 12

    @ObservationIgnored private let activities: ActivityCoordinator
    @ObservationIgnored private var batch: [ScreenshotCapture] = []
    @ObservationIgnored private var activityID: UUID?

    public init(activities: ActivityCoordinator) {
        self.activities = activities
    }

    public func receive(_ event: ScreenshotEvent) {
        switch event {
        case let .captured(capture):
            guard !recent.contains(where: { $0.id == capture.id }) else { return }
            recent.insert(capture, at: 0)
            if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
            batch = isActivityLive ? [capture] + batch : [capture]
            present()
        case let .removed(url):
            recent.removeAll { $0.fileURL == url }
            NotchThumbnailCache.shared.invalidate(url)
            guard isActivityLive, batch.contains(where: { $0.fileURL == url }) else { return }
            batch.removeAll { $0.fileURL == url }
            if batch.isEmpty, let activityID { activities.dismiss(id: activityID) } else { present() }
        }
    }

    public func dismiss(_ capture: ScreenshotCapture) {
        recent.removeAll { $0.id == capture.id }
    }

    public func clearRecent() { recent.removeAll() }

    func reset() {
        if let activityID { activities.dismiss(id: activityID) }
        batch.removeAll()
        activityID = nil
    }

    private var isActivityLive: Bool { activityID.map(activities.contains(id:)) ?? false }

    private func present() {
        guard let latest = batch.first else { return }
        let label = batch.count == 1 ? "Screenshot" : "\(batch.count) Screenshots"
        let notification = NotchNotification(
            kind: .screenshot, coalescingKey: Self.key, action: .shelf, presentationStyle: .compact,
            content: .compact(.init(glyph: .thumbnail(latest.fileURL), title: label,
                                    showsTitle: false, trailing: .text(label))))
        activities.notifications.present(notification)
        // Coalesced updates keep the identity, so later captures extend this same activity.
        activityID = activities.liveActivities.first { $0.key == NotchActivityKey(Self.key) }?.id
    }
}
