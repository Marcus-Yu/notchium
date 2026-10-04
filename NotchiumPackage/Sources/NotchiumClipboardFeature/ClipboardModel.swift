import Foundation
import NotchiumDynamicIsland
import NotchiumServices
import Observation
import SwiftUI

/// How long unpinned history is kept.
public enum ClipboardRetention: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, unlimited
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .day: "1 Day"
        case .week: "7 Days"
        case .month: "30 Days"
        case .unlimited: "Until Removed"
        }
    }
    var maximumAge: TimeInterval? {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .unlimited: nil
        }
    }
}

/// Owns clipboard history: bounded, deduplicated, local. The service owns the pasteboard.
@MainActor
@Observable
public final class ClipboardModel {
    /// Newest first. Pinned items are listed first by the view, not reordered here.
    public private(set) var items: [ClipboardItem] = []
    public var query = ""
    /// The row that just copied, for inline confirmation only (no notch activity).
    public private(set) var lastCopiedID: UUID?
    public var historyLimit: Int {
        didSet {
            guard historyLimit != oldValue else { return }
            preferences.set(historyLimit, forKey: Keys.limit)
            enforceBounds(at: currentDate())
        }
    }
    public var retention: ClipboardRetention {
        didSet {
            guard retention != oldValue else { return }
            preferences.set(retention.rawValue, forKey: Keys.retention)
            enforceBounds(at: currentDate())
        }
    }
    public private(set) var isVisible = false

    public static let limitOptions = [25, 50, 100]
    /// Pins are for a few reusable snippets, never silently evicted.
    public static let maximumPinned = 10

    @ObservationIgnored private let service: any ClipboardService
    @ObservationIgnored private let store: any ClipboardStoring
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let currentDate: () -> Date
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var copiedTask: Task<Void, Never>?
    @ObservationIgnored private var persistedItems: [ClipboardItem] = []
    @ObservationIgnored private var persistedImageIDs: Set<UUID>?

    private enum Keys {
        static let limit = "notchium.clipboard.limit.v1"
        static let retention = "notchium.clipboard.retention.v1"
    }

    public init(service: any ClipboardService, store: any ClipboardStoring, preferences: UserDefaults = .standard,
                now: @escaping () -> Date = Date.init) {
        self.service = service
        self.store = store
        self.preferences = preferences
        currentDate = now
        let limit = preferences.integer(forKey: Keys.limit)
        historyLimit = Self.limitOptions.contains(limit) ? limit : 50
        retention = preferences.string(forKey: Keys.retention).flatMap(ClipboardRetention.init) ?? .month
        items = store.loadItems()
        persistedItems = items
        enforceBounds(at: now())
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self, service] in
            for await capture in await service.captures() {
                guard !Task.isCancelled, let self else { return }
                self.receive(capture)
            }
        }
    }

    public func stop() {
        task?.cancel(); task = nil
        copiedTask?.cancel(); copiedTask = nil
        lastCopiedID = nil
        store.flush()
    }

    isolated deinit { stop() }

    // MARK: History

    func receive(_ capture: ClipboardCapture) {
        let fingerprint = capture.content.fingerprint
        if let index = items.firstIndex(where: { $0.fingerprint == fingerprint }) {
            // Copying the same thing again moves it forward instead of duplicating it.
            var item = items.remove(at: index)
            item.capturedAt = capture.capturedAt
            items.insert(item, at: 0)
        } else {
            let item = ClipboardItem(content: capture.content, capturedAt: capture.capturedAt)
            if case let .image(png, _, _) = capture.content { store.saveImage(png, id: item.id) }
            items.insert(item, at: 0)
        }
        enforceBounds(at: capture.capturedAt)
    }

    /// Unpinned items beyond the limit or older than the retention period are removed.
    private func enforceBounds(at now: Date) {
        var unpinned = 0
        let cutoff = retention.maximumAge.map { now.addingTimeInterval(-$0) }
        let bounded = items.filter { item in
            guard !item.isPinned else { return true }
            if let cutoff, item.capturedAt < cutoff { return false }
            unpinned += 1
            return unpinned <= historyLimit
        }
        if items != bounded { items = bounded }
        persist()
    }

    private func persist() {
        if persistedItems != items {
            store.saveItems(items)
            persistedItems = items
        }
        let images = Set(items.filter { $0.kind == .image }.map(\.id))
        if persistedImageIDs != images {
            store.removeImages(except: images)
            persistedImageIDs = images
        }
    }

    // MARK: Actions

    /// Puts the item back on the clipboard and moves it to the front.
    public func copy(_ item: ClipboardItem) {
        guard let content = content(of: item) else { return }
        Task { [service] in await service.write(content) }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var moved = items.remove(at: index)
            moved.capturedAt = currentDate()
            items.insert(moved, at: 0)
            persist()
        }
        lastCopiedID = item.id
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.lastCopiedID = nil
        }
    }

    public var canPin: Bool { items.count { $0.isPinned } < Self.maximumPinned }

    public func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[index].isPinned || canPin else { return }
        items[index].isPinned.toggle()
        enforceBounds(at: currentDate())
    }

    public func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    /// Clears history; pinned items stay unless `includingPinned`.
    public func clear(includingPinned: Bool = false) {
        items.removeAll { includingPinned || !$0.isPinned }
        persist()
    }

    // MARK: Presentation

    /// Pinned first, then recent; filtered by the search text.
    public var visibleItems: [ClipboardItem] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let matches = needle.isEmpty ? items : items.filter { $0.searchText.localizedCaseInsensitiveContains(needle) }
        return matches.filter(\.isPinned) + matches.filter { !$0.isPinned }
    }

    public func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible { enforceBounds(at: currentDate()) }
    }

    func content(of item: ClipboardItem) -> ClipboardContent? {
        switch item.kind {
        case .text: item.text.map(ClipboardContent.text)
        case .url: item.url.map(ClipboardContent.url)
        case .file: item.fileURLs.map(ClipboardContent.files)
        case .image:
            store.loadImage(id: item.id).map {
                .image(png: $0, thumbnail: item.thumbnail ?? Data(), pixelSize: item.pixelSize ?? .zero)
            }
        }
    }
}

extension ClipboardModel: NotchClipboardRendering {
    public func expandedClipboard() -> AnyView { AnyView(ClipboardPageView(model: self)) }
}
