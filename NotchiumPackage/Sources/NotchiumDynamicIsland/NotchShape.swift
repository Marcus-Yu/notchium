import SwiftUI

/// A single top-attached silhouette used for every Stage 2 presentation state.
///
/// Width, height, horizontal center, and both corner parameters interpolate
/// inside the fixed host panel. The shape therefore grows downward and outward
/// without moving its top edge or swapping to a second rounded-rectangle view.
struct NotchShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var centerX: CGFloat
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>
    > {
        get {
            AnimatablePair(
                AnimatablePair(width, height),
                AnimatablePair(
                    centerX,
                    AnimatablePair(topCornerRadius, bottomCornerRadius)
                )
            )
        }
        set {
            width = newValue.first.first
            height = newValue.first.second
            centerX = newValue.second.first
            topCornerRadius = newValue.second.second.first
            bottomCornerRadius = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let resolvedWidth = max(0, min(width, rect.width))
        let resolvedHeight = max(0, min(height, rect.height))
        let resolvedCenterX = max(
            rect.minX + resolvedWidth / 2,
            min(centerX, rect.maxX - resolvedWidth / 2)
        )
        let surface = CGRect(
            x: resolvedCenterX - resolvedWidth / 2,
            y: rect.minY,
            width: resolvedWidth,
            height: resolvedHeight
        )
        guard surface.width > 0, surface.height > 0 else { return Path() }

        let topRadius = max(
            0,
            min(topCornerRadius, surface.width / 4, surface.height / 4)
        )
        let bottomRadius = max(
            0,
            min(
                bottomCornerRadius,
                (surface.width - 2 * topRadius) / 2,
                surface.height - topRadius
            )
        )
        let leftWall = surface.minX + topRadius
        let rightWall = surface.maxX - topRadius

        var path = Path()
        path.move(to: CGPoint(x: surface.minX, y: surface.minY))
        path.addLine(to: CGPoint(x: surface.maxX, y: surface.minY))
        path.addQuadCurve(
            to: CGPoint(x: rightWall, y: surface.minY + topRadius),
            control: CGPoint(x: rightWall, y: surface.minY)
        )
        path.addLine(to: CGPoint(x: rightWall, y: surface.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rightWall - bottomRadius, y: surface.maxY),
            control: CGPoint(x: rightWall, y: surface.maxY)
        )
        path.addLine(to: CGPoint(x: leftWall + bottomRadius, y: surface.maxY))
        path.addQuadCurve(
            to: CGPoint(x: leftWall, y: surface.maxY - bottomRadius),
            control: CGPoint(x: leftWall, y: surface.maxY)
        )
        path.addLine(to: CGPoint(x: leftWall, y: surface.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: surface.minX, y: surface.minY),
            control: CGPoint(x: leftWall, y: surface.minY)
        )
        path.closeSubpath()
        return path
    }
}
