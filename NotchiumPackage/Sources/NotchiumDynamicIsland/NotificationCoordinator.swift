import Foundation
import Observation

/// The notification slot: the content of the primary activity when it is a notification.
/// ActivityCoordinator owns arbitration and every lifetime; this type keeps the notification
/// API for producers and the interaction state (hover, drag) for the shell.
@MainActor
@Observable
public final class NotificationCoordinator {
    public private(set) var active: NotchNotification?
    public private(set) var isHovered = false
    public private(set) var interactingID: UUID?
    public private(set) var createdAt: Date?
    public private(set) var expiresAt: Date?
    @ObservationIgnored weak var activities: ActivityCoordinator?

    init() {}

    /// Returns whether the notification is now presented. One that cannot present yet
    /// (a higher priority activity holds the notch) stays live until its own deadline.
    /// Explicit input events may refresh an unchanged payload; duplicate state reports do not.
    @discardableResult
    public func present(_ notification: NotchNotification, refreshingLifetime: Bool = false) -> Bool {
        activities?.presentNotification(notification, refreshingLifetime: refreshingLifetime) ?? false
    }

    /// Removes the active notification, or the live notification with `id` even if it is
    /// waiting underneath. Identity-checked so a retiring gesture never dismisses a replacement.
    public func dismiss(id: UUID? = nil) {
        guard let target = id ?? active?.id else { return }
        activities?.dismiss(id: target)
    }

    /// Removes a notification by its source identity, e.g. a persistent transfer when its feature stops.
    public func dismiss(coalescingKey: String) {
        activities?.dismiss(key: NotchActivityKey(coalescingKey))
    }

    public func dismissByUser(id: UUID? = nil) {
        guard let active, active.dismissible, id == nil || id == active.id else { return }
        dismiss(id: active.id)
    }

    public func setInteracting(_ interacting: Bool, id: UUID) {
        guard active?.id == id else { return }
        interactingID = interacting ? id : nil
    }

    public func setHovered(_ hovered: Bool) {
        guard active != nil, isHovered != hovered else { return }
        isHovered = hovered
    }

    /// Called synchronously by ActivityCoordinator whenever the primary activity changes.
    func show(_ notification: NotchNotification?, createdAt: Date?, expiresAt: Date?) {
        if notification?.id != active?.id { interactingID = nil }
        if notification == nil { isHovered = false }
        if active != notification { active = notification }
        if self.createdAt != createdAt { self.createdAt = createdAt }
        if self.expiresAt != expiresAt { self.expiresAt = expiresAt }
    }
}
