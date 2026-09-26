import Combine

@MainActor
public final class NotchPageModel: ObservableObject {
    @Published public var selectedPage: NotchPage {
        didSet {
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

    public func selectDefaultPage() { selectedPage = fallbackPage }

    public func moveSelection(forward: Bool) {
        guard let index = enabledPages.firstIndex(of: selectedPage) else { return }
        let offset = forward ? 1 : enabledPages.count - 1
        selectedPage = enabledPages[(index + offset) % enabledPages.count]
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
