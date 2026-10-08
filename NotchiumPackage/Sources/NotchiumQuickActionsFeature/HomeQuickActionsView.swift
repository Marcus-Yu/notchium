import SwiftUI
import AppKit
import NotchiumCore
import NotchiumDesignSystem
import NotchiumDynamicIsland

struct HomeQuickActionsView: View {
    let model: QuickActionsModel

    var body: some View {
        let actions = model.store.pinned
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - HomeDashboardStyle.focusInset * 2)
            let gaps = HomeDashboardStyle.shortcutGap * CGFloat(max(0, actions.count - 1))
            let tileWidth = max(HomeDashboardStyle.minimumShortcutWidth,
                                (contentWidth - gaps) / CGFloat(max(1, actions.count)))
            ScrollView(.horizontal) {
                LazyHStack(spacing: HomeDashboardStyle.shortcutGap) {
                    ForEach(actions) { action in
                        ShortcutTile(action: action, model: model)
                            .frame(width: tileWidth, height: HomeDashboardStyle.shortcutHeight)
                    }
                }
                .padding(HomeDashboardStyle.focusInset)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shortcuts")
        .accessibilityIdentifier("notchium.home.shortcuts")
    }
}

private struct ShortcutTile: View {
    let action: QuickAction
    let model: QuickActionsModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.notchHomePageVisible) private var isVisible
    @State private var hovered = false
    @FocusState private var focused: Bool
    private var issue: String? { model.runner.unavailable[action.id] }

    var body: some View {
        Button { model.runner.run(action) } label: {
            HStack(spacing: 6) {
                Group {
                    if model.runner.showingProgress.contains(action.id) { ProgressView().controlSize(.mini) }
                    else if issue != nil { Image(systemName: "exclamationmark.circle") }
                    else if model.runner.succeeded.contains(action.id) { Image(systemName: "checkmark") }
                    else { QuickActionIcon(action: action, runner: model.runner) }
                }.frame(width: 18, height: 18).accessibilityHidden(true)
                VStack(alignment: .center, spacing: 2) {
                    Text(action.displayName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    if issue != nil { Text("Unavailable").font(.system(size: 9)).lineLimit(1) }
                }
            }
            .foregroundStyle(.white.opacity(issue == nil ? 0.9 : 0.6))
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: HomeDashboardStyle.shortcutHeight, alignment: .center)
            .background(.white.opacity(hovered ? 0.13 : 0.06), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    .white.opacity(focused ? 0.9 : (contrast == .increased ? 0.5 : 0.08)), lineWidth: focused ? 2 : 1)
            }
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(NotchUtilityButtonStyle())
        .focused($focused)
        .onHover { hovered = $0 }
        .disabled(!model.runner.canRun(action))
        .help(issue ?? action.displayName)
        .accessibilityLabel(action.displayName)
        .accessibilityValue(issue ?? (model.runner.running.contains(action.id) ? "Running" :
            (model.runner.succeeded.contains(action.id) ? "Completed" : action.kind.title)))
        .accessibilityHint(issue == nil ? "Run shortcut" : "Edit or reselect this shortcut in Customize Home")
        .accessibilityIdentifier("notchium.shortcut.\(action.id)")
        .task(id: Preparation(action: action, visible: isVisible)) {
            if isVisible { await model.runner.prepareHomeAction(action) }
        }
        .contextMenu {
            Button(issue == nil ? "Run" : "Retry") { Task { await model.runner.retry(action) } }
                .disabled(model.runner.running.contains(action.id))
            if model.runner.running.contains(action.id) { Button("Cancel Run") { model.runner.cancel(action.id) } }
            Button("Edit…") {
                model.requestedEditID = action.id
                NSApp.activate(ignoringOtherApps: true); openSettings()
            }
            Button("Unpin from Home") {
                var changed = action; changed.pinnedToHome = false; try? model.store.save(changed)
            }
            Button("Remove", role: .destructive) { try? model.store.remove(action.id) }
        }
    }
    private struct Preparation: Equatable {
        let action: QuickAction
        let visible: Bool
    }
}

struct QuickActionIcon: View {
    let action: QuickAction
    let runner: QuickActionRunner
    var body: some View {
        Group {
            if let symbol = action.symbol { Image(systemName: symbol).resizable().scaledToFit() }
            else if let image = runner.icon(for: action) { Image(nsImage: image).resizable().scaledToFit() }
            else {
                Image(systemName: action.kind == .systemAction
                    ? (NativeHomeAction(rawValue: action.target)?.symbol ?? action.kind.symbol) : action.kind.symbol)
                    .resizable().scaledToFit()
            }
        }.frame(width: 18, height: 18).accessibilityHidden(true)
    }
}
