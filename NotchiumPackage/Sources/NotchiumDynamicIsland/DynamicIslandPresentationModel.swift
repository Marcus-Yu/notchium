import AppKit
import Combine
import NotchiumCore
import Observation
import SwiftUI

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

    public let activityCoordinator: ActivityCoordinator
    public let pageModel: NotchPageModel
    private var activityRevision = 0
    @ObservationIgnored private var activityObservation: AnyCancellable?

    /// The sole presentation decision; Stage 2 phase remains manual interaction state.
    public var presentationState: NotchPresentationState {
        _ = activityRevision
        if let activity = activityCoordinator.activeActivity {
            if activity.kind == .notification && activity.priority == 100 { return .activity }
            if visualState == .collapsed { return .activity }
        }
        return visualState == .collapsed ? .passive : .expanded
    }

    /// Activities reuse the existing open shell geometry without becoming pinned.
    public var surfaceState: NotchStableState {
        presentationState == .activity ? .hovered : visualState
    }

    public var visualState: NotchStableState {
        phase.visualState
    }

    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private var pendingHoverTask: Task<Void, Never>?
    @ObservationIgnored private var pendingCollapseTask: Task<Void, Never>?
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var hoverGeneration = 0
    @ObservationIgnored private var transitionGeneration = 0

    private let hoverEntryDelay: Duration = .milliseconds(120)
    private let hoverExitDelay: Duration = .milliseconds(200)
    @ObservationIgnored private var pointerIsInside = false

    public init(
        phase: NotchPresentationPhase = .collapsed,
        clock: any AppClock = ContinuousAppClock()
    ) {
        self.phase = phase
        self.clock = clock
        activityCoordinator = ActivityCoordinator(clock: clock)
        pageModel = NotchPageModel()
        activityObservation = activityCoordinator.$activeActivity.sink { [weak self] _ in
            self?.activityRevision &+= 1
        }
    }

    public func setHovered(_ isHovered: Bool) {
        guard pointerIsInside != isHovered else { return }
        pointerIsInside = isHovered
        if isHovered {
            scheduleHoverExpansion()
        } else {
            scheduleCollapse()
        }
    }

    public func toggleExpanded() {
        pendingHoverTask?.cancel()
        pendingCollapseTask?.cancel()
        setExpanded(visualState != .expanded)
    }

    public func collapse() {
        pendingHoverTask?.cancel()
        pendingCollapseTask?.cancel()
        setExpanded(false)
    }

    public func setExpanded(
        _ expanded: Bool,
        target: NotchStableState = .expanded
    ) {
        let animation = reduceMotion ? NotchMotion.reduced : NotchMotion.morph

        withAnimation(animation) {
            transition(to: expanded ? target : .collapsed)
        }
    }

    public func present(_ state: NotchStableState, animated: Bool = true) {
        pendingHoverTask?.cancel()
        pendingCollapseTask?.cancel()
        if animated {
            setExpanded(state != .collapsed, target: state)
        } else {
            transitionTask?.cancel()
            transitionGeneration &+= 1
            phase = Self.phase(for: state)
        }
    }

    public func reset() {
        activityCoordinator.clearAll()
        pendingHoverTask?.cancel()
        pendingCollapseTask?.cancel()
        transitionTask?.cancel()
        hoverGeneration &+= 1
        transitionGeneration &+= 1
        pointerIsInside = false
        phase = .collapsed
    }

    public func setReduceMotion(_ reduceMotion: Bool) {
        guard self.reduceMotion != reduceMotion else { return }
        self.reduceMotion = reduceMotion
    }

    private func scheduleHoverExpansion() {
        pendingCollapseTask?.cancel()
        pendingHoverTask?.cancel()

        guard visualState != .expanded else { return }

        hoverGeneration &+= 1
        let generation = hoverGeneration
        let delay = hoverEntryDelay

        pendingHoverTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.completeHoverExpansion(generation: generation)
        }
    }

    private func scheduleCollapse() {
        pendingHoverTask?.cancel()
        pendingCollapseTask?.cancel()

        guard visualState != .expanded else { return }
        hoverGeneration &+= 1
        let generation = hoverGeneration
        let delay = hoverExitDelay

        pendingCollapseTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.completeScheduledCollapse(generation: generation)
        }
    }

    private func completeHoverExpansion(generation: Int) {
        guard generation == hoverGeneration else { return }
        setExpanded(true, target: .hovered)
    }

    private func completeScheduledCollapse(generation: Int) {
        guard generation == hoverGeneration, visualState != .expanded else { return }
        setExpanded(false)
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
            return .milliseconds(180)
        }
        return .milliseconds(600)
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
