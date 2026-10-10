import AppKit
import NotchiumDesignSystem
import NotchiumDynamicIsland
import NotchiumServices
import SwiftUI

/// Recent clipboard items as compact one-line rows: click to copy back, search, pin, delete.
struct ClipboardPageView: View {
    @Bindable var model: ClipboardModel
    @State private var selection: UUID?
    @FocusState private var listFocused: Bool
    @Environment(\.notchShelfSection) private var section

    var body: some View {
        let items = model.visibleItems
        VStack(alignment: .leading, spacing: NotchToolbarMetrics.sectionGap) {
            toolbar
            if model.isLoadingStorage {
                Group {
                    if model.storageNeedsAttention {
                        Text("Keychain hasn’t responded. Complete or cancel any Keychain authorization dialog. Existing history has been preserved.")
                            .multilineTextAlignment(.center)
                    } else {
                        ProgressView("Opening Clipboard history…")
                    }
                }
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.storageState.message {
                VStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 16, weight: .light)).foregroundStyle(.white.opacity(0.45))
                    Text(message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                    Button("Try Again", action: model.retryStorage)
                        .accessibilityIdentifier("notchium.clipboard.retryStorage")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            } else if items.isEmpty {
                empty
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 2) {
                            ForEach(items) { item in
                                ClipboardRow(item: item, isSelected: selection == item.id,
                                             copied: model.lastCopiedID == item.id, canPin: model.canPin,
                                             copy: { selection = item.id; model.copy(item) }, pin: { model.togglePin(item) },
                                             delete: { model.delete(item) })
                                    .id(item.id)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 12)
                        }
                    }
                    .focusable()
                    .focused($listFocused)
                    .focusEffectDisabled()
                    .onKeyPress(.downArrow) { move(1, in: items, proxy: proxy) }
                    .onKeyPress(.upArrow) { move(-1, in: items, proxy: proxy) }
                    .onKeyPress(.return) { act(on: items) { model.copy($0) } }
                    .onKeyPress(.space) { act(on: items) { model.copy($0) } }
                    .onKeyPress(.delete) { act(on: items) { model.delete($0) } }
                }
            }
        }
        .padding(.horizontal, ExpandedPageStyle.outerInset)
        .padding(.top, ExpandedPageStyle.topInset)
        .padding(.bottom, ExpandedPageStyle.bottomInset)
        .foregroundStyle(.white)
        .onChange(of: items.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }

    /// The Shelf page's row: same height, controls, gaps and fills (`NotchToolbarMetrics`).
    private var toolbar: some View {
        HStack(spacing: NotchToolbarMetrics.controlGap) {
            if let section {
                NotchShelfSectionSwitch(selection: section)
            } else {
                Text("Clipboard").font(.system(size: 13, weight: .semibold))
            }
            Spacer(minLength: NotchToolbarMetrics.controlGap)
            NotchToolbarSearchField(text: $model.query, prompt: "Search") { listFocused = true }
                .frame(maxWidth: 190)
                .accessibilityLabel("Search clipboard history")
            NotchToolbarButton(symbol: "trash", label: "Clear History") { model.clear() }
                .disabled(model.storageState != .available || !model.items.contains { !$0.isPinned })
        }
        .frame(height: NotchToolbarMetrics.control)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text(model.query.isEmpty ? "Copied text, links, images and files appear here." : "No matches")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func move(_ step: Int, in items: [ClipboardItem], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !items.isEmpty else { return .ignored }
        let index = selection.flatMap { id in items.firstIndex { $0.id == id } }
        let next = index.map { min(max($0 + step, 0), items.count - 1) } ?? (step > 0 ? 0 : items.count - 1)
        selection = items[next].id
        proxy.scrollTo(items[next].id)
        return .handled
    }

    private func act(on items: [ClipboardItem], _ action: (ClipboardItem) -> Void) -> KeyPress.Result {
        guard let item = items.first(where: { $0.id == selection }) else { return .ignored }
        action(item)
        return .handled
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let copied: Bool
    let canPin: Bool
    let copy: () -> Void
    let pin: () -> Void
    let delete: () -> Void
    @State private var isHovered = false
    @NotchReducedMotion private var reduceMotion

    var body: some View {
        HStack(spacing: 9) {
            Button(action: copy) {
                HStack(spacing: 9) {
                    ClipboardItemIcon(item: item, copied: copied, reduceMotion: reduceMotion)
                        .frame(width: 20, height: 20)
                    Text(item.preview)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.white.opacity(0.92))
                    Spacer(minLength: 6)
                    if !isHovered && !isSelected {
                        Text(copied ? "Copied" : item.capturedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.white.opacity(copied ? 0.85 : 0.4))
                            .lineLimit(1)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.kind.spokenName): \(item.preview)")
            .accessibilityValue(item.isPinned ? "Pinned" : (copied ? "Copied" : ""))
            .accessibilityHint("Copies it to the clipboard")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityActions {
                if item.isPinned || canPin {
                    Button(item.isPinned ? "Unpin" : "Pin", action: pin)
                }
                Button("Delete", action: delete)
            }
            if isHovered || isSelected {
                ClipboardIconButton(symbol: item.isPinned ? "pin.slash" : "pin", compact: true,
                                    label: item.isPinned ? "Unpin" : "Pin", action: pin)
                    .disabled(!item.isPinned && !canPin)
                ClipboardIconButton(symbol: "xmark", compact: true, label: "Delete", action: delete)
            } else {
                if item.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(.white.opacity(isSelected ? 0.12 : (isHovered ? 0.07 : 0)),
                    in: .rect(cornerRadius: ExpandedPageStyle.selectionRadius, style: .continuous))
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: copied)
    }
}

private struct ClipboardItemIcon: View {
    let item: ClipboardItem
    let copied: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if copied {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            } else {
                content
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            if let data = item.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .clipShape(.rect(cornerRadius: 4, style: .continuous))
            } else {
                symbol("photo")
            }
        case .file:
            if let path = item.fileURLs?.first?.path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                symbol("doc")
            }
        case .url: symbol("link")
        case .text: symbol("text.alignleft")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
    }
}

private struct ClipboardIconButton: View {
    let symbol: String
    var compact = false
    let label: String
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? (isHovered ? 1 : 0.7) : 0.3))
                .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                .background(.white.opacity(isHovered && isEnabled ? 0.16 : (compact ? 0 : 0.08)), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

private extension ClipboardItemKind {
    var spokenName: String {
        switch self {
        case .text: "Text"
        case .url: "Link"
        case .image: "Image"
        case .file: "File"
        }
    }
}
