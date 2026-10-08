import NotchiumDesignSystem
import AppKit
import SwiftUI

/// One set of metrics for page toolbars (Shelf, Clipboard): row, controls and search field share
/// a height, so neither page's top row can drift from the other.
public enum NotchToolbarMetrics {
    /// Row height and the comfortable macOS-sized hit target of every toolbar control.
    public static let control: CGFloat = 32
    /// Row-level (inline) actions inside lists.
    public static let compactControl: CGFloat = 26
    public static let controlGap: CGFloat = 8
    /// Space between the toolbar row and the page content.
    public static let sectionGap: CGFloat = 10
    public static let symbolSize: CGFloat = 14
    public static let compactSymbolSize: CGFloat = 12
    /// Resting, hover and pressed fills shared by buttons and the search field.
    public static let restingFill = 0.13
    public static let hoverFill = 0.22
    public static let pressedFill = 0.32
}

/// Toolbar glyph: clearly visible at rest, brighter on hover; the style adds the pressed state.
public struct NotchToolbarLabel: View {
    let symbol: String
    var image: NSImage?
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    public init(symbol: String, image: NSImage? = nil, compact: Bool = false) {
        self.symbol = symbol
        self.image = image
        self.compact = compact
    }

    public var body: some View {
        let size = compact ? NotchToolbarMetrics.compactControl : NotchToolbarMetrics.control
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(width: compact ? 14 : 17, height: compact ? 14 : 17)
                    .saturation(isEnabled ? 1 : 0)
            } else {
                Image(systemName: symbol).font(.system(size: compact ? NotchToolbarMetrics.compactSymbolSize
                                                       : NotchToolbarMetrics.symbolSize, weight: .semibold))
            }
        }
        .foregroundStyle(.white.opacity(isEnabled ? 0.95 : 0.3))
        .opacity(isEnabled ? 1 : 0.55)
        .frame(width: size, height: size)
        .contentShape(.circle)
    }
}

/// Resting fill that reads on black, a distinct hover, and a pressed state you can feel.
public struct NotchToolbarButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @NotchReducedMotion private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let fill = !isEnabled ? 0.05 : (configuration.isPressed ? NotchToolbarMetrics.pressedFill
            : (isHovered ? NotchToolbarMetrics.hoverFill : NotchToolbarMetrics.restingFill))
        configuration.label
            .background(.white.opacity(fill), in: .circle)
            .overlay { Circle().strokeBorder(.white.opacity(isEnabled && isHovered ? 0.18 : 0), lineWidth: 0.5) }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .onHover { isHovered = $0 && isEnabled }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// A circular toolbar action with tooltip and spoken label.
public struct NotchToolbarButton: View {
    let symbol: String
    let label: String
    var image: NSImage?
    var compact = false
    let action: () -> Void

    public init(symbol: String, label: String, image: NSImage? = nil, compact: Bool = false,
                action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.image = image
        self.compact = compact
        self.action = action
    }

    public var body: some View {
        Button(action: action) { NotchToolbarLabel(symbol: symbol, image: image, compact: compact) }
            .buttonStyle(NotchToolbarButtonStyle())
            .help(label)
            .accessibilityLabel(label)
    }
}

/// A search capsule at exactly the toolbar control height: it can never make its row taller.
public struct NotchToolbarSearchField: View {
    @Binding var text: String
    let prompt: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @State private var isHovered = false

    public init(text: Binding<String>, prompt: String, onSubmit: @escaping () -> Void = {}) {
        _text = text
        self.prompt = prompt
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: NotchToolbarMetrics.compactSymbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(.circle)
                }
                .buttonStyle(NotchToolbarClearButtonStyle())
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: NotchToolbarMetrics.control)
        .background(.white.opacity(focused || isHovered ? NotchToolbarMetrics.hoverFill : NotchToolbarMetrics.restingFill),
                    in: .capsule)
        .overlay { Capsule().strokeBorder(.white.opacity(focused ? 0.22 : 0), lineWidth: 0.5) }
        .contentShape(.capsule)
        .onTapGesture { focused = true }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: focused)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(prompt)
    }
}

private struct NotchToolbarClearButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(isEnabled && isHovered ? 0.08 : 0), in: .circle)
            .opacity(isEnabled && configuration.isPressed ? 0.65 : 1)
            .onHover { isHovered = $0 && isEnabled }
    }
}
