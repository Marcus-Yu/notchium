import AppKit
import SwiftUI

public struct CalendarSettingsSection: View {
    @Bindable private var model: CalendarActivityModel
    public init(model: CalendarActivityModel) { self.model = model }

    public var body: some View {
        Section("Calendar") {
            switch model.snapshot.permission {
            case .notRequested:
                Text("Show upcoming events from calendars in Apple Calendar.")
                    .foregroundStyle(.secondary)
                Button("Allow Calendar Access") { model.requestAccess() }
            case .denied, .restricted:
                Text("Allow Notchium in System Settings → Privacy & Security → Calendars.")
                    .foregroundStyle(.secondary)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                }
                Button("Check Again") { model.refresh() }
            case .granted:
                if model.snapshot.calendars.isEmpty {
                    Text("No calendars are configured in Apple Calendar.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.snapshot.calendars) { calendar in
                    Toggle(isOn: Binding(
                        get: { calendar.isSelected },
                        set: { model.setCalendarSelected(calendar.id, selected: $0) }
                    )) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(red: calendar.color.red, green: calendar.color.green,
                                                blue: calendar.color.blue))
                                .frame(width: 9, height: 9)
                            Text(calendar.name)
                        }
                    }
                }
                Text("Only selected calendars appear in the notch. Event details stay on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
