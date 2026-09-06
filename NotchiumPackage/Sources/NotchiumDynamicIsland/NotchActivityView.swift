import SwiftUI

struct NotchActivityView: View {
    let activity: NotchActivity

    var body: some View {
        VStack(spacing: 8) {
            Text(activity.title)
                .font(.headline)
                .lineLimit(2)
            if let subtitle = activity.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notchium.activity")
    }
}
