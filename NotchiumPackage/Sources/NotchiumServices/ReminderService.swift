import AppKit
import Combine
import EventKit
import Foundation
import OSLog
import NotchiumCore

public enum ReminderFailure: LocalizedError, Equatable {
    case permission, noWritableList, emptyTitle
    public var errorDescription: String? {
        switch self {
        case .permission: "Allow Notchium to access Reminders in System Settings → Privacy & Security → Reminders."
        case .noWritableList: "Create a writable list in Reminders, then try again."
        case .emptyTitle: "Enter a reminder."
        }
    }
}

@MainActor public protocol ReminderService: Sendable {
    var changes: AnyPublisher<Void, Never> { get }
    func access() -> ReminderAccess
    func refreshAccess() async -> ReminderAccess
    func requestAccess() async throws -> ReminderAccess
    func lists() -> [ReminderList]
    func save(_ draft: ReminderDraft, listID: String?) throws
}

public extension ReminderService {
    var changes: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    func refreshAccess() async -> ReminderAccess { access() }
}

/// EventKit objects remain confined to this adapter. No calendar event is created.
@MainActor public final class EventKitReminderService: ReminderService {
    private let store: any ReminderEventStoreAccessing
    private let clock: any AppClock
    private let accessChanges = PassthroughSubject<Void, Never>()
    private var accessRequest: Task<Bool, Error>?
    private var verificationTask: Task<ReminderAccess, Never>?
    private var requestRevision = 0
    private var verificationRevision = 0
    private var hasVerifiedAccess = false
    private var requestReportedGrant = false
    private var verificationFailed = false
    private var needsStoreReset = true
    private var publishedAccess: ReminderAccess?
    static let authorizationRecheckDelays: [Duration] = [.milliseconds(250), .milliseconds(750), .seconds(2)]
    public convenience init() { self.init(store: EventKitReminderStore()) }
    init(store: any ReminderEventStoreAccessing, clock: any AppClock = ContinuousAppClock()) {
        self.store = store
        self.clock = clock
    }
    deinit {
        accessRequest?.cancel()
        verificationTask?.cancel()
    }
    public var changes: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
            .map { _ in () }
            .merge(with: accessChanges)
            .eraseToAnyPublisher()
    }
    public func access() -> ReminderAccess {
        switch store.authorizationStatus {
        case .fullAccess:
            if needsStoreReset { store.reset(); needsStoreReset = false }
            hasVerifiedAccess = true
            requestReportedGrant = false
            verificationFailed = false
            return .allowed
        case .notDetermined:
            needsStoreReset = true
            guard hasVerifiedAccess || requestReportedGrant else { return .notDetermined }
            return verificationFailed ? .verificationFailed : .checking
        case .restricted:
            clearVerification()
            return .restricted
        case .denied, .writeOnly:
            clearVerification()
            return .denied
        @unknown default:
            clearVerification()
            return .restricted
        }
    }

    /// A successful callback is only a reason to verify, never permission to read or write.
    public func requestAccess() async throws -> ReminderAccess {
        let request: Task<Bool, Error>
        let revision: Int
        if let accessRequest {
            request = accessRequest
            revision = requestRevision
        } else {
            guard access() == .notDetermined else { return await refreshAccess() }
            requestRevision += 1
            revision = requestRevision
            // Settings and the composer share one contextual request. Capturing the
            // adapter, rather than self, leaves the service free to cancel on teardown.
            request = Task { @MainActor [store] in try await store.requestFullAccess() }
            accessRequest = request
        }
        do {
            let reportedGrant = try await request.value
            if requestRevision == revision { accessRequest = nil }
            if reportedGrant { requestReportedGrant = true }
            #if DEBUG
            Logger(subsystem: "Notchium", category: "QuickReminder")
                .debug("Authorization request completed; EventKit status=\(self.store.authorizationStatus.rawValue)")
            #endif
            publishAccessChange()
            guard !Task.isCancelled else { return access() }
            return await refreshAccess()
        } catch {
            if requestRevision == revision { accessRequest = nil }
            publishAccessChange()
            throw error
        }
    }

    /// Coalesces bounded verification. Check Again retries these reads, never TCC prompts.
    public func refreshAccess() async -> ReminderAccess {
        let status = access()
        guard status == .checking || status == .verificationFailed else {
            publishAccessChange()
            return status
        }
        if let verificationTask { return await verificationTask.value }
        verificationFailed = false
        verificationRevision += 1
        let revision = verificationRevision
        publishAccessChange()
        let task = Task { @MainActor [weak self, clock] in
            for delay in Self.authorizationRecheckDelays {
                do { try await clock.sleep(for: delay) }
                catch { return self?.access() ?? .verificationFailed }
                guard !Task.isCancelled, let self else { return .verificationFailed }
                let status = self.access()
                self.publishAccessChange()
                if status != .checking { return status }
            }
            guard let self else { return .verificationFailed }
            self.verificationFailed = true
            self.publishAccessChange()
            return self.access()
        }
        verificationTask = task
        let result = await task.value
        if verificationRevision == revision { verificationTask = nil }
        return result
    }

    private func clearVerification() {
        verificationTask?.cancel()
        hasVerifiedAccess = false
        requestReportedGrant = false
        verificationFailed = false
        needsStoreReset = true
    }

    private func publishAccessChange() {
        let current = access()
        guard current != publishedAccess else { return }
        publishedAccess = current
        accessChanges.send()
    }
    public func lists() -> [ReminderList] {
        guard access() == .allowed else { return [] }
        return store.lists()
    }
    public func save(_ draft: ReminderDraft, listID: String?) throws {
        guard access() == .allowed else { throw ReminderFailure.permission }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ReminderFailure.emptyTitle }
        var savedDraft = draft
        savedDraft.title = title
        try store.save(savedDraft, listID: listID)
    }
}

@MainActor public final class MockReminderService: ReminderService {
    private let changeSubject = PassthroughSubject<Void, Never>()
    public var changes: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }
    public func notifyChanges() { changeSubject.send() }
    public var authorization: ReminderAccess = .allowed
    public var authorizationAfterRequest: ReminderAccess?
    public var availableLists = [ReminderList(id: "personal", title: "Personal")]
    public var failure: ReminderFailure?
    public private(set) var saved: [ReminderDraft] = []
    public private(set) var requestCount = 0
    public init() {}
    public func access() -> ReminderAccess { authorization }
    public func requestAccess() async throws -> ReminderAccess {
        requestCount += 1
        if let authorizationAfterRequest { authorization = authorizationAfterRequest }
        return authorization
    }
    public func lists() -> [ReminderList] { authorization == .allowed ? availableLists : [] }
    public func save(_ draft: ReminderDraft, listID: String?) throws {
        if let failure { throw failure }
        guard authorization == .allowed else { throw ReminderFailure.permission }
        guard !availableLists.isEmpty else { throw ReminderFailure.noWritableList }
        saved.append(draft)
    }
}
