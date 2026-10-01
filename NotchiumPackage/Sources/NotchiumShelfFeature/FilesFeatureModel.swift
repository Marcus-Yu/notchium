import AppKit
import NotchiumCore
import NotchiumDynamicIsland
import NotchiumServices
import Observation
import SwiftUI

/// Composes the Shelf, transfer activities and screenshot activities, and renders the Shelf
/// page. Each part owns its own truth; the ActivityCoordinator only arbitrates presentation.
@MainActor
@Observable
public final class FilesFeatureModel: NotchShelfRendering {
    public let shelf: ShelfModel
    public let transfers: TransferActivityModel
    public let screenshots: ScreenshotActivityModel
    /// A short inline message for an action that could not run (e.g. AirDrop unavailable).
    public private(set) var notice: String?
    /// Folder access for screenshot detection and for acting on finished downloads.
    public private(set) var screenshotAccess: FeatureAvailability = .available
    public private(set) var downloadsAccess: FeatureAvailability = .available

    @ObservationIgnored let actions: any FileActionPerforming
    @ObservationIgnored weak var sharingAnchor: NSView?
    @ObservationIgnored var sharingInteraction = NotchAuxiliaryInteractionHandler()
    @ObservationIgnored private let transferService: any FileTransferService
    @ObservationIgnored private let screenshotService: any ScreenshotService
    @ObservationIgnored private let notifications: NotificationCoordinator
    @ObservationIgnored private var transferTask: Task<Void, Never>?
    @ObservationIgnored private var screenshotTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    public init(transfers: any FileTransferService, screenshots: any ScreenshotService,
                shelf: any ShelfService, actions: any FileActionPerforming,
                activities: ActivityCoordinator, now: @escaping () -> Date = Date.init) {
        transferService = transfers
        screenshotService = screenshots
        self.actions = actions
        notifications = activities.notifications
        self.shelf = ShelfModel(service: shelf, now: now)
        self.transfers = TransferActivityModel(notifications: activities.notifications)
        self.screenshots = ScreenshotActivityModel(activities: activities)
    }

    public func start() {
        guard transferTask == nil else { return }
        shelf.restore()
        transferTask = Task { [weak self, transferService] in
            let updates = await transferService.updates()
            // Monitoring (and its read-only folder access) is established before anything else.
            let access = await transferService.availability()
            self?.downloadsAccess = access
            for await snapshot in updates {
                guard !Task.isCancelled, let self else { return }
                self.transfers.receive(snapshot)
            }
        }
        screenshotTask = Task { [weak self, screenshotService] in
            let events = await screenshotService.events()
            let access = await screenshotService.availability()
            self?.screenshotAccess = access
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                self.screenshots.receive(event)
            }
        }
    }

    public func stop() {
        transferTask?.cancel(); transferTask = nil
        screenshotTask?.cancel(); screenshotTask = nil
        noticeTask?.cancel(); noticeTask = nil
        transfers.reset()
        screenshots.reset()
    }

    // MARK: NotchShelfRendering

    public func expandedShelf() -> AnyView { AnyView(ShelfPageView(model: self)) }

    public func setPageVisible(_ visible: Bool) {
        guard visible else { return }
        shelf.refreshAvailability()
        guard screenshotAccess != .available || downloadsAccess != .available, transferTask != nil else { return }
        Task { [weak self, screenshotService, transferService] in
            let screenshots = await screenshotService.availability()
            let downloads = await transferService.availability()
            self?.screenshotAccess = screenshots
            self?.downloadsAccess = downloads
        }
    }

    @discardableResult
    public func acceptDroppedFiles(_ urls: [URL]) -> Int {
        let accepted = insertIntoShelf(urls)
        guard !urls.isEmpty else { return 0 }
        // One concise result either way; a failed drop never pretends to have added anything.
        let (symbol, text, tint): (String, String, NotchCompactActivity.Tint) = accepted > 0
            ? ("tray.and.arrow.down.fill", accepted == 1 ? "Added" : "\(accepted) Added", .primary)
            : ("exclamationmark.circle.fill", "Couldn’t Add", .warning)
        notifications.present(NotchNotification(
            kind: .shelfAdded, coalescingKey: "shelf.added", action: .shelf, presentationStyle: .compact,
            content: .compact(.init(glyph: .symbol(symbol), title: accepted > 0 ? "Added to Shelf" : "Couldn’t add to Shelf",
                                    showsTitle: false, trailing: .text(text), tint: tint))))
        return accepted
    }

    // MARK: Actions

    public func addToShelf(_ urls: [URL]) {
        if insertIntoShelf(urls) == 0 { show("File is no longer available") }
    }

    private func insertIntoShelf(_ urls: [URL]) -> Int {
        let inserted = shelf.insert(urls)
        for url in inserted {
            screenshots.consumeReference(to: url)
            transfers.consumeReference(to: url)
        }
        return inserted.count
    }

    public func addChosenFiles() {
        Task { [weak self] in
            guard let self else { return }
            self.addToShelf(await self.actions.chooseFiles())
        }
    }

    /// What Share/AirDrop act on: the selection, else every available Shelf item. Missing
    /// files are never offered to a sharing service.
    public func shareItems(selection: Set<ShelfModel.Item.ID>) -> [URL] {
        let chosen = selection.isEmpty ? shelf.items : shelf.items.filter { selection.contains($0.id) }
        return chosen.filter(\.isAvailable).map(\.url)
    }

    public func airDrop(_ urls: [URL]) {
        if actions.airDrop(urls, from: sharingAnchor, interaction: sharingInteraction) == .unavailable {
            show("AirDrop is unavailable")
        }
    }

    public func share(_ urls: [URL]) {
        guard let sharingAnchor else { return }
        if actions.share(urls, from: sharingAnchor, interaction: sharingInteraction) == .unavailable {
            show("Sharing is unavailable")
        }
    }

    private func show(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
