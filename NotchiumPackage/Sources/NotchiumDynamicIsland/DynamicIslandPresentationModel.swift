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
    public private(set) var isAuxiliaryInteractionPresented = false

    public let activityCoordinator: ActivityCoordinator
    public let pageModel: NotchPageModel
    public var mediaRenderer: (any NotchMediaRendering)?
    public var calendarRenderer: (any NotchCalendarRendering)?
    public var audioRenderer: (any NotchAudioRendering)?
    public var caffeineController: (any NotchCaffeineControlling)?
    public var keyboardLockController: (any NotchKeyboardLockControlling)?
    public var audioHUD: NotchAudioHUD? {
        guard case let .audio(hud) = activityCoordinator.activeTransient?.payload else { return nil }
        return hud
    }
    // Measured at the banner's fixed target width; shared with AppKit hit testing.
    var calendarReminderHeight: CGFloat = NotchReminderGeometry.minimumHeight

    public var showsCalendarReminder: Bool {
        _ = activityRevision
        return calendarRenderer?.reminderVisible == true
            && activityCoordinator.activeTransient?.kind == .calendar
            && [.downwardBanner, .combined].contains(activityCoordinator.presentationMode)
            && visualState == .collapsed
    }

    public var showsCollapsedMedia: Bool {
        _ = activityRevision
        return mediaRenderer?.collapsedMediaVisible == true
            && [.mediaSides, .combined].contains(activityCoordinator.presentationMode)
            && visualState == .collapsed
    }

    /// The collapsed artwork follows the media surface, not the expanded page selection.
    public var showsSharedMediaArtwork: Bool {
        if surfaceState == .collapsed { return showsCollapsedMedia }
        return pageModel.selectedPage == .music
    }
    private var activityRevision = 0
    @ObservationIgnored private var activityObservation: AnyCancellable?

    /// The sole presentation decision; Stage 2 phase remains manual interaction state.
    public var presentationState: NotchPresentationState {
        _ = activityRevision
        if activityCoordinator.presentationMode != .none, visualState == .collapsed { return .activity }
        return visualState == .collapsed ? .passive : .expanded
    }

    /// Activities reuse the existing open shell geometry without becoming pinned.
    public var surfaceState: NotchStableState {
        (activityCoordinator.presentationMode != .none && visualState == .collapsed)
            ? .collapsed : (presentationState == .activity ? .hovered : visualState)
    }

    public var visualState: NotchStableState {
        phase.visualState
    }

    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private var pendingHoverTask: Task<Void, Never>?
    @ObservationIgnored private var pendingCollapseTask: Task<Void, Never>?
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private let audioActivityID = UUID()
    @ObservationIgnored private var hoverGeneration = 0
    @ObservationIgnored private var transitionGeneration = 0
    @ObservationIgnored lazy var auxiliaryInteractionHandler = NotchAuxiliaryInteractionHandler(model: self)
    @ObservationIgnored private var auxiliaryInteractionObservedClick = false
    @ObservationIgnored private var suppressNextAuxiliaryActionClick = false

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
        activityObservation = activityCoordinator.$activeTransient
            .combineLatest(activityCoordinator.$persistentActivity)
            .sink { [weak self] activity, _ in
            guard let self else { return }
            self.activityRevision &+= 1
            // A collapsed activity opens on its own page. Expanded navigation remains user-owned.
            if self.visualState == .collapsed {
                self.selectPage(for: activity)
            }
            }
    }

    public func setHovered(_ isHovered: Bool) {
        guard pointerIsInside != isHovered else { return }
        pointerIsInside = isHovered
        guard !isAuxiliaryInteractionPresented else {
            if isHovered { pendingCollapseTask?.cancel() }
            return
        }
        if isHovered {
            scheduleHoverExpansion()
        } else {
            scheduleCollapse()
        }
    }

    public func setAuxiliaryInteractionPresented(_ presented: Bool) {
        if presented {
            guard !isAuxiliaryInteractionPresented else { return }
            isAuxiliaryInteractionPresented = true
            auxiliaryInteractionObservedClick = false
            suppressNextAuxiliaryActionClick = false
            pendingCollapseTask?.cancel()
            hoverGeneration &+= 1
        } else {
            endAuxiliaryInteraction(actionSelected: false)
        }
    }

    func endAuxiliaryInteraction(actionSelected: Bool) {
        guard isAuxiliaryInteractionPresented else { return }
        isAuxiliaryInteractionPresented = false
        suppressNextAuxiliaryActionClick = actionSelected && !auxiliaryInteractionObservedClick
        auxiliaryInteractionObservedClick = false
        if !pointerIsInside {
            scheduleCollapse()
        }
    }

    func consumePointerClickForAuxiliaryInteraction() -> Bool {
        if isAuxiliaryInteractionPresented {
            auxiliaryInteractionObservedClick = true
            return true
        }
        if suppressNextAuxiliaryActionClick {
            suppressNextAuxiliaryActionClick = false
            return true
        }
        return false
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
        if expanded && visualState == .collapsed {
            selectPage(for: activityCoordinator.activeActivity)
        }
        let animation = reduceMotion ? NotchMotion.reduced : NotchMotion.morph(opening: expanded)

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
        isAuxiliaryInteractionPresented = false
        auxiliaryInteractionObservedClick = false
        suppressNextAuxiliaryActionClick = false
        phase = .collapsed
    }

    public func setReduceMotion(_ reduceMotion: Bool) {
        guard self.reduceMotion != reduceMotion else { return }
        self.reduceMotion = reduceMotion
    }

    /// Repeated events coalesce into the coordinator's single Audio slot and reset its deadline.
    public func showAudioHUD(_ hud: NotchAudioHUD) {
        let kind: NotchActivityKind = hud.kind == .outputChanged ? .audioDevice : .systemHUD
        activityCoordinator.present(.init(
            id: audioActivityID,
            kind: kind,
            title: hud.deviceName,
            subtitle: hud.kind == .outputChanged ? "Output changed" : "Volume",
            priority: hud.kind == .outputChanged ? .medium : .low,
            presentationStyle: .compactHUD,
            lifetime: .transient,
            destination: .audio,
            duration: .milliseconds(1250),
            payload: .audio(hud)
        ))
    }

    public func activateCurrentActivity() {
        guard let activity = activityCoordinator.activeTransient else { return }
        activityCoordinator.dismiss(id: activity.id)
        if let destination = activity.destination {
            selectPage(destination)
        }
        setExpanded(true)
    }

    private func selectPage(for activity: NotchActivity?) {
        guard let destination = activity?.destination else { return }
        selectPage(destination)
    }

    private func selectPage(_ destination: NotchActivityDestination) {
        switch destination {
        case .music: pageModel.selectedPage = .music
        case .calendar: pageModel.selectedPage = .calendar
        case .audio: pageModel.selectedPage = .audio
        }
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
        guard generation == hoverGeneration,
              !isAuxiliaryInteractionPresented,
              visualState != .expanded else { return }
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
            return .milliseconds(120)
        }
        return NotchMotion.duration(opening: target != .collapsed)
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
