import SwiftUI

struct MediaPagePlaceholder: View {
    @Environment(\.notchMediaRenderer) private var renderer
    var body: some View {
        if let renderer { renderer.expandedMedia() }
        else { Color.clear }
    }
}
