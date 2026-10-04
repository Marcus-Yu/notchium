import AppKit
import CoreGraphics
import IOKit.pwr_mgt

@MainActor
protocol DisplayEnvironmentReading: AnyObject {
    var pointerLocation: CGPoint? { get }
    func evidence(displays: [NotchiumDisplaySnapshot]) -> DisplayInteractionEvidence
    func start(onChange: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class EmptyDisplayEnvironmentSource: DisplayEnvironmentReading {
    var pointerLocation: CGPoint? { nil }
    func evidence(displays: [NotchiumDisplaySnapshot]) -> DisplayInteractionEvidence { .init() }
    func start(onChange: @escaping @MainActor () -> Void) {}
    func stop() {}
}

@MainActor
final class AppKitDisplayEnvironmentSource: DisplayEnvironmentReading {
    private var observation: NSKeyValueObservation?
    private var generation = 0
#if DEBUG
    private var lastDiagnosticEvidence: DisplayInteractionEvidence?
#endif
    var pointerLocation: CGPoint? { NSEvent.mouseLocation }

    func start(onChange: @escaping @MainActor () -> Void) {
        stop()
        let generation = generation
        // Documented KVO catches presentation changes within an existing fullscreen Space,
        // where neither an app activation nor a Space-change notification is guaranteed.
        observation = NSApplication.shared.observe(\.currentSystemPresentationOptions) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, generation == self.generation else { return }
                onChange()
            }
        }
    }

    func stop() {
        generation &+= 1
        observation?.invalidate()
        observation = nil
    }

    isolated deinit { observation?.invalidate() }

    func evidence(displays: [NotchiumDisplaySnapshot]) -> DisplayInteractionEvidence {
        let options = NSApplication.shared.currentSystemPresentationOptions
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Read bounds/layer/PID only. Never request titles, AX permissions, or screen capture.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let quartzFrames = windows.compactMap { window -> CGRect? in
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), !frame.isEmpty else { return nil }
            return frame
        }
        // Only a fullscreen app pays for the assertion read.
        let keepsDisplayAwake = options.contains(.fullScreen) && pid.map(Self.preventsDisplaySleep) == true
        let result = Self.project(options: options, quartzFrames: quartzFrames, pointerLocation: pointerLocation,
                                  displays: displays, frontmostPreventsDisplaySleep: keepsDisplayAwake)
#if DEBUG
        var diagnostic = result
        diagnostic.pointerLocation = nil
        if diagnostic != lastDiagnosticEvidence {
            lastDiagnosticEvidence = diagnostic
            print("[Notchium Environment] fullscreen=\(result.isFullscreen) immersive=\(result.isImmersiveMedia) presentation=\(result.isPresentationLike) frontDisplay=\(String(describing: result.frontmostDisplayID?.rawValue)) contextDisplay=\(String(describing: result.fullscreenDisplayID?.rawValue))")
        }
#endif
        return result
    }

    /// Deterministic projection of public window evidence, independent of WindowServer access.
    static func project(options: NSApplication.PresentationOptions, quartzFrames: [CGRect],
                        pointerLocation: CGPoint?, displays: [NotchiumDisplaySnapshot],
                        frontmostPreventsDisplaySleep: Bool = false) -> DisplayInteractionEvidence {
        // Quartz's origin is the primary display's TOP left, not the union of screens.
        let primaryTop = displays.first(where: \.isPrimary)?.frame.maxY ?? 0
        let frames = quartzFrames.map { frame in
            CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
        }
        let frontmost = frames.first.flatMap { frame in
            displays.max { intersectionArea(frame, $0.frame) < intersectionArea(frame, $1.frame) }
                .flatMap { intersectionArea(frame, $0.frame) > 0 ? $0.id : nil }
        }
        let fullscreenDisplay = displays.first { display in
            frames.contains { frame in
                abs(frame.minX - display.frame.minX) <= 2
                    && abs(frame.width - display.frame.width) <= 2
                    && abs(frame.minY - display.frame.minY) <= 2
                    && (abs(frame.maxY - display.frame.maxY) <= 2
                        || abs(frame.maxY - (display.frame.maxY - display.safeAreaInsets.top)) <= 2)
            }
        }?.id
        return .init(pointerLocation: pointerLocation,
                     frontmostDisplayID: frontmost,
                     fullscreenDisplayID: fullscreenDisplay ?? frontmost,
                     isFullscreen: options.contains(.fullScreen),
                     // Playback is what turns a fullscreen Space immersive: video players and
                     // browsers hold a display-sleep assertion only while media plays.
                     isImmersiveMedia: options.contains(.fullScreen) && frontmostPreventsDisplaySleep,
                     // Permanent UI hiding or process-switch restriction is stronger than
                     // ordinary fullscreen's auto-hide flags. No bundle-ID allowlist.
                     isPresentationLike: options.contains(.hideMenuBar)
                        && (options.contains(.hideDock) || options.contains(.disableProcessSwitching)))
    }

    /// Public power-management read of the frontmost process's own assertions. An error or an
    /// assertion held by a helper process conservatively reads as "not immersive".
    static func preventsDisplaySleep(pid: pid_t) -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]],
              let assertions = byProcess[NSNumber(value: pid)] else { return false }
        let displayTypes: Set<String> = [kIOPMAssertPreventUserIdleDisplaySleep as String,
                                         kIOPMAssertionTypeNoDisplaySleep as String]
        return assertions.contains { assertion in
            (assertion[kIOPMAssertionTypeKey as String] as? String).map(displayTypes.contains) == true
                && (assertion[kIOPMAssertionLevelKey as String] as? Int) != 0
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
