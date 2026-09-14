import AppKit
import SwiftUI
import NotchiumServices

public struct MediaConnectionView: View {
    let provider: RealMediaProvider
    @AppStorage("SpotifyClientID") private var clientID = ""
    @State private var status = "Connect a Spotify Premium account to observe and control playback."
    @State private var providerIssue: String?
    @State private var connectionTask: Task<Void, Never>?
    public init(provider: RealMediaProvider) { self.provider = provider }
    public var body: some View {
        Section("Media Center") {
            TextField("Spotify client ID", text: $clientID)
                .textContentType(.none).disabled(connectionTask != nil)
            Text("Register \(SpotifyAuthorization.redirectURI) as a redirect URI in your Spotify developer app.")
                .font(.caption).textSelection(.enabled)
            HStack {
                Button(connectionTask == nil ? "Connect Spotify" : "Cancel") {
                    if let connectionTask { connectionTask.cancel(); self.connectionTask = nil; return }
                    let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
                    connectionTask = Task {
                        defer { connectionTask = nil }
                        do {
                            let url = try await provider.authorization.begin(clientID: clientID)
                            let receiver = SpotifyLoopbackCallback()
                            status = "Waiting for Spotify authorization…"
                            let callback = try await receiver.receive {
                                Task { @MainActor in NSWorkspace.shared.open(url) }
                            }
                            try Task.checkCancellation()
                            try await provider.authorization.complete(callback: callback)
                            try await provider.connect()
                            status = "Spotify connected. Start playback on an active device."
                        } catch is CancellationError { status = "Connection cancelled." }
                        catch { status = (error as? MediaFailure)?.errorDescription ?? "Spotify connection failed." }
                    }
                }
                Button("Disconnect") {
                    connectionTask?.cancel(); connectionTask = nil
                    Task {
                        do { try await provider.disconnect(); status = "Spotify disconnected." }
                        catch { status = "Could not remove Spotify credentials from Keychain." }
                    }
                }
            }
            Text(providerIssue ?? status).font(.caption).foregroundStyle(.secondary)
            Text(RealMediaProvider.appleMusicLimitation).font(.caption).foregroundStyle(.secondary)
            Text("Other media sources are unsupported. The waveform uses system audio when recording permission is granted. Audio is analyzed in memory and never saved.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task {
            for await state in await provider.updates() {
                guard !Task.isCancelled else { return }
                providerIssue = state.issue
            }
        }
        .onDisappear { connectionTask?.cancel(); connectionTask = nil }
    }
}
