import Foundation

public struct NotchPanelLayout: Equatable, Sendable {
    public let panelFrame: CGRect
    public let surfaceSize: CGSize
    public let topInset: CGFloat
    public let physicalBridgeSize: CGSize?
    public let cornerRadius: CGFloat

    public init(
        panelFrame: CGRect,
        surfaceSize: CGSize,
        topInset: CGFloat,
        physicalBridgeSize: CGSize?,
        cornerRadius: CGFloat
    ) {
        self.panelFrame = panelFrame
        self.surfaceSize = surfaceSize
        self.topInset = topInset
        self.physicalBridgeSize = physicalBridgeSize
        self.cornerRadius = cornerRadius
    }
}

public enum NotchGeometryResolver {
    private static let horizontalMargin: CGFloat = 16
    private static let bottomMargin: CGFloat = 32
    private static let virtualTopInset: CGFloat = 6

    public static func layout(
        for placement: NotchShellPlacement,
        state: NotchStableState
    ) -> NotchPanelLayout {
        let display = placement.display
        let availableWidth = max(1, display.frame.width - horizontalMargin * 2)
        let availableHeight = max(1, display.frame.height - bottomMargin)
        let topInset = placement.mode == .virtualPill ? virtualTopInset : 0

        let requestedSize = requestedSurfaceSize(for: placement, state: state)
        let width = min(max(1, requestedSize.width), availableWidth)
        let height = min(max(1, requestedSize.height), max(1, availableHeight - topInset))
        let x = min(
            max(display.frame.midX - width / 2, display.frame.minX),
            display.frame.maxX - width
        )
        let y = display.frame.maxY - topInset - height
        let frame = CGRect(x: x, y: y, width: width, height: height)

        let bridgeSize: CGSize?
        if placement.mode == .physicalNotch {
            bridgeSize = CGSize(
                width: min(physicalBridgeWidth(for: display), width),
                height: min(max(display.safeAreaInsets.top, 1), height)
            )
        } else {
            bridgeSize = nil
        }

        return NotchPanelLayout(
            panelFrame: frame,
            surfaceSize: frame.size,
            topInset: topInset,
            physicalBridgeSize: bridgeSize,
            cornerRadius: cornerRadius(for: placement.mode, state: state)
        )
    }

    private static func requestedSurfaceSize(
        for placement: NotchShellPlacement,
        state: NotchStableState
    ) -> CGSize {
        switch state {
        case .collapsed:
            if placement.mode == .physicalNotch {
                let width = max(physicalBridgeWidth(for: placement.display) + 24, 240)
                let height = max(placement.display.safeAreaInsets.top + 10, 44)
                return CGSize(width: width, height: height)
            }
            return CGSize(width: 220, height: 44)
        case .hovered:
            let collapsed = requestedSurfaceSize(for: placement, state: .collapsed)
            return CGSize(width: max(collapsed.width, 272), height: max(collapsed.height, 56))
        case .expanded:
            return CGSize(width: 420, height: 260)
        }
    }

    private static func physicalBridgeWidth(for display: NotchiumDisplaySnapshot) -> CGFloat {
        if let notchGap = display.physicalNotchGap, notchGap.width > 0 {
            return notchGap.width
        }
        return min(max(display.frame.width * 0.15, 160), 200)
    }

    private static func cornerRadius(
        for mode: NotchSurfaceMode,
        state: NotchStableState
    ) -> CGFloat {
        switch (mode, state) {
        case (.physicalNotch, .collapsed):
            16
        case (.physicalNotch, .hovered):
            20
        case (.physicalNotch, .expanded):
            26
        case (.virtualPill, .collapsed):
            22
        case (.virtualPill, .hovered):
            24
        case (.virtualPill, .expanded):
            28
        }
    }
}
