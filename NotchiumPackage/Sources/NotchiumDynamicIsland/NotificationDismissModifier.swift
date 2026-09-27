import SwiftUI

/// Only the unused banner background recognizes drags. Native buttons above it
/// retain their click/drag behavior, including Join and the accessible dismiss X.
struct NotificationDismissModifier: ViewModifier {
    let notification: NotchNotification
    let coordinator: NotificationCoordinator
    let reduceMotion: Bool
    @GestureState private var translation: CGSize
    @State private var committedTranslation: CGSize?

    init(notification: NotchNotification, coordinator: NotificationCoordinator, reduceMotion: Bool) {
        self.notification = notification
        self.coordinator = coordinator
        self.reduceMotion = reduceMotion
        _translation = GestureState(initialValue: .zero,
            resetTransaction: Transaction(animation: reduceMotion ? NotchMotion.reduced : NotchMotion.notificationOut))
    }

    func body(content: Content) -> some View {
        let displacement = committedTranslation ?? translation
        content
            .offset(y: NotificationDismissGesturePolicy.offset(for: displacement, reduceMotion: reduceMotion))
            .opacity(NotificationDismissGesturePolicy.opacity(for: displacement))
            .background {
                if notification.dismissible {
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .global)
                            .updating($translation) { value, state, transaction in
                                transaction.animation = nil
                                state = value.translation
                            }
                            .onEnded { value in
                                if NotificationDismissGesturePolicy.shouldDismiss(
                                    translation: value.translation, predicted: value.predictedEndTranslation) {
                                    committedTranslation = value.translation
                                    coordinator.dismissByUser(id: notification.id)
                                }
                            })
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: translation != .zero) { _, interacting in
                coordinator.setInteracting(interacting, id: notification.id)
            }
            .onDisappear { coordinator.setInteracting(false, id: notification.id) }
    }
}
