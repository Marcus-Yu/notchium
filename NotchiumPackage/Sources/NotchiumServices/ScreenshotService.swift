import Foundation
import ImageIO
import CoreGraphics
import NotchiumCore

/// A file-backed capture. Identity is path + creation time, so a new capture reusing a
/// filename is a new capture, while repeated notifications for one file are not.
public struct ScreenshotCapture: Identifiable, Equatable, Sendable {
    public let id: String
    public let fileURL: URL
    public let createdAt: Date

    public init(fileURL: URL, createdAt: Date) {
        self.fileURL = fileURL
        self.createdAt = createdAt
        // Whole seconds: the folder watch and Spotlight report the same file with different precision.
        id = "\(fileURL.path)|\(Int(createdAt.timeIntervalSince1970))"
    }
}

public enum ScreenshotEvent: Equatable, Sendable {
    case captured(ScreenshotCapture)
    case removed(URL)
}

public protocol ScreenshotService: Sendable {
    func availability() async -> FeatureAvailability
    func events() async -> AsyncStream<ScreenshotEvent>
}

/// Detects captures from macOS's own screenshot workflow without Screen Recording permission.
///
/// Primary source: the configured screenshot folder (`com.apple.screencapture` `location`,
/// default Desktop), watched with a kernel directory event (no polling). New files are
/// identified by the `kMDItemIsScreenCapture` extended attribute that screencapture itself
/// writes, independent of file names or language. The initial listing is the legitimate
/// read-only access that raises the folder privacy prompt when the feature starts; a denial
/// is reported through `availability()` instead of silently producing nothing.
///
/// Supplement: a Spotlight query for the same attribute, which also notices captures saved
/// elsewhere (and re-targets the folder watch when the configured location changed).
/// Captures sent only to the clipboard have no file and are not observable.
@MainActor
public final class RealScreenshotService: ScreenshotService {
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var continuations: [UUID: AsyncStream<ScreenshotEvent>.Continuation] = [:]
    private var startedAt = Date()
    /// Bounded de-duplication across both sources and repeated events.
    private var seen: [String] = []
    private var captured: [URL] = []
    private var folder: URL?
    private var folderSource: DispatchSourceFileSystemObject?
    private var knownNames: Set<String> = []
    private var watchTask: Task<Void, Never>?
    private var watchRequested = false
    private var watchRequestGeneration = 0
    private var scanTask: Task<Void, Never>?
    private var scanRequested = false
    private var candidateSources: [URL: DispatchSourceFileSystemObject] = [:]
    private var readinessTasks: [URL: Task<Void, Never>] = [:]
    private var validationRequested: Set<URL> = []
    private var access: FeatureAvailability = .available
    private let locate: @Sendable () -> URL
    private let selectedFolderAccess: ScreenshotFolderAccess?
    private var selectedFolder: URL?
    private var ownsFolderScope = false
    private var generation = 0

    /// `location` overrides the configured folder (tests); production reads screencapture's setting.
    public init(location: (@Sendable () -> URL)? = nil, folderAccess: ScreenshotFolderAccess? = nil) {
        locate = location ?? { RealScreenshotService.configuredLocation() }
        selectedFolderAccess = location == nil ? (folderAccess ?? ScreenshotFolderAccess()) : nil
    }

    isolated deinit { stopObservation() }

    /// Re-attempts the folder watch when previously denied, so a later grant is picked up.
    public func availability() async -> FeatureAvailability {
        if access != .available, query != nil {
            folder = nil
            requestWatch()
        }
        await watchTask?.value
        return access
    }

    public func events() async -> AsyncStream<ScreenshotEvent> {
        let token = UUID()
        let pair = AsyncStream<ScreenshotEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        continuations[token] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.removeObserver(token) }
        }
        if query == nil {
            selectedFolder = selectedFolderAccess?.resolve()
            if selectedFolderAccess?.hasSelection == true, selectedFolder == nil {
                // A broken/revoked selection must not silently broaden back to Desktop/home.
                access = .unavailable(.permissionDenied)
                return pair.stream
            }
            ownsFolderScope = selectedFolder?.startAccessingSecurityScopedResource() ?? false
            startedAt = Date()
            startQuery()
            requestWatch()
        }
        await watchTask?.value
        return pair.stream
    }

    /// The folder screencapture saves to; the Desktop when unset or unusable.
    nonisolated static func configuredLocation(defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.screencapture"),
                                               fileManager: FileManager = .default) -> URL {
        let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        guard let raw = defaults?.string(forKey: "location"), !raw.isEmpty else { return desktop }
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue ? url : desktop
    }

    /// True when screencapture tagged the file as a capture.
    nonisolated static func isScreenCapture(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }

    // MARK: Folder watch

    /// Folder privacy checks can wait inside the filesystem. The stream's caller may
    /// await setup, but neither location resolution nor directory I/O occupies MainActor.
    private func requestWatch() {
        watchRequested = true
        guard watchTask == nil else { return }
        watchRequestGeneration &+= 1
        let request = watchRequestGeneration
        watchTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.watchRequestGeneration == request { self.watchTask = nil } }
            while self.watchRequested, !Task.isCancelled {
                self.watchRequested = false
                let location = await self.watchLocation()
                guard !Task.isCancelled, self.query != nil else { return }
                await self.watch(location)
            }
        }
    }

    private func watch(_ location: URL) async {
        guard folder?.standardizedFileURL != location.standardizedFileURL else { return }
        generation &+= 1
        let generation = generation
        scanTask?.cancel(); scanTask = nil
        scanRequested = false
        folderSource?.cancel()
        folderSource = nil
        folder = location
        let descriptor: Int32
        do {
            let snapshot = try await Self.openWatch(in: location)
            guard !Task.isCancelled, self.generation == generation else {
                close(snapshot.descriptor)
                return
            }
            knownNames = snapshot.names
            descriptor = snapshot.descriptor
        } catch {
            guard !Task.isCancelled, self.generation == generation else { return }
            access = Self.isPermissionError(error) ? .unavailable(.permissionDenied) : .unavailable(.temporarilyUnavailable)
            return
        }
        access = .available
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                if let source, !source.data.intersection([.delete, .rename]).isEmpty {
                    // The old descriptor no longer represents the configured location.
                    self.folder = nil
                    self.requestWatch()
                } else { self.scheduleScan() }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        folderSource = source
    }

    /// Coalesce events already queued in this actor turn; never wait for a timer.
    private func scheduleScan() {
        scanRequested = true
        guard scanTask == nil else { return }
        let generation = generation
        scanTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == generation { self.scanTask = nil } }
            while self.scanRequested, !Task.isCancelled {
                self.scanRequested = false
                let location = await self.watchLocation()
                guard !Task.isCancelled, self.generation == generation else { return }
                guard location.standardizedFileURL == self.folder?.standardizedFileURL else {
                    self.requestWatch()
                    return
                }
                guard let names = try? await Self.directoryNames(in: location), !Task.isCancelled,
                      self.generation == generation else { return }
                self.scan(names: names, in: location)
            }
        }
    }

    private func scan(names: Set<String>, in folder: URL) {
        guard self.folder == folder else { return }
        let added = names.subtracting(knownNames)
        let removed = knownNames.subtracting(names)
        knownNames = names
        for name in added.sorted() {
            let url = folder.appendingPathComponent(name)
            guard Self.isImage(url),
                  let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  created >= startedAt.addingTimeInterval(-2) else { continue }
            observeCandidate(url)
            validate(url: url, created: created)
        }
        for name in removed {
            let url = folder.appendingPathComponent(name)
            stopCandidate(url)
            if captured.contains(url) { remove(url) }
        }
    }

    /// Directory events do not include subsequent file writes/xattrs. Keep a bounded set
    /// of candidate descriptors until screencapture tags and finishes the image.
    private func observeCandidate(_ url: URL) {
        guard candidateSources[url] == nil, !captured.contains(url) else { return }
        if candidateSources.count >= 64, let evicted = candidateSources.keys.min(by: { $0.path < $1.path }) {
            stopCandidate(evicted)
        }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                    self.stopCandidate(url)
                    return
                }
                self.validate(url: url, created: created)
            }
        }
        source.setCancelHandler { close(descriptor) }
        candidateSources[url] = source
        source.resume()
    }

    private func stopCandidate(_ url: URL) {
        validationRequested.remove(url)
        candidateSources.removeValue(forKey: url)?.cancel()
        readinessTasks.removeValue(forKey: url)?.cancel()
    }

    private func validate(url: URL, created: Date) {
        guard !seen.contains(ScreenshotCapture(fileURL: url, createdAt: created).id) else { return }
        // Metadata can arrive repeatedly while ImageIO is reading. Coalesce it without
        // cancelling the in-flight result; otherwise a readable capture can starve forever.
        guard readinessTasks[url] == nil else { validationRequested.insert(url); return }
        readinessTasks[url] = Task { [weak self] in
            let ready = await Self.isReadyCapture(url)
            guard let self, !Task.isCancelled else { return }
            self.readinessTasks[url] = nil
            guard ready else {
                if self.validationRequested.remove(url) != nil { self.validate(url: url, created: created) }
                return
            }
            self.stopCandidate(url)
            self.emit(url: url, created: created)
        }
    }

    @concurrent private static func directoryNames(in folder: URL) async throws -> Set<String> {
        try names(in: folder)
    }

    private func watchLocation() async -> URL {
        if let selectedFolder { return selectedFolder }
        return await Self.resolveLocation(using: locate)
    }

    @concurrent private static func resolveLocation(using locate: @Sendable () -> URL) async -> URL {
        locate()
    }

    @concurrent private static func openWatch(in folder: URL) async throws -> (names: Set<String>, descriptor: Int32) {
        let names = try names(in: folder)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return (names, descriptor)
    }

    /// Decode just a tiny thumbnail off the UI executor. A tag alone does not prove that
    /// an image's bytes are complete. File change events re-attempt incomplete candidates.
    @concurrent static func isReadyCapture(_ url: URL) async -> Bool {
        guard isScreenCapture(url) else { return false }
        if url.pathExtension.lowercased() == "pdf" {
            return CGPDFDocument(url as CFURL).map { $0.numberOfPages > 0 } ?? false
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete else { return false }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceThumbnailMaxPixelSize: 1,
                                       kCGImageSourceShouldCache: false]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil
    }

    private nonisolated static func names(in folder: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") })
    }

    private nonisolated static func isImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "tiff", "pdf", "gif", "bmp"].contains(url.pathExtension.lowercased())
    }

    private nonisolated static func isPermissionError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return true }
        let posix = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code ?? error.code
        return posix == Int(EPERM) || posix == Int(EACCES)
    }

    // MARK: Spotlight supplement

    private func startQuery() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate >= %@",
                                      startedAt as NSDate)
        query.searchScopes = selectedFolder.map { [$0.path] } ?? [NSMetadataQueryUserHomeScope]
        query.notificationBatchingInterval = 0.2
        let identity = ObjectIdentifier(query)
        observers.append(NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query,
                                                                queue: .main) { [weak self] note in
            let added = Self.items(note.userInfo?[NSMetadataQueryUpdateAddedItemsKey])
                + Self.items(note.userInfo?[NSMetadataQueryUpdateChangedItemsKey])
            let removed = Self.items(note.userInfo?[NSMetadataQueryUpdateRemovedItemsKey])
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.query.map(ObjectIdentifier.init) == identity else { return }
                added.forEach { self.observeCandidate($0.0); self.validate(url: $0.0, created: $0.1) }
                removed.forEach { self.remove($0.0) }
                if !added.isEmpty { self.requestWatch() }
            }
        })
        self.query = query
        query.start()
    }

    private nonisolated static func items(_ value: Any?) -> [(URL, Date)] {
        (value as? [NSMetadataItem] ?? []).compactMap { item in
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? Date()
            return (URL(fileURLWithPath: path), created)
        }
    }

    // MARK: Events

    private func emit(url: URL, created: Date) {
        let capture = ScreenshotCapture(fileURL: url, createdAt: created)
        guard !seen.contains(capture.id) else { return }
        seen.append(capture.id)
        if seen.count > 64 { seen.removeFirst(seen.count - 64) }
        captured.append(url)
        if captured.count > 64 { captured.removeFirst(captured.count - 64) }
        continuations.values.forEach { $0.yield(.captured(capture)) }
    }

    private func remove(_ url: URL) {
        guard captured.contains(url) else { return }
        captured.removeAll { $0 == url }
        continuations.values.forEach { $0.yield(.removed(url)) }
    }

    private func removeObserver(_ token: UUID) {
        continuations[token] = nil
        guard continuations.isEmpty else { return }
        stopObservation()
    }

    private func stopObservation() {
        generation &+= 1
        watchRequestGeneration &+= 1
        watchTask?.cancel()
        watchTask = nil
        watchRequested = false
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        folderSource?.cancel()
        folderSource = nil
        folder = nil
        scanTask?.cancel()
        scanTask = nil
        scanRequested = false
        seen.removeAll()
        captured.removeAll()
        knownNames.removeAll()
        candidateSources.values.forEach { $0.cancel() }
        candidateSources.removeAll()
        readinessTasks.values.forEach { $0.cancel() }
        readinessTasks.removeAll()
        validationRequested.removeAll()
        if ownsFolderScope { selectedFolder?.stopAccessingSecurityScopedResource() }
        ownsFolderScope = false
        selectedFolder = nil
    }
}

public struct MockScreenshotService: ScreenshotService {
    public let events: [ScreenshotEvent]
    public init(events: [ScreenshotEvent] = []) { self.events = events }
    public func availability() async -> FeatureAvailability { .available }
    public func events() async -> AsyncStream<ScreenshotEvent> {
        AsyncStream { continuation in
            events.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}
