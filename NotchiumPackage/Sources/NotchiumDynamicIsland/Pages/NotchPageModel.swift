import Combine
import Foundation

/// Opening-page eligibility is independent of the timer's collapsed activity lifetime.
public enum NotchPomodoroPageState: Equatable, Sendable {
    case inactive
    case running
    case paused(at: ContinuousClock.Instant)
}

@MainActor
public final class NotchPageModel: ObservableObject {
    public static let pomodoroPausedPageGrace: Duration = .seconds(30)

    /// Evaluate only when opening a fresh expansion. Media's existing local/remote resolver
    /// remains authoritative; no scheduled work changes a page when this grace expires.
    public static func automaticOpenPage(existingDefault: NotchPage,
                                         pomodoro: NotchPomodoroPageState,
                                         now: ContinuousClock.Instant) -> NotchPage {
        if existingDefault == .music { return .music }
        switch pomodoro {
        case .running: return .pomodoro
        case let .paused(at) where now < at.advanced(by: pomodoroPausedPageGrace): return .pomodoro
        default: return existingDefault
        }
    }

    public private(set) var manualSelectionDuringExpansion = false
    private var expansionIsActive = false
    private var selectingAutomatically = false

    @Published public var selectedPage: NotchPage {
        didSet {
            if expansionIsActive && !selectingAutomatically { manualSelectionDuringExpansion = true }
            if !enabledPages.contains(selectedPage) { selectedPage = fallbackPage }
        }
    }
    @Published public var enabledPages: [NotchPage] {
        didSet {
            let normalized = Self.normalize(enabledPages)
            if enabledPages != normalized { enabledPages = normalized }
            if !enabledPages.contains(selectedPage) { selectedPage = fallbackPage }
        }
    }
    @Published public var defaultPage: NotchPage
    /// Files or Clipboard inside the Shelf page; kept across collapse like the page itself.
    @Published public var shelfSection: NotchShelfSection = .files

    public init(selectedPage: NotchPage = .home,
                enabledPages: [NotchPage] = NotchPage.allCases,
                defaultPage: NotchPage = .home) {
        let pages = Self.normalize(enabledPages)
        self.enabledPages = pages
        self.defaultPage = defaultPage
        self.selectedPage = pages.contains(selectedPage) ? selectedPage
            : (pages.contains(defaultPage) ? defaultPage : pages[0])
    }

    public func beginExpansion(default page: NotchPage) {
        guard !expansionIsActive else { return }
        expansionIsActive = true
        manualSelectionDuringExpansion = false
        selectingAutomatically = true
        if selectedPage != page { selectedPage = page }
        selectingAutomatically = false
    }

    public func endExpansion() {
        expansionIsActive = false
        manualSelectionDuringExpansion = false
    }

    public func selectDefaultPage() {
        guard !expansionIsActive else { return }
        selectedPage = fallbackPage
    }

    public func moveSelection(forward: Bool) {
        guard let index = enabledPages.firstIndex(of: selectedPage) else { return }
        let next = index + (forward ? 1 : -1)
        guard enabledPages.indices.contains(next) else { return }
        selectedPage = enabledPages[next]
    }

    private var fallbackPage: NotchPage {
        enabledPages.contains(defaultPage) ? defaultPage : enabledPages[0]
    }

    private static func normalize(_ pages: [NotchPage]) -> [NotchPage] {
        var unique: [NotchPage] = []
        for page in pages where !unique.contains(page) { unique.append(page) }
        // Keep a valid selection even if a future settings client disables everything.
        return unique.isEmpty ? [.home] : unique
    }
}
