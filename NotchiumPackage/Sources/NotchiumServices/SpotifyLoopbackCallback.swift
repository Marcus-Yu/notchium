import Foundation
import Network
import NotchiumCore

/// A five-minute OAuth receiver bound only to IPv4 loopback. One attempt, bounded input.
public actor SpotifyLoopbackCallback {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, any Error>?
    private var timeout: Task<Void, Never>?
    private var connection: NWConnection?
    private var connectionTimeout: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var expectedState: String?
    private let clock: any AppClock
    public init(clock: any AppClock = ContinuousAppClock()) { self.clock = clock }
    public func receive(expectedState: String? = nil,
                        onReady: @escaping @Sendable () -> Void = {}) async throws -> URL {
        guard listener == nil else { throw MediaFailure.busy }
        generation &+= 1
        let generation = generation
        self.expectedState = expectedState
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8888)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                listener.newConnectionHandler = { [weak self] connection in
                    Task { await self?.accept(connection, generation: generation) }
                }
                listener.stateUpdateHandler = { [weak self] state in
                    Task { await self?.listenerChanged(state, generation: generation, onReady: onReady) }
                }
                listener.start(queue: DispatchQueue(label: "Notchium.Spotify.Callback"))
                timeout = Task { [weak self, clock] in
                    do { try await clock.sleep(for: .seconds(300)) } catch { return }
                    await self?.finish(.failure(MediaFailure.authorization), generation: generation)
                }
                if Task.isCancelled { finish(.failure(CancellationError()), generation: generation) }
            }
        } onCancel: { Task { await self.finish(.failure(CancellationError()), generation: generation) } }
    }
    public func cancel() { finish(.failure(CancellationError()), generation: generation) }
    private func listenerChanged(_ state: NWListener.State, generation: UInt64,
                                 onReady: @Sendable () -> Void) {
        guard self.generation == generation, continuation != nil else { return }
        if case .ready = state { onReady() }
        if case .failed = state { finish(.failure(MediaFailure.authorization), generation: generation) }
    }
    private func accept(_ incoming: NWConnection, generation: UInt64) {
        guard self.generation == generation, continuation != nil, connection == nil else { incoming.cancel(); return }
        connection = incoming
        incoming.start(queue: DispatchQueue(label: "Notchium.Spotify.Callback.Read"))
        connectionTimeout = Task { [weak self, clock] in
            do { try await clock.sleep(for: .seconds(10)) } catch { return }
            await self?.close(incoming, generation: generation)
        }
        read(incoming, buffer: Data(), generation: generation)
    }
    private func read(_ incoming: NWConnection, buffer: Data, generation: UInt64) {
        incoming.receive(minimumIncompleteLength: 1, maximumLength: 8192 - buffer.count) { [weak self] data, _, complete, error in
            Task { await self?.received(incoming, buffer: buffer + (data ?? Data()), complete: complete,
                                       failed: error != nil, generation: generation) }
        }
    }
    private func received(_ incoming: NWConnection, buffer: Data, complete: Bool, failed: Bool, generation: UInt64) {
        guard self.generation == generation, continuation != nil, connection === incoming else { incoming.cancel(); return }
        guard !failed, buffer.count < 8192 else { close(incoming, generation: generation); return }
        guard let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") else {
            if complete { close(incoming, generation: generation) }
            else { read(incoming, buffer: buffer, generation: generation) }
            return
        }
        guard let url = Self.callbackURL(request: text, expectedState: expectedState) else {
            close(incoming, generation: generation); return
        }
        let body = "Return to Notchium to finish connecting Spotify."
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        incoming.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            Task { await self?.complete(url, incoming: incoming, generation: generation) }
        })
    }
    static func callbackURL(request: String, expectedState: String?) -> URL? {
        let parts = request.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/callback?"),
              ["HTTP/1.0", "HTTP/1.1"].contains(String(parts[2])),
              let url = URL(string: "http://127.0.0.1:8888" + parts[1]),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path == "/callback", components.fragment == nil else { return nil }
        let items = components.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              let state = items.first(where: { $0.name == "state" })?.value, !state.isEmpty,
              expectedState == nil || state == expectedState else { return nil }
        let codes = items.filter { $0.name == "code" }, errors = items.filter { $0.name == "error" }
        guard (codes.count == 1 && codes[0].value?.isEmpty == false && errors.isEmpty)
            || (errors.count == 1 && errors[0].value?.isEmpty == false && codes.isEmpty) else { return nil }
        return url
    }
    private func complete(_ url: URL, incoming: NWConnection, generation: UInt64) {
        guard self.generation == generation, connection === incoming else { incoming.cancel(); return }
        finish(.success(url), generation: generation)
    }
    private func close(_ incoming: NWConnection, generation: UInt64) {
        incoming.cancel()
        guard self.generation == generation, connection === incoming else { return }
        connection = nil
        connectionTimeout?.cancel(); connectionTimeout = nil
    }
    private func finish(_ result: Result<URL, any Error>, generation: UInt64) {
        guard self.generation == generation else { return }
        listener?.cancel(); listener = nil; connection?.cancel(); connection = nil
        timeout?.cancel(); timeout = nil
        connectionTimeout?.cancel(); connectionTimeout = nil
        expectedState = nil
        let continuation = continuation; self.continuation = nil
        continuation?.resume(with: result)
    }
}
