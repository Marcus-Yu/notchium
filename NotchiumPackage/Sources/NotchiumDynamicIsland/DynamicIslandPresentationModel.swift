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
    private var auxiliarySources: Set<String> = []

    public let activityCoordinator: ActivityCoordinator
    public var notificationCoordinator: NotificationCoordinator { activityCoordinator.notifications }
    /// Full notch content takes precedence; model lifetime is independent of visibility.
    public var presentedNotification: NotchNotification? {
        // A file drag near the notch is direct interaction: its drop affordance wins.
        surfaceState == .collapsed && fileDrag == .idle ? notificationCoordinator.active : nil
    }
    /// The coordinator pairs only baseline activities (a transient primary never has one), so the
    /// chip sits beside a baseline compact activity (a transfer) or Music's live flanks. Never
    /// beside a banner, and never while expanded.
    public var presentedSecondary: NotchActivity? {
        _ = activityRevision
        guard surfaceState == .collapsed, fileDrag == .idle,
              let secondary = activityCoordinator.secondary else { return nil }
        if let notification = presentedNotification {
            return notification.presentationStyle == .feedback ? nil : secondary
        }
        return showsCollapsedMedia ? secondary : nil
    }

    /// System file drags near the collapsed notch (set by the panel controller).
    public private(set) var fileDrag: NotchFileDragState = .idle
    public var showsFileDropTarget: Bool { fileDrag != .idle && visualState == .collapsed }
    public let pageModel: NotchPageModel
    public var mediaRenderer: (any NotchMediaRendering)?
    public var calendarRenderer: (any NotchCalendarRendering)?
    public var audioRenderer: (any NotchAudioRendering)?
    public var caffeineController: (any NotchCaffeineControlling)?
    public var quickActionsRenderer: (any NotchQuickActionsRendering)?
    public var shelfRenderer: (any NotchShelfRendering)?
    public var audioHUD: NotchAudioHUD? {
        guard case let .audio(hud) = activityCoordinator.activeTransient?.payload else { return nil }
        return hud
    }
    // A stable Calendar height prevents title changes from resizing the shell.
    var calendarReminderHeight: CGFloat { NotchReminderGeometry.minimumHeight }

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
        if phase.visualState != .collapsed { pageModel.beginExpansion(default: .home) }
        activityObservation = activityCoordinator.$activeTransient
            .combineLatest(activityCoordinator.$persistentActivity, activityCoordinator.$secondary)
            .sink { [weak self] _, _, _ in
                self?.activityRevision &+= 1
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

    public func setAuxiliaryInteractionPresented(_ presented: Bool, source: String = "feature") {
        if presented {
            auxiliarySources.insert(source)
            guard !isAuxiliaryInteractionPresented else { return }
            isAuxiliaryInteractionPresented = true
            auxiliaryInteractionObservedClick = false
            suppressNextAuxiliaryActionClick = false
            pendingCollapseTask?.cancel()
            pendingHoverTask?.cancel()
            hoverGeneration &+= 1
        } else {
            endAuxiliaryInteraction(actionSelected: false, source: source)
        }
    }

    func endAuxiliaryInteraction(actionSelected: Bool, source: String = "feature") {
        auxiliarySources.remove(source)
        guard auxiliarySources.isEmpty else { return }
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

    /// Child menus/popovers receive Escape first through the native responder chain.
    public func handleEscape() {
        guard !isAuxiliaryInteractionPresented else { return }
        if surfaceState == .collapsed, notificationCoordinator.active?.dismissible == true {
            notificationCoordinator.dismissByUser()
        } else {
            collapse()
        }
    }

    public func setExpanded(
        _ expanded: Bool,
        target: NotchStableState = .expanded
    ) {
        if expanded {
            pageModel.beginExpansion(default: activityCoordinator.preferredExpandedPage)
        }
        transition(to: expanded ? target : .collapsed)
    }

    public func present(_ state: NotchStableState, animated: Bool = true) {
        pendingHoverTask?.cancel()
        pendingCollapseTask?.cancel()
        if animated {
            setExpanded(state != .collapsed, target: state)
        } else {
            transitionTask?.cancel()
            transitionGeneration &+= 1
            if state == .collapsed { pageModel.endExpansion() }
            else { pageModel.beginExpansion(default: activityCoordinator.preferredExpandedPage) }
            phase = Self.phase(for: state)
        }
    }

    public func reset() {
        activityCoordinator.clearAll()
        fileDrag = .idle
        pendingHoverTask?.cancel()
        pendingCollapseTask?.cancel()
        transitionTask?.cancel()
        hoverGeneration &+= 1
        transitionGeneration &+= 1
        pointerIsInside = false
        isAuxiliaryInteractionPresented = false
        auxiliarySources.removeAll()
        auxiliaryInteractionObservedClick = false
        suppressNextAuxiliaryActionClick = false
        pageModel.endExpansion()
        phase = .collapsed
    }

    public func setReduceMotion(_ reduceMotion: Bool) {
        guard self.reduceMotion != reduceMotion else { return }
        self.reduceMotion = reduceMotion
    }

    /// Repeated events coalesce into the coordinator's single Audio slot and reset its deadline.
    public func showAudioHUD(_ hud: NotchAudioHUD) {
        notificationCoordinator.present(.audio(hud))
    }

    /// An explicit click: opens the activity's destination. A transient is consumed; a
    /// persistent activity (an active transfer) keeps running.
    public func activateCurrentActivity() {
        guard let activity = activityCoordinator.activeTransient
                ?? activityCoordinator.primary.flatMap({ notificationCoordinator.active?.id == $0.id ? $0 : nil })
        else { return }
        if !activity.lifetime.isBaseline { activityCoordinator.dismiss(id: activity.id) }
        setExpanded(true)
        if let destination = activity.destination {
            selectPage(destination)
        }
    }

    // MARK: File drag and drop

    /// Proximity of a system file drag, from the panel controller's pointer tracking.
    public func setFileDragNearby(_ nearby: Bool) {
        let next: NotchFileDragState = nearby ? (fileDrag == .targeted ? .targeted : .nearby) : .idle
        guard fileDrag != next, visualState == .collapsed || next == .idle else { return }
        fileDrag = next
    }

    /// The drop affordance's own hover state (SwiftUI drop targeting).
    public func setFileDropTargeted(_ targeted: Bool) {
        guard fileDrag != .idle else { return }
        fileDrag = targeted ? .targeted : .nearby
    }

    /// Returns whether anything was accepted. Files are referenced, never copied.
    @discardableResult
    public func acceptDroppedFiles(_ urls: [URL]) -> Bool {
        let accepted = shelfRenderer?.acceptDroppedFiles(urls.filter(\.isFileURL)) ?? 0
        fileDrag = .idle
        return accepted > 0
    }

    public func endFileDrag() {
        fileDrag = .idle
    }

    /// Promotes the secondary chip in place. Presentation role only: no page or provider change.
    public func activateSecondaryActivity() {
        activityCoordinator.promoteSecondary()
    }

    private func selectPage(_ destination: NotchActivityDestination) {
        switch destination {
        case .music: pageModel.selectedPage = .music
        case .calendar: pageModel.selectedPage = .calendar
        case .audio: pageModel.selectedPage = .audio
        case .shelf: pageModel.selectedPage = .shelf
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
        if target == .collapsed { pageModel.endExpansion() }
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
