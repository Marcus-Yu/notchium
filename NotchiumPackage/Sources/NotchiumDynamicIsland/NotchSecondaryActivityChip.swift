import SwiftUI

/// Content slots in the single shell. All frames are shared with AppKit hit testing.
enum NotchSecondaryGeometry {
    static let bodyWidth: CGFloat = 32
    static let contentSize: CGFloat = 20

    static func primaryWidth(layout: NotchPanelLayout, notification: NotchNotification?) -> CGFloat {
        switch notification?.presentationStyle {
        case .compact?: NotchCompactGeometry(layout: layout, activity: notification?.content.compactActivity).width
        case .calendar?: NotchNotificationGeometry.size(for: .calendar, layout: layout).width
        default: CollapsedMediaGeometry(hardwareWidth: layout.hardwareNotchGeometry?.frame.width ?? 0,
                                        hardwareHeight: layout.collapsedVisibleFrame.height).width
        }
    }

    static func shellWidth(layout: NotchPanelLayout, notification: NotchNotification?, hasIndicators: Bool) -> CGFloat {
        let primary = primaryWidth(layout: layout, notification: notification)
        // Calendar's existing banner contains the flanks. Compact primaries grow the actual
        // silhouette symmetrically so the hardware and primary content remain centered.
        return hasIndicators && notification?.presentationStyle != .calendar ? primary + bodyWidth * 2 : primary
    }

    static func frame(layout: NotchPanelLayout, beside notification: NotchNotification? = nil,
                      kind: NotchActivityKind = .download) -> CGRect {
        let height = layout.collapsedVisibleFrame.height
        let center = layout.collapsedVisibleFrame.midX
        let hardware = layout.hardwareNotchGeometry?.frame.width ?? layout.collapsedVisibleFrame.width
        let x: CGFloat
        if notification?.presentationStyle == .calendar {
            x = kind == .media ? center + hardware / 2 : center - hardware / 2 - bodyWidth
        } else {
            x = center + primaryWidth(layout: layout, notification: notification) / 2 - 6
        }
        return CGRect(x: x, y: layout.collapsedVisibleFrame.maxY - height, width: bodyWidth, height: height)
    }
}

/// Only glyphs and hit targets. Fill, clipping and animation belong to the outer shell.
struct NotchSecondaryActivityChip: View {
    let model: DynamicIslandPresentationModel
    let layout: NotchPanelLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.presentedIndicators) { activity in
                let frame = NotchSecondaryGeometry.frame(layout: layout, beside: model.presentedNotification,
                                                          kind: activity.kind)
                Button { model.activateIndicator(activity) } label: {
                    content(for: activity)
                        .frame(width: frame.width, height: frame.height)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(activity.kind == .media ? "Music" : activity.title)")
                .accessibilityIdentifier("notchium.secondary.\(activity.kind.rawValue)")
                .offset(x: frame.minX - layout.panelFrame.minX)
            }
        }
        .frame(width: layout.panelFrame.width, height: layout.collapsedVisibleFrame.height, alignment: .topLeading)
    }

    @ViewBuilder private func content(for activity: NotchActivity) -> some View {
        let size = NotchSecondaryGeometry.contentSize
        switch activity.minimal {
        case .artwork:
            model.mediaRenderer?.mediaArtwork(size: size)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: 5, style: .continuous))
        case let .glyph(.symbol(name, variableValue), tint):
            Image(systemName: name, variableValue: variableValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint.color)
        case let .glyph(.device(style, _), tint):
            Image(systemName: style.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint.color)
        case let .glyph(.thumbnail(url), _):
            NotchThumbnailView(url: url, size: CGSize(width: size, height: size), cornerRadius: 4)
        case let .progress(fraction):
            NotchProgressRing(fraction: fraction, reduceMotion: model.reduceMotion)
                .frame(width: 15, height: 15)
        case nil:
            EmptyView()
        }
    }
}

/// A thin determinate ring, or a quiet native spinner when progress is unknown. Only the
/// arc moves; value changes glide rather than jump.
struct NotchProgressRing: View {
    let fraction: Double?
    let reduceMotion: Bool

    var body: some View {
        if let fraction {
            ZStack {
                Circle().stroke(.white.opacity(0.22), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : NotchMotion.compactLevel, value: fraction)
            }
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int((min(max(fraction, 0), 1) * 100).rounded())) percent")
        } else {
            ProgressView().controlSize(.mini).tint(.white)
        }
    }
}
