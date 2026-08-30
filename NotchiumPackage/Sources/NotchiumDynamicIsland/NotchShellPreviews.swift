#if DEBUG
import NotchiumCore
import SwiftUI

private struct NotchShellPreviewFixture: View {
    let placement: NotchShellPlacement
    let state: NotchStableState
    var configuration = NotchShellRenderConfiguration.automatic

    var body: some View {
        let model = DynamicIslandPresentationModel(
            phase: phase,
            clock: TestAppClock(now: Date(timeIntervalSince1970: 0))
        )
        let layout = NotchGeometryResolver.layout(for: placement, state: state)

        NotchiumShellView(
            model: model,
            layout: layout,
            renderConfiguration: configuration
        )
        .frame(width: layout.surfaceSize.width, height: layout.surfaceSize.height)
        .padding(32)
    }

    private var phase: NotchPresentationPhase {
        switch state {
        case .collapsed: .collapsed
        case .hovered: .hovered
        case .expanded: .expanded
        }
    }
}

@MainActor
private let previewPhysicalPlacement = NotchShellPlacement(
    display: NotchShellDebugModel.builtInFixture,
    mode: .physicalNotch
)

@MainActor
private let previewVirtualPlacement = NotchShellPlacement(
    display: NotchShellDebugModel.externalFixture,
    mode: .virtualPill
)

#Preview("Physical — Collapsed") {
    NotchShellPreviewFixture(placement: previewPhysicalPlacement, state: .collapsed)
}

#Preview("Physical — Hovered") {
    NotchShellPreviewFixture(placement: previewPhysicalPlacement, state: .hovered)
}

#Preview("Physical — Expanded") {
    NotchShellPreviewFixture(placement: previewPhysicalPlacement, state: .expanded)
}

#Preview("Virtual — Collapsed") {
    NotchShellPreviewFixture(placement: previewVirtualPlacement, state: .collapsed)
}

#Preview("Virtual — Hovered") {
    NotchShellPreviewFixture(placement: previewVirtualPlacement, state: .hovered)
}

#Preview("Virtual — Expanded") {
    NotchShellPreviewFixture(placement: previewVirtualPlacement, state: .expanded)
}

#Preview("Light") {
    NotchShellPreviewFixture(
        placement: previewVirtualPlacement,
        state: .expanded,
        configuration: NotchShellRenderConfiguration(appearance: .light)
    )
}

#Preview("Dark") {
    NotchShellPreviewFixture(
        placement: previewVirtualPlacement,
        state: .expanded,
        configuration: NotchShellRenderConfiguration(appearance: .dark)
    )
}

#Preview("Reduce Motion") {
    NotchShellPreviewFixture(
        placement: previewVirtualPlacement,
        state: .hovered,
        configuration: NotchShellRenderConfiguration(reduceMotion: .on)
    )
}

#Preview("Reduce Transparency") {
    NotchShellPreviewFixture(
        placement: previewVirtualPlacement,
        state: .expanded,
        configuration: NotchShellRenderConfiguration(reduceTransparency: .on)
    )
}

#Preview("Long Content") {
    NotchShellPreviewFixture(placement: previewVirtualPlacement, state: .collapsed)
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}

#Preview("Small Display") {
    let display = NotchiumDisplaySnapshot(
        id: NotchiumDisplayID(rawValue: 3),
        name: "Small",
        frame: CGRect(x: 0, y: 0, width: 360, height: 240),
        isBuiltIn: false,
        isPrimary: true
    )
    NotchShellPreviewFixture(
        placement: NotchShellPlacement(display: display, mode: .virtualPill),
        state: .expanded
    )
}

#Preview("Large Display") {
    let display = NotchiumDisplaySnapshot(
        id: NotchiumDisplayID(rawValue: 4),
        name: "Large",
        frame: CGRect(x: 0, y: 0, width: 3456, height: 2234),
        isBuiltIn: false,
        isPrimary: true
    )
    NotchShellPreviewFixture(
        placement: NotchShellPlacement(display: display, mode: .virtualPill),
        state: .expanded
    )
}
#endif
