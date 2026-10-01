import AppKit
import NotchiumDynamicIsland
import SwiftUI

/// One retained native presentation session, from picker entry through service completion.
/// Cancellation is delivered by the picker (nil choice) or the service's failure delegate.
@MainActor
final class NativeFileSharing: NSObject, @MainActor NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private var picker: NSSharingServicePicker?
    private var service: NSSharingService?
    private weak var sourceWindow: NSWindow?
    private var interaction = NotchAuxiliaryInteractionHandler()
    private var source: String?
    private var returnsToOpenSession = false

    func share(_ urls: [URL], from view: NSView, interaction: NotchAuxiliaryInteractionHandler) -> ShareOutcome {
        guard source == nil, !urls.isEmpty, view.window != nil else { return .unavailable }
        begin(window: view.window, interaction: interaction)
        let picker = NSSharingServicePicker(items: urls)
        self.picker = picker
        picker.delegate = self
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        return .presented
    }

    func airDrop(_ urls: [URL], from view: NSView?, interaction: NotchAuxiliaryInteractionHandler) -> ShareOutcome {
        guard source == nil, let service = NSSharingService(named: .sendViaAirDrop),
              !urls.isEmpty, service.canPerform(withItems: urls) else { return .unavailable }
        begin(window: view?.window, interaction: interaction, returnsToOpenSession: true)
        self.service = service
        service.delegate = self
        service.perform(withItems: urls)
        return .presented
    }

    func begin(window: NSWindow?, interaction: NotchAuxiliaryInteractionHandler,
               returnsToOpenSession: Bool = false) {
        sourceWindow = window
        self.returnsToOpenSession = returnsToOpenSession
        self.interaction = interaction
        let source = "native.share.\(UUID())"
        self.source = source
        interaction.beginNativeSharing(in: window, source: source)
    }

    private func finish() {
        guard let source else { return }
        interaction.endNativeSharing(in: sourceWindow, source: source,
                                     returnsToOpenSession: returnsToOpenSession)
        self.source = nil
        picker?.delegate = nil
        service?.delegate = nil
        picker = nil
        service = nil
        sourceWindow = nil
        returnsToOpenSession = false
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard let service else { finish(); return }
        // AirDrop chosen through Share uses the same standalone presentation and return rule.
        returnsToOpenSession = service == NSSharingService(named: .sendViaAirDrop)
        self.service = service
        service.delegate = self
        // Picker dismissal does not end the selected service's interaction lease.
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

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) { finish() }
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
