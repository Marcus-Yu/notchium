import Combine

@MainActor
public final class NotchPageModel: ObservableObject {
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
