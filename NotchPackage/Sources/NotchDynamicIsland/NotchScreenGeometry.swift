import AppKit
import CoreGraphics

public struct NotchScreenGeometry: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let frame: CGRect
    public let safeAreaTop: CGFloat
    public let notchGap: CGRect?

    public var panelFrame: CGRect {
        let preferredWidth: CGFloat = 220
        let gapWidth = notchGap?.width ?? 0
        let width = max(preferredWidth, gapWidth)
        let height = max(44, safeAreaTop)

        return CGRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    @MainActor
    public static func builtInNotchedScreen() -> (screen: NSScreen, geometry: Self)? {
        for screen in NSScreen.screens {
            guard
                let displayID = screen.displayID,
                CGDisplayIsBuiltin(displayID) != 0,
                screen.safeAreaInsets.top > 0
            else {
                continue
            }

            let notchGap: CGRect?
            if
                let leftArea = screen.auxiliaryTopLeftArea,
                let rightArea = screen.auxiliaryTopRightArea,
                rightArea.minX > leftArea.maxX
            {
                notchGap = CGRect(
                    x: leftArea.maxX,
                    y: min(leftArea.minY, rightArea.minY),
                    width: rightArea.minX - leftArea.maxX,
                    height: max(leftArea.height, rightArea.height)
                )
            } else {
                notchGap = nil
            }

            return (
                screen,
                NotchScreenGeometry(
                    displayID: displayID,
                    frame: screen.frame,
                    safeAreaTop: screen.safeAreaInsets.top,
                    notchGap: notchGap
                )
            )
        }

        return nil
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
