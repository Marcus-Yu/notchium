import AppKit
import CoreGraphics

@MainActor
protocol NotchiumDisplaySnapshotting: AnyObject {
    func snapshots() -> [NotchiumDisplaySnapshot]
}

@MainActor
final class AppKitDisplaySource: NotchiumDisplaySnapshotting {
    func snapshots() -> [NotchiumDisplaySnapshot] {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.enumerated().compactMap { index, screen in
            guard let displayID = screen.notchiumDisplayID else { return nil }
            return NotchiumDisplaySnapshot(
                id: NotchiumDisplayID(rawValue: displayID),
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                safeAreaInsets: NotchiumDisplayInsets(
                    top: screen.safeAreaInsets.top,
                    leading: screen.safeAreaInsets.left,
                    bottom: screen.safeAreaInsets.bottom,
                    trailing: screen.safeAreaInsets.right
                ),
                auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                isPrimary: index == 0,
                containsMousePointer: screen.frame.contains(mouseLocation),
                backingScaleFactor: screen.backingScaleFactor,
                statusBarThickness: NSStatusBar.system.thickness
            )
        }
    }
}

private extension NSScreen {
    var notchiumDisplayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
