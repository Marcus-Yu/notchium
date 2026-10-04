import AppKit
import NotchiumCore
import NotchiumDesignSystem
import NotchiumDynamicIsland
import NotchiumServices
import SwiftUI

/// A lightweight temporary workspace, not a Finder: one toolbar row, the held items, then
/// Transfers and Screenshots strips that exist only while relevant.
struct ShelfPageView: View {
    @Bindable var model: FilesFeatureModel
    @State private var selection: Set<ShelfModel.Item.ID> = []
    /// Present when Clipboard shares this page; the title becomes the section switch.
    @Environment(\.notchShelfSection) private var section

    var body: some View {
        VStack(alignment: .leading, spacing: ShelfStyle.sectionGap) {
            toolbar
            ScrollView(.vertical) {
                // Held items lead; timely strips follow; the empty state never pushes them down.
                VStack(alignment: .leading, spacing: ShelfStyle.sectionGap) {
                    if !model.shelf.items.isEmpty { shelf }
                    if model.downloadsAccess == .unavailable(.permissionDenied) {
                        AccessRow(text: "Allow Downloads access to act on finished downloads",
                                  action: model.actions.openPrivacySettings)
                    }
                    if !model.transfers.active.isEmpty || !model.transfers.recent.isEmpty { transfers }
                    if model.screenshotAccess == .unavailable(.permissionDenied) {
                        AccessRow(text: "Allow access to your screenshot folder to show new screenshots",
                                  action: model.actions.openPrivacySettings)
                    }
                    if !model.screenshots.recent.isEmpty { screenshots }
                    if model.shelf.items.isEmpty { emptyShelf }
                }
            }
            .scrollIndicators(.never)
            // Content scrolls under a short fade instead of ending in a hard cut at the shell edge.
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 14)
                }
            }
        }
        .padding(.horizontal, ExpandedPageStyle.outerInset)
        .padding(.top, ExpandedPageStyle.topInset)
        .padding(.bottom, ExpandedPageStyle.bottomInset)
        .foregroundStyle(.white)
        .onDeleteCommand { selection.forEach(model.shelf.remove); selection.removeAll() }
        .onChange(of: model.shelf.items.map(\.id)) { _, ids in selection.formIntersection(ids) }
    }

    // MARK: Toolbar

    /// Share and AirDrop act on the selection, or on everything held when nothing is selected.
    private var toolbar: some View {
        let targets = model.shareItems(selection: selection)
        return HStack(spacing: ShelfStyle.controlGap) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let section {
                    NotchShelfSectionSwitch(selection: section)
                } else {
                    Text("Shelf").font(.system(size: 13, weight: .semibold))
                }
                if !model.shelf.items.isEmpty {
                    Text(selection.isEmpty ? "\(model.shelf.items.count)" : "\(selection.count) of \(model.shelf.items.count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                        .contentTransition(.numericText())
                }
            }
            if let notice = model.notice {
                Text(notice).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1).transition(.opacity)
            }
            Spacer(minLength: 4)
            ShelfToolButton(symbol: "plus", label: "Add Files…", action: model.addChosenFiles)
            ShelfToolButton(symbol: "dot.radiowaves.left.and.right", label: "AirDrop",
                            image: NativeFileActions.airDropImage) { model.airDrop(targets) }
                .disabled(targets.isEmpty || model.isSharing)
            ShelfToolButton(symbol: "square.and.arrow.up", label: "Share") { model.share(targets) }
                .disabled(model.isSharing)
                .background { FileSharingAnchor(model: model) }
                .disabled(targets.isEmpty)
                .help("Share")
                .accessibilityLabel("Share")
            ShelfToolButton(symbol: "trash", label: selection.isEmpty ? "Clear Shelf" : "Remove Selected") {
                if selection.isEmpty { model.shelf.clear() } else { selection.forEach(model.shelf.remove) }
                selection.removeAll()
            }
            .disabled(model.shelf.items.isEmpty)
        }
        .frame(height: ShelfStyle.control)
        .animation(.easeOut(duration: 0.15), value: model.notice)
    }

    // MARK: Shelf

    private var shelf: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: ShelfStyle.tileGap) {
                ForEach(model.shelf.items) { item in
                    let dragged = dragItems(for: item)
                    FileTile(url: item.url, name: item.displayName, thumbnail: ShelfStyle.shelfThumbnail,
                             isAvailable: item.isAvailable, isSelected: selection.contains(item.id),
                             select: { toggle(item.id) }, open: { model.actions.open([item.url]) },
                             selectedURLs: dragged.map(\.url),
                             delivered: { urls in
                                 dragged.filter { urls.contains($0.url) }.forEach { model.shelf.remove($0.id) }
                             }) {
                        if item.isAvailable { fileActions([item.url]) }
                        Divider()
                        Button("Remove from Shelf") { model.shelf.remove(item.id) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
    }

    private func dragItems(for item: ShelfModel.Item) -> [ShelfModel.Item] {
        selection.contains(item.id)
            ? model.shelf.items.filter { selection.contains($0.id) && $0.isAvailable } : [item]
    }

    private var emptyShelf: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.45))
            Text("Drop files onto the notch to keep them here")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            Button("Add Files…", action: model.addChosenFiles)
                .buttonStyle(ShelfTextButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExpandedPageStyle.Space.md)
        .accessibilityElement(children: .contain)
    }

    // MARK: Transfers

    private var transfers: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionTitle("Transfers")
            ForEach(model.transfers.active.prefix(2)) { TransferRow(transfer: $0, model: model) }
            if model.transfers.active.count > 2 {
                Text("+\(model.transfers.active.count - 2) more")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(model.transfers.recent.prefix(model.transfers.active.isEmpty ? 2 : 1)) {
                TransferRow(transfer: $0, model: model)
            }
        }
    }

    // MARK: Screenshots

    private var screenshots: some View {
        VStack(alignment: .leading, spacing: ExpandedPageStyle.Space.xs) {
            HStack {
                sectionTitle("Screenshots")
                Spacer()
                Button("Add All to Shelf") { model.addToShelf(model.screenshots.recent.map(\.fileURL)) }
                    .buttonStyle(ShelfTextButtonStyle())
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: ShelfStyle.tileGap) {
                    ForEach(model.screenshots.recent) { capture in
                        FileTile(url: capture.fileURL, name: capture.fileURL.deletingPathExtension().lastPathComponent,
                                 thumbnail: ShelfStyle.screenshotThumbnail, isAvailable: true, isSelected: false,
                                 select: {}, open: { model.actions.open([capture.fileURL]) }) {
                            Button("Add to Shelf") { model.addToShelf([capture.fileURL]) }
                            fileActions([capture.fileURL])
                            Divider()
                            Button("Dismiss") { model.screenshots.dismiss(capture) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        }
    }

    @ViewBuilder private func fileActions(_ urls: [URL]) -> some View {
        Button("Open") { model.actions.open(urls) }
        Button("Show in Finder") { model.actions.reveal(urls) }
        Button("Copy") { model.actions.copyFiles(urls) }
        Button("Copy Path") { model.actions.copyPaths(urls) }
        Button("Share…") { model.share(urls) }.disabled(model.isSharing)
        Button("AirDrop") { model.airDrop(urls) }.disabled(model.isSharing)
    }

    private func toggle(_ id: ShelfModel.Item.ID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(ExpandedPageStyle.sectionTitle).foregroundStyle(ExpandedPageStyle.secondary)
    }
}

/// One set of Shelf metrics so controls, tiles and rows stay proportionate.
enum ShelfStyle {
    /// Comfortable macOS-sized hit target for toolbar actions (shared with Clipboard).
    static let control = NotchToolbarMetrics.control
    static let controlGap = NotchToolbarMetrics.controlGap
    static let sectionGap = NotchToolbarMetrics.sectionGap
    static let tileGap: CGFloat = 10
    static let tileWidth: CGFloat = 82
    static let shelfThumbnail = CGSize(width: 48, height: 48)
    static let screenshotThumbnail = CGSize(width: 68, height: 42)
}

/// Thumbnail + short name. Click selects, double-click opens, dragging out hands the file to
/// the destination (and, for Shelf items, consumes it); every action is also in the menu.
private struct FileTile<Menu: View>: View {
    let url: URL
    let name: String
    let thumbnail: CGSize
    let isAvailable: Bool
    let isSelected: Bool
    let select: () -> Void
    let open: () -> Void
    var selectedURLs: [URL] = []
    /// A successful external drop; nil for tiles that are only dragged, never consumed.
    var delivered: (([URL]) -> Void)?
    @ViewBuilder let menu: () -> Menu
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            VStack(spacing: 5) {
                NotchThumbnailView(url: url, size: thumbnail, cornerRadius: 7)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .opacity(isAvailable ? 1 : 0.35)
                    .overlay(alignment: .bottomTrailing) {
                        if !isAvailable {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                                .offset(x: 3, y: 3)
                        }
                    }
                    .frame(height: max(thumbnail.height, ShelfStyle.shelfThumbnail.height))
                // Two centred lines at a fixed height keep the row aligned; the middle is elided so
                // the extension stays readable.
                Text(name)
                    .font(.system(size: 10.5, weight: isSelected ? .medium : .regular))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(isAvailable ? (isSelected ? 1 : 0.8) : 0.45))
                    .frame(width: max(thumbnail.width, ShelfStyle.tileWidth) - 6, height: 28, alignment: .top)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 5)
            .background(.white.opacity(isSelected ? 0.15 : (isHovered ? 0.07 : 0)),
                        in: .rect(cornerRadius: ExpandedPageStyle.selectionRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ExpandedPageStyle.selectionRadius)
                    .strokeBorder(.white.opacity(isSelected ? 0.22 : 0), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { if isAvailable { open() } })
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .overlay { ShelfDragSource(url: url, isEnabled: isAvailable, selectedURLs: selectedURLs, onDelivered: delivered) }
        .contextMenu { menu() }
        .help(name)
        .accessibilityLabel(isAvailable ? name : "\(name), missing")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Open") { if isAvailable { open() } }
    }
}

private struct TransferRow: View {
    let transfer: TransferSnapshot
    let model: FilesFeatureModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusSymbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(transfer.phase.isTerminal ? 0.6 : 0.9))
                .frame(width: 18)
            Text(transfer.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if !transfer.phase.isTerminal, let fraction = transfer.fraction {
                // The same thin bar language as the compact activity.
                Capsule().fill(.white.opacity(0.18))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(.white).frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)))
                        }
                    }
                    .frame(width: 110, height: 4)
                    .animation(.smooth(duration: 0.25), value: fraction)
            }
            Text(status)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            if let finished = model.transfers.finishedFiles[transfer.id] {
                ShelfToolButton(symbol: "tray.and.arrow.down", label: "Add to Shelf", compact: true) {
                    model.addToShelf([finished])
                }
                ShelfToolButton(symbol: "magnifyingglass", label: "Show in Finder", compact: true) {
                    model.actions.reveal([finished])
                }
            } else if !transfer.phase.isTerminal, let url = transfer.fileURL {
                ShelfToolButton(symbol: "magnifyingglass", label: "Show in Finder", compact: true) {
                    model.actions.reveal([url])
                }
            }
        }
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        switch transfer.phase {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .stopped: "xmark.circle"
        case .active, .paused: transfer.operation.symbol
        }
    }

    /// Percent and remaining time only when the publisher reports them.
    private var status: String {
        switch transfer.phase {
        case .completed: return "Done"
        case let .failed(message): return message ?? "Failed"
        case .stopped: return "Stopped"
        case .paused: return "Paused"
        case .active:
            guard let fraction = transfer.fraction else { return "\(transfer.operation.verb)…" }
            let percent = "\(Int((fraction * 100).rounded(.down)))%"
            guard let remaining = transfer.estimatedTimeRemaining, remaining.isFinite, remaining > 0 else { return percent }
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = remaining >= 3600 ? [.hour, .minute] : (remaining >= 60 ? [.minute] : [.second])
            formatter.unitsStyle = .abbreviated
            return "\(percent) · \(formatter.string(from: remaining) ?? "")"
        }
    }
}

/// A denied folder: say what is missing and offer the one place to fix it.
private struct AccessRow: View {
    let text: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            Spacer(minLength: 6)
            Button("Open Settings", action: action).buttonStyle(ShelfTextButtonStyle())
        }
        .frame(height: 26)
        .accessibilityElement(children: .combine)
    }
}

/// Toolbar controls are shared with Clipboard so both top rows keep one rhythm.
private struct ShelfToolButton: View {
    let symbol: String
    let label: String
    var image: NSImage?
    var compact = false
    let action: () -> Void

    var body: some View {
        NotchToolbarButton(symbol: symbol, label: label, image: image, compact: compact, action: action)
    }
}

/// Quiet capsule text action for secondary commands ("Add All to Shelf", "Open Settings").
private struct ShelfTextButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(isHovered ? 1 : 0.8))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.white.opacity(configuration.isPressed ? 0.2 : (isHovered ? 0.14 : 0.08)), in: .capsule)
            .contentShape(.capsule)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
