import SwiftUI

/// The same notification content overlays the bottom of the existing black shell.
/// Pages retain their identity, layout, selection and focus behind this transient row.
struct ExpandedNotificationOverlay: View {
    let model: DynamicIslandPresentationModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if model.showsExpandedNotification, let notification = model.notificationCoordinator.active {
                UnifiedNotchNotificationContent(model: model, presentedExpanded: true)
                    .frame(height: NotchNotificationGeometry.contentHeight(for: notification.presentationStyle))
                    .background(.black)
                    .transition(.opacity)
            }
        }
        .animation(NotchMotion.notificationContent, value: model.notificationCoordinator.active?.id)
    }
}
