import SwiftUI

struct MediaPagePlaceholder: View {
    @Environment(\.notchMediaRenderer) private var renderer
    var body: some View {
        if let renderer { renderer.expandedMedia() }
        else {
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .semibold))
                Text("Spotify")
                    .font(.system(size: 15, weight: .semibold))
                Text("Media service is initializing.")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("notchium.media.status.initializing")
        }
    }
}
