import Foundation
import Network

/// A five-minute OAuth receiver bound only to IPv4 loopback. One attempt, bounded input.
public actor SpotifyLoopbackCallback {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, any Error>?
    private var timeout: Task<Void, Never>?
    private var connection: NWConnection?
    public init() {}
    public func receive(onReady: @escaping @Sendable () -> Void = {}) async throws -> URL {
        guard listener == nil else { throw MediaFailure.busy }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8888)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                listener.newConnectionHandler = { [weak self] connection in
                    Task { await self?.accept(connection) }
                }
                listener.stateUpdateHandler = { [weak self] state in
                    if case .ready = state { onReady() }
                    if case .failed = state { Task { await self?.finish(.failure(MediaFailure.authorization)) } }
                }
                listener.start(queue: DispatchQueue(label: "Notchium.Spotify.Callback"))
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(300)) } catch { return }
                    await self?.finish(.failure(MediaFailure.authorization))
                }
                if Task.isCancelled { finish(.failure(CancellationError())) }
            }
        } onCancel: { Task { await self.cancel() } }
    }
    public func cancel() { finish(.failure(CancellationError())) }
    private func accept(_ incoming: NWConnection) {
        guard connection == nil else { incoming.cancel(); return }
        connection = incoming
        incoming.start(queue: DispatchQueue(label: "Notchium.Spotify.Callback.Read"))
        read(incoming, buffer: Data())
    }
    private func read(_ incoming: NWConnection, buffer: Data) {
        incoming.receive(minimumIncompleteLength: 1, maximumLength: 8192 - buffer.count) { [weak self] data, _, complete, error in
            Task { await self?.received(incoming, buffer: buffer + (data ?? Data()), complete: complete, failed: error != nil) }
        }
    }
    private func received(_ incoming: NWConnection, buffer: Data, complete: Bool, failed: Bool) {
        guard continuation != nil else { incoming.cancel(); return }
        guard !failed, buffer.count < 8192 else { incoming.cancel(); connection = nil; return }
        guard let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") else {
            if complete { incoming.cancel(); connection = nil }
            else { read(incoming, buffer: buffer) }
            return
        }
        let parts = text.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/callback?"),
              let url = URL(string: "http://127.0.0.1:8888" + parts[1]) else {
            incoming.cancel(); connection = nil; return
        }
        let body = "Return to Notchium to finish connecting Spotify."
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        incoming.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            Task { await self?.finish(.success(url)) }
        })
    }
    private func finish(_ result: Result<URL, any Error>) {
        listener?.cancel(); listener = nil; connection?.cancel(); connection = nil
        timeout?.cancel(); timeout = nil
        let continuation = continuation; self.continuation = nil
        continuation?.resume(with: result)
    }
}
