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
    var hardwareExclusion: CGRect? = nil
    var extensionHeight: CGFloat = 0
    var extensionWidth: CGFloat = 0

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
        // Boolean path subtraction can retain degenerate boundary segments.
        // Return a truly empty path whenever the interpolated surface fits
        // within the hardware, including a spring's tiny closing undershoot.
        if let hardwareExclusion, hardwareExclusion.contains(surface) {
            return Path()
        }

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
        // Continuous lower corners: the curve starts a little earlier along each edge and
        // eases in, so the wall flows into the bottom without a visible tangent break.
        let extent = min(bottomRadius * 1.18, (surface.width - 2 * topRadius) / 2, surface.height - topRadius)
        let pull = extent * 0.6
        path.addLine(to: CGPoint(x: rightWall, y: surface.maxY - extent))
        path.addCurve(
            to: CGPoint(x: rightWall - extent, y: surface.maxY),
            control1: CGPoint(x: rightWall, y: surface.maxY - extent + pull),
            control2: CGPoint(x: rightWall - extent + pull, y: surface.maxY)
        )
        if extensionHeight > 0, extensionWidth > 0 {
            // Continue the bottom edge through the centered extension. These concave roots
            // and lower curves are part of this single outline, with no overlapping fills.
            let h = min(extensionHeight, max(0, rect.maxY - surface.maxY))
            let root = min(10, h / 2)
            let half = min(extensionWidth / 2, max(0, (rightWall - leftWall) / 2 - extent - root))
            let right = resolvedCenterX + half
            let left = resolvedCenterX - half
            let lower = min(bottomRadius * 0.6, h - root, half)
            let bottom = surface.maxY + h
            path.addLine(to: CGPoint(x: right + root, y: surface.maxY))
            path.addQuadCurve(to: CGPoint(x: right, y: surface.maxY + root),
                              control: CGPoint(x: right, y: surface.maxY))
            path.addLine(to: CGPoint(x: right, y: bottom - lower))
            path.addCurve(to: CGPoint(x: right - lower, y: bottom),
                          control1: CGPoint(x: right, y: bottom - lower * 0.4),
                          control2: CGPoint(x: right - lower * 0.4, y: bottom))
            path.addLine(to: CGPoint(x: left + lower, y: bottom))
            path.addCurve(to: CGPoint(x: left, y: bottom - lower),
                          control1: CGPoint(x: left + lower * 0.4, y: bottom),
                          control2: CGPoint(x: left, y: bottom - lower * 0.4))
            path.addLine(to: CGPoint(x: left, y: surface.maxY + root))
            path.addQuadCurve(to: CGPoint(x: left - root, y: surface.maxY),
                              control: CGPoint(x: left, y: surface.maxY))
        }
        path.addLine(to: CGPoint(x: leftWall + extent, y: surface.maxY))
        path.addCurve(
            to: CGPoint(x: leftWall, y: surface.maxY - extent),
            control1: CGPoint(x: leftWall + extent - pull, y: surface.maxY),
            control2: CGPoint(x: leftWall, y: surface.maxY - extent + pull)
        )
        path.addLine(to: CGPoint(x: leftWall, y: surface.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: surface.minX, y: surface.minY),
            control: CGPoint(x: leftWall, y: surface.minY)
        )
        path.closeSubpath()
        // Permanently exclude the measured hardware footprint. At rest the
        // entire path is excluded; expansion reveals only its growing perimeter.
        if let hardwareExclusion {
            return path.subtracting(Path(hardwareExclusion))
        }
        return path
    }
}
