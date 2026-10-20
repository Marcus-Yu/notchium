import Foundation
import Observation
import NotchiumCore
import NotchiumPersistence
import NotchiumServices

@MainActor @Observable public final class OnboardingModel {
    public private(set) var state = OnboardingState()
    public private(set) var statuses: [SetupPermission: SetupPermissionStatus] = [:]
    public private(set) var isBusy = false
    public private(set) var error: String?
    @ObservationIgnored private let store: any OnboardingStoring
    @ObservationIgnored private let permissions: any OnboardingPermissionProviding
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var canWrite = true

    public init(store: any OnboardingStoring, permissions: any OnboardingPermissionProviding) {
        self.store = store
        self.permissions = permissions
        do {
            if let saved = try store.load() {
                state = saved
                if saved.schemaVersion > 1 {
                    canWrite = false
                    error = "Setup was saved by a newer Notchium version. Update Notchium to change it."
                }
            } else if store.hasLegacyConfiguration() {
                var migrated = OnboardingState()
                migrated.completion = .legacyRecognized
                try store.save(migrated)
                state = migrated
            } else {
                // Write before feature constructors can seed preferences or storage.
                try store.save(state)
            }
        } catch {
            canWrite = false
            self.error = "Your setup record could not be read or saved. Existing data is preserved. Quit and check that Application Support is accessible, then reopen Notchium."
        }
    }

    public var requiresOnboarding: Bool { state.requiresOnboarding }
    public var current: SetupPermission { state.currentPermission }
    public var canFinish: Bool {
        canWrite && !isBusy && SetupPermission.allCases.allSatisfy(isSatisfied)
    }
    public func isSatisfied(_ permission: SetupPermission) -> Bool {
        guard let status = statuses[permission] else { return false }
        if permission == .clipboard { return state.clipboardChoice != nil }
        if permission == .spotify, state.reviewed.contains(.spotify) { return true }
        if status.authorization == .granted || status.authorization == .selectionSaved { return true }
        if permission == .clipboardAccess, state.clipboardChoice == false {
            return state.reviewed.contains(.clipboardAccess)
        }
        return status.authorization.acceptsAcknowledgment && state.reviewed.contains(permission)
    }

    public func canAcknowledge(_ permission: SetupPermission) -> Bool {
        guard let status = statuses[permission] else { return false }
        return status.authorization.acceptsAcknowledgment
            || (permission == .clipboardAccess && state.clipboardChoice == false && status.authorization != .granted)
    }

    public func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await readStatuses()
    }

    /// Own refreshes initiated by synchronous controls and activation notifications.
    public func refreshStatus() {
        guard !isBusy, operation == nil else { return }
        isBusy = true
        operation = Task { [weak self] in
            guard let self else { return }
            await self.readStatuses()
            guard !Task.isCancelled else { return }
            self.isBusy = false
            self.operation = nil
        }
    }

    private func readStatuses() async {
        var latest: [SetupPermission: SetupPermissionStatus] = [:]
        for permission in SetupPermission.allCases {
            guard !Task.isCancelled else { return }
            latest[permission] = await permissions.status(for: permission)
        }
        guard !Task.isCancelled else { return }
        statuses = latest
    }

    public func go(to step: OnboardingState.Step) { commit { $0.step = step } }
    public func select(_ permission: SetupPermission) {
        commit { $0.currentPermission = permission; $0.step = .permissions }
    }
    public func acknowledgeCurrent() {
        guard canAcknowledge(current) else { return }
        commit { $0.reviewed.insert($0.currentPermission) }
    }
    /// This is a reviewed integration exception, never an OS grant or playback opt-in.
    public func continueWithoutSpotify() {
        guard statuses[.spotify]?.authorization != .granted else { return }
        commit { $0.reviewed.insert(.spotify) }
    }

    public func chooseClipboard(_ enabled: Bool) {
        if commit({ $0.clipboardChoice = enabled; $0.reviewed.insert(.clipboard) }) {
            permissions.setClipboardConsent(enabled)
        }
    }
    public func next() {
        // An unresolved row may be revisited from review, but never bypasses completion.
        guard let index = SetupPermission.allCases.firstIndex(of: current) else { return }
        if index + 1 < SetupPermission.allCases.count { select(SetupPermission.allCases[index + 1]) }
        else { go(to: .review) }
    }

    public func request(_ permission: SetupPermission) {
        guard !isBusy, operation == nil else { return }
        // Persist the step before any system dialog; quitting while it is open resumes here.
        if requiresOnboarding {
            guard commit({ $0.currentPermission = permission; $0.step = .permissions }) else { return }
        }
        isBusy = true
        error = nil
        operation = Task { [weak self, permissions] in
            do { try await permissions.request(permission) }
            catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                self?.error = (error as? SpotifySetupRequestFailure)?.message
                    ?? "macOS could not complete this request. Review the status and try again or open System Settings."
            }
            guard !Task.isCancelled, let self else { return }
            await self.readStatuses()
            guard !Task.isCancelled else { return }
            self.isBusy = false
            self.operation = nil
        }
    }

    /// Re-read OS truth immediately before the one authoritative completion write.
    public func finish() {
        guard !isBusy, operation == nil, requiresOnboarding else { return }
        isBusy = true
        operation = Task { [weak self] in
            guard let self else { return }
            await self.readStatuses()
            guard !Task.isCancelled else { return }
            self.isBusy = false
            self.operation = nil
            guard !Task.isCancelled, self.canFinish else {
                self.error = "Some requirements still need attention. Grant available permissions or explicitly review the listed exceptions before finishing."
                return
            }
            self.commit { $0.completion = .userCompleted; $0.step = .ready }
        }
    }

    public func openSettings(for permission: SetupPermission) { permissions.openSettings(for: permission) }
    public func stop() {
        operation?.cancel()
        operation = nil
        isBusy = false
    }
    isolated deinit { operation?.cancel() }

    @discardableResult private func commit(_ update: (inout OnboardingState) -> Void) -> Bool {
        guard canWrite, !isBusy else { return false }
        var next = state
        update(&next)
        do {
            try store.save(next)
            state = next
            error = nil
            return true
        } catch {
            self.error = "Setup progress could not be saved. Check available disk space and Application Support access, then try again."
            return false
        }
    }
}
