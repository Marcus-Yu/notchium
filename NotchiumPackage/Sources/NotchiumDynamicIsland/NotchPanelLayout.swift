import Foundation

public struct NotchPanelLayout: Equatable, Sendable {
    public let panelFrame: CGRect
    public let visibleSurfaceFrame: CGRect
    public let collapsedVisibleFrame: CGRect
    public let collapsedHoverFrame: CGRect
    public let hardwareNotchGeometry: NotchHardwareGeometry?
    public let surfaceSize: CGSize
    public let expandedSize: CGSize
    public let hasHardwareNotch: Bool
    public let topCornerRadius: CGFloat
    public let bottomCornerRadius: CGFloat

    public init(
        panelFrame: CGRect,
        visibleSurfaceFrame: CGRect,
        collapsedVisibleFrame: CGRect,
        collapsedHoverFrame: CGRect,
        hardwareNotchGeometry: NotchHardwareGeometry?,
        surfaceSize: CGSize,
        expandedSize: CGSize,
        hasHardwareNotch: Bool,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat
    ) {
        self.panelFrame = panelFrame
        self.visibleSurfaceFrame = visibleSurfaceFrame
        self.collapsedVisibleFrame = collapsedVisibleFrame
        self.collapsedHoverFrame = collapsedHoverFrame
        self.hardwareNotchGeometry = hardwareNotchGeometry
        self.surfaceSize = surfaceSize
        self.expandedSize = expandedSize
        self.hasHardwareNotch = hasHardwareNotch
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }
}

public enum NotchGeometryResolver {
    public static let expandedNotchSize = CGSize(
        width: 450,
        height: 190
    )
    public static let panelSize = CGSize(
        width: 640,
        height: 210
    )
    public static let virtualNotchWidth: CGFloat = 180

    private static let hoverHorizontalSlop: CGFloat = 5
    private static let hoverBottomSlop: CGFloat = 5

    public static func layout(
        for placement: NotchShellPlacement,
        state: NotchStableState
    ) -> NotchPanelLayout {
        let hardwareGeometry = hardwareNotchGeometry(for: placement)
        let hasHardwareNotch = hardwareGeometry != nil
        let collapsedFrame = hardwareGeometry?.frame ?? virtualNotchFrame(for: placement.display)

        let panelFrame = CGRect(
            x: placement.display.frame.midX - panelSize.width / 2,
            y: placement.display.frame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )

        let surfaceSize = visibleSurfaceSize(
            state: state,
            collapsedSize: collapsedFrame.size,
            expandedSize: expandedNotchSize
        )
        let surfaceCenterX = state == .collapsed ? collapsedFrame.midX : panelFrame.midX
        let visibleSurfaceFrame = CGRect(
            x: surfaceCenterX - surfaceSize.width / 2,
            y: panelFrame.maxY - surfaceSize.height,
            width: surfaceSize.width,
            height: surfaceSize.height
        )

        return NotchPanelLayout(
            panelFrame: panelFrame,
            visibleSurfaceFrame: visibleSurfaceFrame,
            collapsedVisibleFrame: collapsedFrame,
            collapsedHoverFrame: collapsedHoverFrame(from: collapsedFrame),
            hardwareNotchGeometry: hardwareGeometry,
            surfaceSize: surfaceSize,
            expandedSize: expandedNotchSize,
            hasHardwareNotch: hasHardwareNotch,
            topCornerRadius: topCornerRadius(for: placement.mode, state: state),
            bottomCornerRadius: bottomCornerRadius(for: placement.mode, state: state)
        )
    }

    public static func hardwareNotchGeometry(
        for placement: NotchShellPlacement
    ) -> NotchHardwareGeometry? {
        guard placement.mode == .physicalNotch else { return nil }

        let display = placement.display
        let height = display.safeAreaInsets.top
        guard height > 0,
              let leftArea = display.auxiliaryTopLeftArea,
              let rightArea = display.auxiliaryTopRightArea else {
            return nil
        }

        let minX = leftArea.maxX
        let maxX = rightArea.minX
        guard maxX > minX else { return nil }

        return NotchHardwareGeometry(
            frame: CGRect(
                x: minX,
                y: display.frame.maxY - height,
                width: maxX - minX,
                height: height
            )
        )
    }

    public static func virtualNotchFrame(
        for display: NotchiumDisplaySnapshot
    ) -> CGRect {
        let geometryMenuBarHeight = display.frame.maxY - display.visibleFrame.maxY
        let menuBarHeight = max(geometryMenuBarHeight, display.statusBarThickness)

        return CGRect(
            x: display.frame.midX - virtualNotchWidth / 2,
            y: display.frame.maxY - menuBarHeight,
            width: virtualNotchWidth,
            height: menuBarHeight
        )
    }

    public static func collapsedHoverFrame(from collapsedFrame: CGRect) -> CGRect {
        CGRect(
            x: collapsedFrame.minX - hoverHorizontalSlop,
            y: collapsedFrame.minY - hoverBottomSlop,
            width: collapsedFrame.width + hoverHorizontalSlop * 2,
            height: collapsedFrame.height + hoverBottomSlop
        )
    }

    private static func visibleSurfaceSize(
        state: NotchStableState,
        collapsedSize: CGSize,
        expandedSize: CGSize
    ) -> CGSize {
        switch state {
        case .collapsed:
            collapsedSize
        case .hovered, .expanded:
            expandedSize
        }
    }

    private static func topCornerRadius(
        for mode: NotchSurfaceMode,
        state: NotchStableState
    ) -> CGFloat {
        switch (mode, state) {
        case (_, .collapsed): 0
        case (.physicalNotch, .hovered), (.physicalNotch, .expanded): 12
        case (.virtualPill, .hovered), (.virtualPill, .expanded): 0
        }
    }

    private static func bottomCornerRadius(
        for mode: NotchSurfaceMode,
        state: NotchStableState
    ) -> CGFloat {
        switch (mode, state) {
        case (.physicalNotch, .collapsed): 8
        case (.virtualPill, .collapsed): 12
        case (_, .hovered), (_, .expanded): 26
        }
    }
}

public enum NotchHoverRegion {
    public static func contains(_ point: CGPoint, in frame: CGRect) -> Bool {
        point.x >= frame.minX
            && point.x <= frame.maxX
            && point.y >= frame.minY
            && point.y <= frame.maxY
    }
}
