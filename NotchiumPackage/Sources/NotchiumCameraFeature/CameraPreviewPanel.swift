import AppKit
import NotchiumDesignSystem
import NotchiumDynamicIsland
import NotchiumServices
import SwiftUI

/// A small landscape mirror inside the expanded notch, with only the controls a pre-call
/// check needs: camera, mirror orientation, close.
struct CameraPreviewPanel: View {
    let model: CameraModel
    @NotchReducedMotion private var reduceMotion
    /// The system permission alert takes the pointer away; the notch stays open for its answer.
    @Environment(\.notchAuxiliaryInteraction) private var auxiliaryInteraction

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            tile
                .frame(width: 272, height: 153)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                }
            controls
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, ExpandedPageStyle.outerInset)
        .padding(.top, ExpandedPageStyle.topInset + 4)
        .padding(.bottom, ExpandedPageStyle.bottomInset)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mirror")
    }

    @ViewBuilder private var tile: some View {
        ZStack {
            Color.white.opacity(0.05)
            switch model.status {
            case .live:
                CameraPreviewLayerView(service: model.service, deviceID: model.activeDevice?.id)
                    .scaleEffect(x: model.isMirrored ? -1 : 1, y: 1)
                    // The feed settles in once frames arrive instead of popping.
                    .transition(.opacity.animation(.easeOut(duration: reduceMotion ? 0.1 : 0.35)))
                    .accessibilityLabel("Live camera preview")
                    .accessibilityAddTraits(.updatesFrequently)
                liveBadge
            case .idle, .starting:
                ProgressView().controlSize(.small).tint(.white)
            case .needsPermission:
                message("web.camera", "Notchium needs camera access to show your preview. Nothing is recorded.",
                        action: ("Allow Camera", requestAccess))
            case .denied:
                message("video.slash", "Camera access is off for Notchium.",
                        action: ("Open Settings", model.openPrivacySettings))
            case .noCamera:
                message("video.slash", "No camera is connected.", action: nil)
            case .failed:
                message("exclamationmark.triangle", "The camera couldn’t start. It may be in use.", action: nil)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.status)
    }

    private func requestAccess() {
        auxiliaryInteraction.begin(source: "camera.permission")
        model.requestAccess { [auxiliaryInteraction] in
            auxiliaryInteraction.end(actionSelected: true, source: "camera.permission")
        }
    }

    /// Clearly active: a small green dot, like the system indicator.
    private var liveBadge: some View {
        Circle().fill(Color(red: 0.2, green: 0.84, blue: 0.4))
            .frame(width: 6, height: 6)
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityHidden(true)
    }

    private func message(_ symbol: String, _ text: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 18, weight: .light)).foregroundStyle(.white.opacity(0.55))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(.white.opacity(0.14), in: .capsule)
            }
        }
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mirror").font(.system(size: 13, weight: .semibold))
            if model.devices.count > 1 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.devices) { device in
                            CameraChoiceRow(title: device.name, selected: device.id == model.activeDevice?.id) {
                                model.select(device)
                            }
                        }
                    }
                }
                .frame(maxHeight: 72)
                .scrollIndicators(.visible)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Camera")
            } else if let device = model.activeDevice ?? model.devices.first {
                Text(device.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            CameraChoiceRow(title: model.isMirrored ? "Mirrored" : "Natural",
                            symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                            selected: false) { model.isMirrored.toggle() }
                .accessibilityLabel("Orientation")
                .accessibilityValue(model.isMirrored ? "Mirrored" : "Natural")
                .accessibilityHint("Switches between a mirror image and what others see")
            Spacer(minLength: 0)
            Button(action: model.closePreview) {
                Label("Close", systemImage: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(.white.opacity(0.10), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Mirror")
            .accessibilityIdentifier("notchium.camera.close")
        }
    }
}

private struct CameraChoiceRow: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol ?? (selected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(selected || symbol != nil ? 0.9 : 0.4))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(selected || isHovered ? 1 : 0.7))
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(.white.opacity(isHovered ? 0.08 : 0), in: .rect(cornerRadius: 6, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Hosts the session's preview layer. A new layer is made per device so a switch never shows
/// the previous camera's last frame.
private struct CameraPreviewLayerView: NSViewRepresentable {
    let service: any CameraService
    let deviceID: String?

    func makeNSView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.install(service.makePreviewLayer(), for: deviceID)
        return view
    }

    func updateNSView(_ view: PreviewHostView, context: Context) {
        guard view.deviceID != deviceID else { return }
        view.install(service.makePreviewLayer(), for: deviceID)
    }

    final class PreviewHostView: NSView {
        private(set) var deviceID: String?
        private var preview: CALayer?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
        }

        required init?(coder: NSCoder) { nil }

        func install(_ layer: CALayer?, for id: String?) {
            preview?.removeFromSuperlayer()
            preview = layer
            deviceID = id
            guard let layer else { return }
            layer.frame = bounds
            self.layer?.addSublayer(layer)
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            preview?.frame = bounds
            CATransaction.commit()
        }
    }
}
