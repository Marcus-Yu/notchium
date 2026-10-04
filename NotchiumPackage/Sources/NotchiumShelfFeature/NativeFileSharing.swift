import AppKit
import NotchiumDynamicIsland
import SwiftUI

/// Owns at most one native sharing presentation (Share picker or AirDrop) at a time. A new
/// request while one is active is refused rather than overlapping: ShareKit raises an internal
/// inconsistency exception when a second presentation starts over a live one.
@MainActor
@Observable
final class NativeFileSharing {
    /// Observed by the Shelf so Share/AirDrop are disabled for the session's lifetime.
    private(set) var isActive = false
    @ObservationIgnored private var session: NativeSharingSession?
    @ObservationIgnored var makeAirDropService: () -> NSSharingService? = { NSSharingService(named: .sendViaAirDrop) }

    func share(_ urls: [URL], from view: NSView, interaction: NotchAuxiliaryInteractionHandler) -> ShareOutcome {
        guard session == nil else { return .inProgress }
        guard !urls.isEmpty, view.window != nil else { return .unavailable }
        let session = begin(window: view.window, interaction: interaction)
        let picker = NSSharingServicePicker(items: urls)
        session.picker = picker
        picker.delegate = session
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        return .presented
    }

    /// Items and the service are validated before the session takes any ownership.
    func airDrop(_ urls: [URL], from view: NSView?, interaction: NotchAuxiliaryInteractionHandler) -> ShareOutcome {
        guard session == nil else { return .inProgress }
        guard !urls.isEmpty, let service = makeAirDropService(),
              service.canPerform(withItems: urls) else { return .unavailable }
        let session = begin(window: view?.window, interaction: interaction, returnsToOpenSession: true, service: service)
        service.perform(withItems: urls)
        // ShareKit accepts a presentation synchronously (`willShareItems`). One that was neither
        // accepted nor finished during `perform` never presents and gets no later callback.
        if !session.hasStarted { session.finish() }
        return self.session === session ? .presented : .unavailable
    }

    @discardableResult
    func begin(window: NSWindow?, interaction: NotchAuxiliaryInteractionHandler,
               returnsToOpenSession: Bool = false, service: NSSharingService? = nil) -> NativeSharingSession {
        let session = NativeSharingSession(window: window, interaction: interaction,
                                           returnsToOpenSession: returnsToOpenSession) { [weak self] ended in
            guard let self, self.session === ended else { return }
            self.session = nil
            self.isActive = false
        }
        self.session = session
        isActive = true
        interaction.beginNativeSharing(in: window, source: session.source)
        if let service { session.adopt(service) }
        return session
    }
}

/// One native presentation, from picker entry through its terminal event. It is the delegate
/// itself: ShareKit calls back with a different `NSSharingService` instance than the one
/// performed, so a session is identified by the object its callbacks reach, never the service.
/// Terminal events are the service/picker callbacks and the presentation's windows closing,
/// which also covers a sheet torn down without a callback. The lease is released exactly once.
@MainActor
final class NativeSharingSession: NSObject, @MainActor NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    let source = "native.share.\(UUID())"
    var picker: NSSharingServicePicker?
    private(set) var hasStarted = false
    private(set) var hasEnded = false
    private var service: NSSharingService?
    private weak var sourceWindow: NSWindow?
    private let interaction: NotchAuxiliaryInteractionHandler
    private var returnsToOpenSession: Bool
    private let onEnd: (NativeSharingSession) -> Void
    private var presentationWindows: [ObjectIdentifier: WeakWindow] = [:]
    private var windowObservers: [any NSObjectProtocol] = []

    init(window: NSWindow?, interaction: NotchAuxiliaryInteractionHandler, returnsToOpenSession: Bool,
         onEnd: @escaping (NativeSharingSession) -> Void) {
        sourceWindow = window
        self.interaction = interaction
        self.returnsToOpenSession = returnsToOpenSession
        self.onEnd = onEnd
    }

    /// The service now presenting; from here the windows it brings up belong to this session.
    func adopt(_ service: NSSharingService) {
        self.service = service
        service.delegate = self
        guard windowObservers.isEmpty else { return }
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated {
                    guard let self, let window, window !== self.sourceWindow else { return }
                    self.presentationWindows[ObjectIdentifier(window)] = WeakWindow(window: window)
                }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    self.presentationWindows[ObjectIdentifier(window)]?.isClosed = true
                    self.finishIfPresentationGone()
                }
            },
        ] + [NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishIfPresentationGone() }
            }
        }
    }

    /// Closing one sheet window can merely order its companions out, which posts no close.
    private func finishIfPresentationGone() {
        guard !presentationWindows.isEmpty,
              presentationWindows.values.allSatisfy({ $0.isClosed || $0.window?.isVisible != true }) else { return }
        finish()
    }

    func finish() {
        guard !hasEnded else { return }
        hasEnded = true
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()
        picker?.delegate = nil
        service?.delegate = nil
        picker = nil
        service = nil
        interaction.endNativeSharing(in: sourceWindow, source: source, returnsToOpenSession: returnsToOpenSession)
        onEnd(self)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard !hasEnded else { return }
        guard let service else { finish(); return }
        // AirDrop chosen through Share uses the same standalone presentation and return rule.
        returnsToOpenSession = service == NSSharingService(named: .sendViaAirDrop)
        hasStarted = true
        // Picker dismissal does not end the selected service's interaction lease.
        adopt(service)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? { self }

    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        // ShareKit dims the entire source window for AirDrop. Our transparent host is much
        // larger than the drawn notch, producing a rectangular dimming artifact. Let macOS
        // present its centered standalone picker; the interaction lease still owns the notch.
        sharingService == NSSharingService(named: .sendViaAirDrop) ? nil : sourceWindow
    }

    func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) { hasStarted = true }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        finish()
    }
}

private struct WeakWindow {
    weak var window: NSWindow?
    var isClosed = false
}

/// Exposes the actual host window without a delayed dispatch or a global window lookup.
struct FileSharingAnchor: NSViewRepresentable {
    let model: FilesFeatureModel
    @Environment(\.notchAuxiliaryInteraction) private var interaction

    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) {
        view.model = model
        view.interaction = interaction
        model.sharingAnchor = view
        model.sharingInteraction = interaction
    }

    final class AnchorView: NSView {
        weak var model: FilesFeatureModel?
        var interaction = NotchAuxiliaryInteractionHandler()
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                model?.sharingAnchor = self
                model?.sharingInteraction = interaction
            }
        }
    }
}
