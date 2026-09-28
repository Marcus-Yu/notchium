import SwiftUI

/// Both feature renderers live inside the one persistent, animated shell.
/// Content has its final dimensions throughout; only the shell clips its reveal.
struct UnifiedNotchNotificationContent: View {
    let model: DynamicIslandPresentationModel
    var presentedExpanded = false

    var body: some View {
        ZStack {
            if let notification = model.notificationCoordinator.active,
               (model.surfaceState != .collapsed) == presentedExpanded {
                Group {
                    switch notification.content {
                    case let .feedback(title, symbol):
                        Label(title, systemImage: symbol)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(2).padding(.horizontal, 24)
                    case .calendar:
                        model.calendarRenderer?.reminderBanner(action: model.activateCurrentActivity)
                    case let .audio(hud):
                        NotchAudioHUDView(hud: hud, action: model.activateCurrentActivity)
                            .padding(.horizontal, 24)
                    }
                }
                .modifier(NotificationDismissModifier(notification: notification,
                    coordinator: model.notificationCoordinator, reduceMotion: model.reduceMotion))
                .id(notification.id)
                .transition(.opacity)
            }
        }
        .animation(NotchMotion.notificationContent, value: model.notificationCoordinator.active?.id)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAction(named: "Dismiss notification") {
            model.notificationCoordinator.dismissByUser()
        }
    }
}
