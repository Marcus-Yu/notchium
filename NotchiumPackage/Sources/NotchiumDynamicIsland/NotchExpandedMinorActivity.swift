import SwiftUI

enum NotchExpandedMinorGeometry {
    static let width: CGFloat = 292
    static let height: CGFloat = NotchNotificationGeometry.audioHeight

    static func frame(layout: NotchPanelLayout) -> CGRect {
        CGRect(x: layout.panelFrame.midX - width / 2,
               y: layout.panelFrame.maxY - layout.expandedSize.height - height,
               width: width, height: height)
    }
}

/// Keeps the existing page mounted while the same shell grows a short bottom extension.
/// Retention is visual only; coordinator identity, repeat coalescing and expiry stay authoritative.
struct NotchExpandedMinorActivitySlot: View {
    let model: DynamicIslandPresentationModel
    let layout: NotchPanelLayout
    @Environment(\.notchExpandedMinorReveal) private var reveal
    @State private var retained: Presentation?

    private struct Presentation: Equatable {
        let activity: NotchActivity
        let compact: NotchCompactActivity?
    }

    private var current: Presentation? {
        model.expandedMinorActivity.map {
            Presentation(activity: $0, compact: model.notificationCoordinator.active?.content.compactActivity)
        }
    }

    var body: some View {
        let shown = current ?? (reveal > 0.001 ? retained : nil)
        ZStack {
            if let shown {
                if let compact = shown.compact {
                    NotchCompactActivityView(activity: compact,
                        geometry: NotchCompactGeometry(layout: layout, activity: compact),
                        reveal: reveal, entryID: shown.activity.id, reduceMotion: model.reduceMotion,
                        action: {}, inlineWidth: NotchExpandedMinorGeometry.width - 24)
                } else {
                    // Generic system HUDs (including the existing brightness fixture) keep
                    // their source-provided title/status without inventing a hardware value.
                    VStack(spacing: 4) {
                        Text(shown.activity.title).font(.system(size: 12, weight: .semibold))
                        if let subtitle = shown.activity.subtitle {
                            Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 24)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(width: NotchExpandedMinorGeometry.width, height: NotchExpandedMinorGeometry.height)
        .mask(alignment: .top) {
            Rectangle().frame(height: NotchExpandedMinorGeometry.height * reveal)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(current == nil)
        .onChange(of: current, initial: true) { _, value in
            if let value { retained = value }
        }
    }
}
