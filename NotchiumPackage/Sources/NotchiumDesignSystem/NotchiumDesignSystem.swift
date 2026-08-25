import SwiftUI

public enum NotchiumDesignMetrics {
    public static let compactCornerRadius: CGFloat = 14
    public static let standardSpacing: CGFloat = 12
    public static let minimumHitTarget: CGFloat = 44
}

public struct NotchiumSurfaceModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let shape: S

    public init(shape: S) {
        self.shape = shape
    }

    public func body(content: Content) -> some View {
        content
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color.black)
                    : AnyShapeStyle(.regularMaterial),
                in: shape
            )
            .environment(\.colorScheme, .dark)
    }
}

public extension View {
    func notchSurface<S: InsettableShape>(in shape: S) -> some View {
        modifier(NotchiumSurfaceModifier(shape: shape))
    }
}
