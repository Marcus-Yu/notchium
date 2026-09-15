import AppKit
import SwiftUI
import NotchiumServices

public struct MediaConnectionView: View {
    let provider: RealMediaProvider
    @AppStorage("SpotifyClientID") private var clientID = ""
    @State private var status = "Connect a Spotify Premium account to observe and control playback."
    @State private var providerIssue: String?
    @State private var connectionState: MediaConnectionState = .initializing
    @State private var connectionTask: Task<Void, Never>?
    public init(provider: RealMediaProvider) { self.provider = provider }
    public var body: some View {
        Section("Media Center") {
            TextField("Spotify client ID", text: $clientID)
                .textContentType(.none).disabled(connectionTask != nil)
                .accessibilityIdentifier("notchium.settings.spotifyClientID")
            Text("Register \(SpotifyAuthorization.redirectURI) as a redirect URI in your Spotify developer app.")
                .font(.caption).textSelection(.enabled)
            HStack {
                if connectionState == .authenticated {
                    Label("Connected to Spotify", systemImage: "checkmark.circle.fill")
                } else {
                    Button(connectionTask == nil ? "Connect Spotify" : "Cancel") {
                        if let connectionTask { connectionTask.cancel(); self.connectionTask = nil; return }
                        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
                        connectionTask = Task {
                            defer { connectionTask = nil }
                            do {
                                let url = try await provider.beginAuthorization(clientID: clientID)
                                let receiver = SpotifyLoopbackCallback()
                                status = "Waiting for Spotify authorization…"
                                let callback = try await receiver.receive {
                                    Task { @MainActor in NSWorkspace.shared.open(url) }
                                }
                                try Task.checkCancellation()
                                try await provider.completeAuthorization(callback: callback)
                                status = "Spotify connected. Start playback on an active device."
                            } catch is CancellationError {
                                await provider.cancelAuthorization()
                                status = "Connection cancelled."
                            }
                            catch {
                                await provider.failAuthorization()
                                status = (error as? MediaFailure)?.errorDescription ?? "Spotify connection failed."
                            }
                        }
                    }
                    .disabled(connectionState == .initializing)
                }
                if connectionState == .authenticated {
                    Button("Disconnect") {
                        connectionTask?.cancel(); connectionTask = nil
                        Task {
                            do { try await provider.disconnect(); status = "Spotify disconnected." }
                            catch { status = "Could not remove Spotify credentials from Keychain." }
                        }
                    }
                }
            }
            Text(providerIssue ?? status).font(.caption).foregroundStyle(.secondary)
            Text("Other media sources are unsupported. The waveform uses system audio when recording permission is granted. Audio is analyzed in memory and never saved.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task {
            for await state in await provider.updates() {
                guard !Task.isCancelled else { return }
                connectionState = state.connectionState
                providerIssue = state.issue
                guard state.issue == nil else { continue }
                switch state.connectionState {
                case .initializing:
                    status = "Restoring your Spotify session…"
                case .authorizing:
                    status = "Connecting Spotify…"
                case .authenticated:
                    status = state.hasMedia
                        ? "Spotify connected."
                        : "Spotify connected. Start playback on an active device."
                case .unauthenticated:
                    status = "Connect a Spotify Premium account to observe and control playback."
                case .error:
                    break
                }
            }
        }
        .onDisappear {
            connectionTask?.cancel(); connectionTask = nil
            Task { await provider.cancelAuthorization() }
        }
    }
}
