import SwiftUI
import NotchiumCore

struct HomeQuickActionsView: View {
    let model: QuickActionsModel
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        HStack(spacing: 12) {
            ForEach(model.store.pinned) { action in
                Button { model.runner.run(action) } label: {
                    HStack(spacing: 6) {
                        if model.runner.showingProgress.contains(action.id) {
                            ProgressView().controlSize(.small).frame(width: 20, height: 20)
                        } else { QuickActionIcon(action: action, runner: model.runner) }
                        Text(action.displayName).lineLimit(1)
                        if model.runner.unavailable[action.id] != nil {
                            Image(systemName: "exclamationmark.circle").accessibilityLabel("Unavailable")
                        }
                    }
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderless)
                .disabled(model.runner.running.contains(action.id))
                .help(model.runner.unavailable[action.id] ?? action.displayName)
                .accessibilityLabel(action.displayName)
                .contextMenu {
                    Button("Run") { model.runner.run(action) }
                    Button("Edit…") { model.requestedEditID = action.id; NSApp.activate(ignoringOtherApps: true); openSettings() }
                    Button("Unpin from Home") {
                        var changed = action; changed.pinnedToHome = false; try? model.store.save(changed)
                    }
                    Button("Remove", role: .destructive) { try? model.store.remove(action.id) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Actions")
    }
}

struct QuickActionIcon: View {
    let action: QuickAction
    let runner: QuickActionRunner
    var body: some View {
        Group {
            if let symbol = action.symbol { Image(systemName: symbol).resizable().scaledToFit() }
            else if let image = runner.workspace.icon(for: action) { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: action.kind.symbol).resizable().scaledToFit() }
        }.frame(width: 20, height: 20).accessibilityHidden(true)
    }
}
