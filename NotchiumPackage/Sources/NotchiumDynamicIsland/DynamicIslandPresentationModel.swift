import NotchiumCore
import Observation

public enum DynamicIslandInteraction: String, Equatable, Sendable {
    case collapsed
    case hovered
    case opened
}

@MainActor
@Observable
public final class DynamicIslandPresentationModel {
    public private(set) var interaction: DynamicIslandInteraction

    public init(interaction: DynamicIslandInteraction = .collapsed) {
        self.interaction = interaction
    }

    public func setHovered(_ isHovered: Bool) {
        guard interaction != .opened else { return }
        interaction = isHovered ? .hovered : .collapsed
    }

    public func toggleOpened() {
        interaction = interaction == .opened ? .collapsed : .opened
    }

    public func collapse() {
        interaction = .collapsed
    }
}
