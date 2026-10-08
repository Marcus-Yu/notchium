import NotchiumServices
import SwiftUI

enum MediaSurface: String, CaseIterable, Identifiable {
    case player = "Currently Playing"
    case upNext = "Up Next"
    var id: Self { self }
}

struct MediaPageHeader: View {
    @Binding var selection: MediaSurface

    var body: some View {
        HStack(spacing: 10) {
            ForEach(MediaSurface.allCases) { surface in
                Button {
                    selection = surface
                } label: {
                    Text(surface.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(height: 32)
                        .background(.white.opacity(selection == surface ? 0.18 : 0.06),
                                    in: .rect(cornerRadius: 8))
                        .contentShape(.rect)
                }
                .buttonStyle(MediaControlButtonStyle())
                .accessibilityAddTraits(selection == surface ? .isSelected : [])
                .accessibilityIdentifier(surface == .player
                    ? "notchium.media.surface.currently-playing" : "notchium.media.surface.up-next")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media view")
        .accessibilityIdentifier("notchium.media.surface-picker")
    }
}

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
