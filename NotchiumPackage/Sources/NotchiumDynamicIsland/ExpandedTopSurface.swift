import SwiftUI

/// Keeps native geometry interpolation alive when returning to the empty
/// passive endpoint. Expanded paths never subtract the hardware footprint.
struct NotchShellSurface: Shape {
    var width: CGFloat
    var height: CGFloat
    var centerX: CGFloat
    var bottomRadius: CGFloat
    let passiveShape: NotchShape
    var reminderHeight: CGFloat = 0
    var reminderWidth: CGFloat = 0
    var reminderProgress: CGFloat = 1
    var shoulderRadius: CGFloat = 0
    var extensionHeight: CGFloat = 0

    var animatableData: AnimatablePair<
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>,
        AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>
    > {
        get {
            AnimatablePair(
                AnimatablePair(AnimatablePair(width, height), AnimatablePair(centerX, AnimatablePair(bottomRadius, shoulderRadius))),
                AnimatablePair(reminderHeight, AnimatablePair(reminderProgress, extensionHeight))
            )
        }
        set {
            width = newValue.first.first.first
            height = newValue.first.first.second
            centerX = newValue.first.second.first
            bottomRadius = newValue.first.second.second.first
            shoulderRadius = newValue.first.second.second.second
            reminderHeight = newValue.second.first
            reminderProgress = newValue.second.second.first
            extensionHeight = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let reveal = NotchReminderReveal(progress: reminderProgress)
        let surfaceWidth = width + max(0, reminderWidth - width) * reveal.width
        let totalHeight = height + max(0, reminderHeight) * reveal.height
        let isExpanded = reminderHeight * reveal.height > 0 || surfaceWidth > passiveShape.width || totalHeight > passiveShape.height
        guard isExpanded else { return passiveShape.path(in: rect) }

        var resolvedWidth = surfaceWidth
        var resolvedHeight = totalHeight
        var resolvedShoulder = max(0, shoulderRadius)
        var resolvedBottom = max(0, bottomRadius)
        if let hardware = passiveShape.hardwareExclusion {
            // An underdamped close can travel above the hardware's bottom edge.
            // Constrain the drawn geometry, shared by the fill and content mask,
            // while leaving the live spring free to reverse and settle naturally.
            resolvedWidth = max(resolvedWidth, hardware.width + 2 * abs(centerX - hardware.midX))
            resolvedHeight = max(resolvedHeight, hardware.maxY - rect.minY)
            let flank = max(0, min(hardware.minX - (centerX - resolvedWidth / 2),
                                   centerX + resolvedWidth / 2 - hardware.maxX))
            // Keep both the concave shoulder and the continuous lower corner
            // outside the hardware, even as media's flanks retract to zero.
            resolvedShoulder = min(resolvedShoulder, flank)
            resolvedBottom = min(resolvedBottom, (flank - resolvedShoulder) / NotchShape.lowerCornerExtentMultiplier)
        }
        // Use the same curve topology at zero shoulder radius. Switching to a
        // quadratic rounded rectangle at that endpoint made media corners pop.
        return NotchShape(width: resolvedWidth, height: resolvedHeight, centerX: centerX,
                          topCornerRadius: resolvedShoulder,
                          bottomCornerRadius: resolvedBottom,
                          extensionHeight: extensionHeight,
                          extensionWidth: NotchExpandedMinorGeometry.width).path(in: rect)
    }
}
