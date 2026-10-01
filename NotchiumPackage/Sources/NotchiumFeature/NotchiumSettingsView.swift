import NotchiumCore
import NotchiumCaffeineFeature
import NotchiumCalendarFeature
import NotchiumClipboardFeature
import NotchiumFocusFeature
import SwiftUI
import NotchiumQuickActionsFeature
import NotchiumMediaFeature
import NotchiumServices

public struct NotchiumSettingsView: View {
    private let quickActions: QuickActionsModel?
    private let environment: AppEnvironment
    private let caffeineModel: CaffeineControlModel?
    private let audioMeter: SystemAudioMeter?
    private let calendarModel: CalendarActivityModel?
    private let menuBarInsertion: Binding<Bool>?
    private let clipboardModel: ClipboardModel?
    private let focusModeModel: FocusModeModel?
    private let pomodoroModel: PomodoroModel?

    public init(environment: AppEnvironment, audioMeter: SystemAudioMeter? = nil,
                calendarModel: CalendarActivityModel? = nil,
                menuBarInsertion: Binding<Bool>? = nil,
                caffeineModel: CaffeineControlModel? = nil,
                quickActions: QuickActionsModel? = nil,
                clipboardModel: ClipboardModel? = nil,
                focusModeModel: FocusModeModel? = nil,
                pomodoroModel: PomodoroModel? = nil) {
        self.clipboardModel = clipboardModel
        self.focusModeModel = focusModeModel
        self.pomodoroModel = pomodoroModel
        self.quickActions = quickActions
        self.environment = environment
        self.caffeineModel = caffeineModel
        self.audioMeter = audioMeter
        self.calendarModel = calendarModel
        self.menuBarInsertion = menuBarInsertion
    }

    public var body: some View {
        Form {
            if let menuBarInsertion {
                Section("Menu Bar") {
                    Toggle("Show menu-bar icon", isOn: menuBarInsertion)
                    Text("If macOS blocks the icon, allow Notchium in System Settings → Menu Bar. Settings is always available from the expanded notch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let media = environment.services.media as? RealMediaProvider {
                MediaConnectionView(provider: media)
            }
            if let audioMeter { AudioMeterPermissionView(meter: audioMeter) }
            if let calendarModel { CalendarSettingsSection(model: calendarModel) }
            if environment.distributionProfile == .developerID, let caffeineModel {
                LidAwakeSettingsSection(controller: caffeineModel.lidAwake)
            }
            if let quickActions {
                Section("Home") {
                    Toggle("Show Quick Actions", isOn: Binding(get: { quickActions.store.showOnHome },
                                                              set: { quickActions.store.showOnHome = $0 }))
                }
                QuickActionsSettings(model: quickActions)
            }
            if environment.featureFlags[.focus], let focusModeModel, let pomodoroModel {
                FocusSettingsSection(focus: focusModeModel, timer: pomodoroModel)
            }
            if environment.featureFlags[.clipboard], let clipboardModel {
                ClipboardSettingsSection(model: clipboardModel)
            }
            Section("Distribution") {
                Text(environment.distributionProfile.rawValue)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 540)
    }
}
