#if DEBUG
import SwiftUI
import NotchiumMediaFeature
import NotchiumServices

struct MediaDeveloperControls: View {
    let model: MediaFeatureModel
    let mock: MockMediaProvider
    let real: any MediaProviding
    @State private var usesMocks = false
    @State private var errorMessage: String?
    var body: some View {
        Section("Media fixtures") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))]) {
                ForEach(MediaFixture.allCases, id: \.self) { fixture in
                    Button(fixture.rawValue) {
                        if !usesMocks { model.use(mock); usesMocks = true }
                        Task {
                            do { try await mock.apply(fixture); errorMessage = nil }
                            catch { errorMessage = "Play a mock song first." }
                        }
                    }
                }
                Button("Use Real Provider") { model.use(real); usesMocks = false }
            }
            if let errorMessage { Text(errorMessage).font(.caption) }
        }
    }
}
#endif
