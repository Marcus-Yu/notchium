import NotchiumServices
import SwiftUI

/// Source-specific branding and destinations stay together as more providers are added.
struct MediaSourceDestination {
    let logoName: String
    let applicationURL: URL
    let fallbackURL: URL

    init(source: MediaSource) {
        switch source {
        case .spotify:
            logoName = "SpotifyLogo"
            applicationURL = URL(string: "spotify:")!
            fallbackURL = URL(string: "https://www.spotify.com/download/")!
        }
    }

    @MainActor
    func open(using openURL: OpenURLAction) {
        openURL(applicationURL) { accepted in
            if !accepted { openURL(fallbackURL) }
        }
    }
}

struct MediaSourceButton: View {
    static let contentInset: CGFloat = 10
    let source: MediaSource
    @Environment(\.openURL) private var openURL

    var body: some View {
        let destination = MediaSourceDestination(source: source)
        Button {
            destination.open(using: openURL)
        } label: {
            Image(destination.logoName, bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .padding(Self.contentInset)
                .contentShape(.rect)
        }
        .buttonStyle(MediaControlButtonStyle())
        .help("Open \(source.rawValue)")
        .accessibilityLabel("Open \(source.rawValue)")
        .accessibilityIdentifier("notchium.media.open-source")
    }
}
