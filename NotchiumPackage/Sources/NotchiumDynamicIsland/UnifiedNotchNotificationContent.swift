import SwiftUI
import NotchiumDesignSystem

/// Both feature renderers live inside the one persistent, animated shell.
/// Content has its final dimensions throughout; only the shell clips its reveal.
struct UnifiedNotchNotificationContent: View {
    let model: DynamicIslandPresentationModel
    var presentedExpanded = false

    var body: some View {
        ZStack {
            // Compact activities render beside the notch (NotchCompactActivitySlot), not below it.
            if let notification = model.notificationCoordinator.active,
               notification.presentationStyle != .compact,
               (model.surfaceState != .collapsed) == presentedExpanded {
                Group {
                    switch notification.content {
                    case let .feedback(title, symbol):
                        Label {
                            Text(title)
                        } icon: {
                            NotchFeedbackGlyph(symbol: symbol, color: Self.feedbackColor(notification.kind),
                                               reduceMotion: model.reduceMotion)
                        }
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2).padding(.horizontal, NotchNotificationGeometry.contentLeadingInset)
                    case .calendar:
                        model.calendarRenderer?.reminderBanner(action: model.activateCurrentActivity)
                    case let .pomodoroCompletion(title):
                        model.pomodoroRenderer?.completionBanner(title: title, openTimer: model.activateCurrentActivity)
                    case .audio, .compact:
                        EmptyView()
                    }
                }
                .modifier(NotificationDismissModifier(notification: notification,
                    coordinator: model.notificationCoordinator, reduceMotion: model.reduceMotion))
                .id(notification.id)
                .transition(.opacity)
            }
        }
        .animation(model.reduceMotion ? NotchMotionStyle.reduced : NotchMotion.notificationContent,
                   value: model.notificationCoordinator.active?.id)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAction(named: "Dismiss notification") {
            model.notificationCoordinator.dismissByUser()
        }
    }

    /// The glyph carries the outcome: green for done, red for failed. The symbol shape
    /// (checkmark or exclamation mark) says the same thing without color.
    static func feedbackColor(_ kind: NotchNotification.Kind) -> Color {
        switch kind {
        case .actionFailed, .transferFailed: NotchStatusColor.failure
        case .reminderAdded: NotchPalette.orange
        default: NotchStatusColor.success
        }
    }
}

/// A status glyph that lands with one small bounce when its banner appears.
private struct NotchFeedbackGlyph: View {
    let symbol: String
    let color: Color
    let reduceMotion: Bool
    @State private var landed = false

    var body: some View {
        Image(systemName: symbol)
            .symbolVariant(.fill)
            .foregroundStyle(color)
            .symbolEffect(.bounce.up, options: .speed(1.3), value: landed)
            .onAppear { if !reduceMotion { landed = true } }
    }
}
