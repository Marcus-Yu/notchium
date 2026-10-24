import AppKit
import SwiftUI
import XCTest
import NotchiumCore
import NotchiumPersistence
import NotchiumServices
@testable import NotchiumFeature

@MainActor final class OnboardingRenderTests: XCTestCase {
    func testMinimumWindowAllStagesLongDisclosureAndDenialInBothAppearances() async throws {
        let screens: [(OnboardingState.Step, SetupPermission)] = [
            (.welcome, .calendar), (.overview, .calendar),
            (.permissions, .systemAudio), (.permissions, .volumeKeys), (.permissions, .clipboardAccess),
            (.review, .calendar), (.ready, .calendar)
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (step, permission) in screens {
                var state = OnboardingState()
                state.step = step
                state.currentPermission = permission
                if step == .permissions { state.clipboardChoice = false }
                if step == .ready { state.completion = .userCompleted }
                let permissions = RenderSetupPermissions()
                let native = NativeOnboardingPermissions(camera: MockCameraService(), profile: .freeDirect,
                                                          pasteboardBehavior: { .default })
                permissions.audio = await native.status(for: .systemAudio)
                permissions.clipboard = await native.status(for: .clipboardAccess)
                let model = OnboardingModel(store: InMemoryOnboardingStore(state: state), permissions: permissions)
                await model.refresh()
                let size = NSSize(width: 620, height: 520)
                let host = NSHostingView(rootView: OnboardingView(model: model, enterApp: {})
                    .environment(\.colorScheme, scheme).frame(width: size.width, height: size.height))
                host.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.orderBack(nil)
                defer { window.close() }
                // Rendering requires a native display pass, separate from domain timing.
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                XCTAssertEqual(host.bounds.size, size)
                XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                if let path = ProcessInfo.processInfo.environment["NOTCHIUM_SETUP_RENDER_DIR"] {
                    let directory = URL(fileURLWithPath: path)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let name = "\(scheme == .dark ? "dark" : "light")-\(step.rawValue)-\(permission.rawValue)-620x520.png"
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: directory.appendingPathComponent(name), options: .atomic)
                }
            }
        }
    }
}

@MainActor private final class RenderSetupPermissions: OnboardingPermissionProviding {
    var audio = SetupPermissionStatus(.notPregrantable)
    var clipboard = SetupPermissionStatus(.notPregrantable)
    func status(for permission: SetupPermission) async -> SetupPermissionStatus {
        if permission == .systemAudio { return audio }
        if permission == .clipboardAccess { return clipboard }
        if permission == .volumeKeys {
            return .init(.denied, "Allow Accessibility for volume-key replacement in System Settings → Privacy & Security → Accessibility. This grant does not enable replacement. Typed text is never read or stored.")
        }
        return .init(.granted)
    }
    func request(_ permission: SetupPermission) async throws { }
    func openSettings(for permission: SetupPermission) { }
    func setClipboardConsent(_ enabled: Bool) { }
}
