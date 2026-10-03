import SwiftUI

/// Content injection for the Focus Timer page; timer and history truth stay in the feature.
@MainActor public protocol NotchPomodoroRendering: AnyObject {
    var automaticOpenPageState: NotchPomodoroPageState { get }
    func expandedPomodoro() -> AnyView
    func completionBanner(title: String, openTimer: @escaping @MainActor () -> Void) -> AnyView
    func setPageVisible(_ visible: Bool)
}

public extension NotchPomodoroRendering {
    func completionBanner(title: String, openTimer: @escaping @MainActor () -> Void) -> AnyView {
        AnyView(Button(title, action: openTimer).buttonStyle(.plain))
    }
}

/// Content injection for Clipboard history, shown as the Shelf page's second section.
@MainActor public protocol NotchClipboardRendering: AnyObject {
    func expandedClipboard() -> AnyView
    func setVisible(_ visible: Bool)
}

/// The header Camera utility. The feature owns capture; the shell only reveals the preview.
@MainActor public protocol NotchCameraControlling: AnyObject {
    var isPreviewPresented: Bool { get }
    func togglePreview()
    /// Stops capture immediately; called whenever the preview leaves the screen.
    func closePreview()
    func preview() -> AnyView
}

/// The Shelf page holds files and, beside them, recent clipboard items.
public enum NotchShelfSection: String, CaseIterable, Identifiable, Sendable {
    case files, clipboard
    public var id: String { rawValue }
    public var title: String { self == .files ? "Shelf" : "Clipboard" }
}

extension EnvironmentValues {
    @Entry public var notchPomodoroPageVisible = false
    /// Present only when Clipboard is available; Shelf then shows the section switch in its title.
    @Entry public var notchShelfSection: Binding<NotchShelfSection>? = nil
}

/// The Shelf page title doubles as a two-item switch: text only, selection by weight and contrast.
public struct NotchShelfSectionSwitch: View {
    @Binding var selection: NotchShelfSection
    public init(selection: Binding<NotchShelfSection>) { _selection = selection }

    public var body: some View {
        HStack(spacing: 12) {
            ForEach(NotchShelfSection.allCases) { section in
                Button { selection = section } label: {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(selection == section ? 1 : 0.42))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
                .accessibilityIdentifier("notchium.shelf.section.\(section.rawValue)")
            }
        }
        .animation(.smooth(duration: 0.16), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shelf sections")
    }
}
