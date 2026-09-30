import SwiftUI

/// One small black tab hanging from the top edge just past the primary's trailing edge.
/// It carries only a glyph or artwork: never text, never a second banner.
enum NotchSecondaryGeometry {
    static let bodyWidth: CGFloat = 32
    static let shoulderRadius: CGFloat = 4
    static let gap: CGFloat = 8
    static let contentSize: CGFloat = 20

    /// Screen-space interaction frame (the body, not the shoulder flare). `beside` is the
    /// compact primary; nil means Music's collapsed flanks are the primary.
    static func frame(layout: NotchPanelLayout, beside compact: NotchCompactActivity?) -> CGRect {
        let height = layout.collapsedVisibleFrame.height
        let primaryHalfWidth = compact.map { NotchCompactGeometry(layout: layout, activity: $0).width / 2 }
            ?? CollapsedMediaGeometry(hardwareWidth: layout.hardwareNotchGeometry?.frame.width ?? 0,
                                      hardwareHeight: height).width / 2
        return CGRect(x: layout.collapsedVisibleFrame.midX + primaryHalfWidth + gap + shoulderRadius,
                      y: layout.collapsedVisibleFrame.maxY - height,
                      width: bodyWidth, height: height)
    }
}

extension NotchMotion {
    /// The chip settles in once the primary has mostly grown, so the two never race.
    static let secondaryIn = Animation.interactiveSpring(response: 0.32, dampingFraction: 0.86, blendDuration: 0).delay(0.1)
    static let secondaryOut = Animation.easeOut(duration: 0.14)
    /// Follows the primary's edge when it resizes (e.g. compact ↔ Music after promotion).
    static let secondaryMove = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.9, blendDuration: 0)
}

struct NotchSecondaryActivityChip: View {
    let model: DynamicIslandPresentationModel
    let layout: NotchPanelLayout

    var body: some View {
        let secondary = model.presentedSecondary
        let frame = NotchSecondaryGeometry.frame(layout: layout,
                                                 beside: model.presentedNotification?.content.compactActivity)
        let shoulder = NotchSecondaryGeometry.shoulderRadius
        ZStack {
            if let secondary {
                Button(action: model.activateSecondaryActivity) {
                    content(for: secondary)
                        .frame(width: frame.width + shoulder * 2, height: frame.height)
                        .background(NotchSecondaryChipShape(shoulderRadius: shoulder,
                                                            bottomRadius: min(12, frame.height * 0.4)).fill(.black))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(secondary.kind == .media ? "Music" : secondary.title)")
                .accessibilityIdentifier("notchium.secondary.activity")
                // A promotion changes role, not identity: the same key keeps the same view.
                .id(secondary.key)
                .transition(model.reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.4, anchor: .leading))
                        .animation(NotchMotion.secondaryIn),
                    removal: .opacity.combined(with: .scale(scale: 0.7, anchor: .leading))
                        .animation(NotchMotion.secondaryOut)))
            }
        }
        .frame(width: frame.width + shoulder * 2, height: frame.height)
        .offset(x: frame.minX - shoulder - layout.panelFrame.minX)
        .animation(model.reduceMotion ? nil : NotchMotion.secondaryMove, value: frame.minX)
        .animation(model.reduceMotion ? NotchMotion.reduced : NotchMotion.secondaryIn, value: secondary?.key)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        case let .glyph(.device(style), tint):
            Image(systemName: style.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint.color)
        case nil:
            EmptyView()
        }
    }
}

/// A top-attached tab: concave shoulders into the screen edge, rounded lower corners.
struct NotchSecondaryChipShape: Shape {
    let shoulderRadius: CGFloat
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = shoulderRadius
        let r = min(bottomRadius, (rect.width - s * 2) / 2, rect.height - s)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s, y: rect.minY + s),
                          control: CGPoint(x: rect.minX + s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s + r, y: rect.maxY),
                          control: CGPoint(x: rect.minX + s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - s, y: rect.maxY - r),
                          control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - s, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
