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
    @State private var selection: SettingsCategory? = .general
    private let quickActions: QuickActionsModel?
    private let environment: AppEnvironment
    private let caffeineModel: CaffeineControlModel?
    private let audioMeter: SystemAudioMeter?
    private let waveformAppearance: WaveformAppearanceModel?
    private let calendarModel: CalendarActivityModel?
    private let menuBarInsertion: Binding<Bool>?
    private let clipboardModel: ClipboardModel?
    private let focusModeModel: FocusModeModel?
    private let pomodoroModel: PomodoroModel?

    public init(environment: AppEnvironment, audioMeter: SystemAudioMeter? = nil,
                waveformAppearance: WaveformAppearanceModel? = nil,
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
        self.waveformAppearance = waveformAppearance
        self.calendarModel = calendarModel
        self.menuBarInsertion = menuBarInsertion
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Notchium") {
                    categoryLink(.general)
                }
                Section("Features") {
                    ForEach(featureCategories) { category in
                        categoryLink(category)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 195, max: 240)
            .accessibilityIdentifier("notchium.settings.sidebar")
        } detail: {
            Form {
                settings(for: selection ?? .general)
            }
            .formStyle(.grouped)
            .navigationTitle((selection ?? .general).title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("notchium.settings.detail")
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 740, idealWidth: 800, minHeight: 520, idealHeight: 600)
        .onChange(of: quickActions?.requestedEditID) { _, id in
            if id != nil { selection = .home }
        }
        .onAppear {
            if quickActions?.requestedEditID != nil { selection = .home }
        }
    }

    private var featureCategories: [SettingsCategory] {
        SettingsCategory.allCases.filter { category in
            switch category {
            case .general: false
            case .home: quickActions != nil
            case .media: environment.services.media is RealMediaProvider || waveformAppearance != nil
            case .audio: audioMeter != nil
            case .calendar: calendarModel != nil
            case .clipboard: environment.featureFlags[.clipboard] && clipboardModel != nil
            case .focus: environment.featureFlags[.focus] && focusModeModel != nil && pomodoroModel != nil
            case .caffeine: environment.distributionProfile == .developerID && caffeineModel != nil
            }
        }
    }

    private func categoryLink(_ category: SettingsCategory) -> some View {
        NavigationLink(value: category) {
            Label(category.title, systemImage: category.symbol)
        }
        .accessibilityIdentifier("notchium.settings.category.\(category.rawValue)")
    }

    @ViewBuilder private func settings(for category: SettingsCategory) -> some View {
        switch category {
        case .general:
            if let menuBarInsertion {
                Section("Menu Bar") {
                    Toggle("Show menu-bar icon", isOn: menuBarInsertion)
                    Text("If macOS blocks the icon, allow Notchium in System Settings → Menu Bar. Settings is always available from the expanded notch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("About") {
                LabeledContent("App", value: "Notchium")
                Text("Settings apply immediately.").font(.caption).foregroundStyle(.secondary)
            }
        case .home:
            if let quickActions {
                HomeSettingsSections(model: quickActions)
                QuickActionsSettings(model: quickActions, showActions: false)
            }
        case .media:
            if let media = environment.services.media as? RealMediaProvider {
                MediaConnectionView(provider: media)
            }
            if let waveformAppearance { WaveformAppearanceSettings(appearance: waveformAppearance) }
        case .audio:
            if let audioMeter { AudioMeterPermissionView(meter: audioMeter) }
        case .calendar:
            if let calendarModel { CalendarSettingsSection(model: calendarModel) }
        case .clipboard:
            if let clipboardModel { ClipboardSettingsSection(model: clipboardModel) }
        case .focus:
            if let focusModeModel, let pomodoroModel {
                FocusSettingsSection(focus: focusModeModel, timer: pomodoroModel)
            }
        case .caffeine:
            if let caffeineModel {
                LidAwakeSettingsSection(controller: caffeineModel.lidAwake)
            }
        }
    }
}
