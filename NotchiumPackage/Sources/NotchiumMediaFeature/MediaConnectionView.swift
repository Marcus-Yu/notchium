import SwiftUI
import NotchiumServices

public struct MediaConnectionView: View {
    let provider: RealMediaProvider
    @State private var state = MediaState(connectionState: .initializing)
    @State private var actionTask: Task<Void, Never>?
    @State private var actionIssue: String?
    @Environment(\.scenePhase) private var scenePhase
    public init(provider: RealMediaProvider) { self.provider = provider }

    public var body: some View {
        Section("Media Center") {
            Text("Control Spotify on this Mac. No Spotify login or developer account is needed in Notchium.")
                .font(.callout)
            HStack {
                switch state.localSpotifyStatus {
                case .ready:
                    Label("Local control enabled", systemImage: "checkmark.circle.fill")
                    Button("Disable Local Control") { run { try await provider.disconnect() } }
                case .denied:
                    Button("Open System Settings") { SpotifyAutomationSettings.open() }
                    Button("Check Access") { run { await provider.refresh() } }
                case .notRunning:
                    Button("Open Spotify") { run { try await provider.openSpotify() } }
                case .notInstalled:
                    Text("Spotify is not installed.").foregroundStyle(.secondary)
                case .needsPermission:
                    Button("Enable Local Control") { run { try await provider.enableLocalControl() } }
                        .accessibilityIdentifier("notchium.settings.spotifyLocalControl")
                case nil:
                    Text(state.connectionState == .authorizing ? "Waiting for macOS permission…" : "Checking Spotify…")
                }
            }
            .disabled(actionTask != nil)
            Text(actionIssue ?? state.issue ?? state.localSpotifyStatus?.message ?? "")
                .font(.caption).foregroundStyle(.secondary)
            Text("macOS asks for Automation access once. If access is denied, allow Spotify under Privacy & Security → Automation → Notchium. Queue access and remote Spotify Connect devices aren’t available with local control.")
                .font(.caption).foregroundStyle(.secondary)
            Text("The waveform uses the existing audio meter when audio recording permission is granted. Audio is analyzed in memory and never saved.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task {
            for await next in await provider.updates() {
                guard !Task.isCancelled else { return }
                state = next
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { run { await provider.refresh() } }
        }
        .onDisappear { actionTask?.cancel() }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard actionTask == nil else { return }
        actionIssue = nil
        actionTask = Task {
            defer { actionTask = nil }
            do { try await operation() }
            catch is CancellationError {}
            catch { actionIssue = error.localizedDescription }
        }
    }
}
