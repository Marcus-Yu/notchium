import SwiftUI

struct ExpandedTopSurface: Shape {
    var bottomRadius: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.width - r, y: rect.height),
            control: CGPoint(x: rect.width, y: rect.height)
        )
        path.addLine(to: CGPoint(x: r, y: rect.height))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height - r),
            control: CGPoint(x: 0, y: rect.height)
        )
        path.closeSubpath()
        return path
    }
}

/// Keeps native geometry interpolation alive when returning to the empty
/// passive endpoint. Expanded paths never subtract the hardware footprint.
struct NotchShellSurface: Shape {
    var width: CGFloat
    var height: CGFloat
    var centerX: CGFloat
    var bottomRadius: CGFloat
    let passiveShape: NotchShape
    var reminderHeight: CGFloat = 0

    var animatableData: AnimatablePair<
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>,
        CGFloat
    > {
        get {
            AnimatablePair(
                AnimatablePair(AnimatablePair(width, height), AnimatablePair(centerX, bottomRadius)),
                reminderHeight
            )
        }
        set {
            width = newValue.first.first.first
            height = newValue.first.first.second
            centerX = newValue.first.second.first
            bottomRadius = newValue.first.second.second
            reminderHeight = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let totalHeight = height + max(0, reminderHeight)
        let isExpanded = reminderHeight > 0 || width > passiveShape.width || totalHeight > passiveShape.height
        if isExpanded {
            return ExpandedTopSurface(bottomRadius: max(0, bottomRadius))
                .path(in: CGRect(x: 0, y: 0, width: width, height: totalHeight))
                .applying(CGAffineTransform(translationX: centerX - width / 2, y: rect.minY))
        } else {
            return passiveShape.path(in: rect)
        }
    }
}
