import NotchiumCore
import Observation

public enum NotchStableState: String, CaseIterable, Equatable, Sendable {
    case collapsed
    case hovered
    case expanded
}

public enum NotchPresentationPhase: Equatable, Sendable {
    case collapsed
    case hovered
    case expanded
    case transitioning(from: NotchStableState, to: NotchStableState)

    public var visualState: NotchStableState {
        switch self {
        case .collapsed:
            .collapsed
        case .hovered:
            .hovered
        case .expanded:
            .expanded
        case let .transitioning(_, target):
            target
        }
    }

    public var accessibilityValue: String {
        switch self {
        case .collapsed:
            "collapsed"
        case .hovered:
            "hovered"
        case .expanded:
            "expanded"
        case let .transitioning(_, target):
            "transitioning to \(target.rawValue)"
        }
    }
}

@MainActor
@Observable
public final class DynamicIslandPresentationModel {
    public private(set) var phase: NotchPresentationPhase
    public private(set) var reduceMotion = false

    public var visualState: NotchStableState {
        phase.visualState
    }

    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var hoverGeneration = 0
    @ObservationIgnored private var transitionGeneration = 0

    private let hoverEntryDelay: Duration = .milliseconds(80)
    private let hoverExitDelay: Duration = .milliseconds(180)

    public init(
        phase: NotchPresentationPhase = .collapsed,
        clock: any AppClock = ContinuousAppClock()
    ) {
        self.phase = phase
        self.clock = clock
    }

    public func setHovered(_ isHovered: Bool) {
        guard visualState != .expanded else { return }
        scheduleHoverTransition(
            to: isHovered ? .hovered : .collapsed,
            after: isHovered ? hoverEntryDelay : hoverExitDelay
        )
    }

    public func toggleExpanded() {
        hoverTask?.cancel()
        transition(to: visualState == .expanded ? .collapsed : .expanded)
    }

    public func collapse() {
        hoverTask?.cancel()
        transition(to: .collapsed)
    }

    public func present(_ state: NotchStableState, animated: Bool = true) {
        hoverTask?.cancel()
        if animated {
            transition(to: state)
        } else {
            transitionTask?.cancel()
            transitionGeneration &+= 1
            phase = Self.phase(for: state)
        }
    }

    public func reset() {
        hoverTask?.cancel()
        transitionTask?.cancel()
        hoverGeneration &+= 1
        transitionGeneration &+= 1
        phase = .collapsed
    }

    public func setReduceMotion(_ reduceMotion: Bool) {
        guard self.reduceMotion != reduceMotion else { return }
        self.reduceMotion = reduceMotion
    }

    private func scheduleHoverTransition(to target: NotchStableState, after delay: Duration) {
        hoverTask?.cancel()
        hoverGeneration &+= 1
        let generation = hoverGeneration

        hoverTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.completeHoverTransition(to: target, generation: generation)
        }
    }

    private func completeHoverTransition(to target: NotchStableState, generation: Int) {
        guard generation == hoverGeneration, visualState != .expanded else { return }
        transition(to: target)
    }

    private func transition(to target: NotchStableState) {
        let source = visualState
        guard source != target || phase != Self.phase(for: target) else { return }

        transitionTask?.cancel()
        transitionGeneration &+= 1
        let generation = transitionGeneration
        phase = .transitioning(from: source, to: target)

        let duration = transitionDuration(from: source, to: target)
        transitionTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: duration)
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.completeTransition(to: target, generation: generation)
        }
    }

    private func completeTransition(to target: NotchStableState, generation: Int) {
        guard generation == transitionGeneration, visualState == target else { return }
        phase = Self.phase(for: target)
    }

    private func transitionDuration(
        from source: NotchStableState,
        to target: NotchStableState
    ) -> Duration {
        if reduceMotion {
            return .milliseconds(120)
        }
        return .milliseconds(620)
    }

    private static func phase(for state: NotchStableState) -> NotchPresentationPhase {
        switch state {
        case .collapsed:
            .collapsed
        case .hovered:
            .hovered
        case .expanded:
            .expanded
        }
    }
}
