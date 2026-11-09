import SwiftUI

struct TeleprompterMicrophonePicker: View {
    @Bindable var session: TeleprompterReadingSession

    var body: some View {
        Picker("Microphone", selection: $session.inputDeviceID) {
            Text(systemDefaultTitle).tag(Optional<String>.none)
            ForEach(session.availableMicrophones) { microphone in
                Text(microphone.name).tag(Optional(microphone.id))
            }
            if let selected = session.inputDeviceID,
               !session.availableMicrophones.contains(where: { $0.id == selected }) {
                Text("Selected microphone unavailable").tag(Optional(selected)).disabled(true)
            }
        }
        .accessibilityIdentifier("notchium.teleprompter.microphone")
    }

    private var systemDefaultTitle: String {
        guard let microphone = session.availableMicrophones.first(where: \.isDefault) else { return "System default" }
        return "System default (\(microphone.name))"
    }
}
