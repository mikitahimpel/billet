import DrawInterface
import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import ProfileInterface
import UsInterface
import UserNotifications
import WidgetKit
import Wire

/// Puts the drawing or the love streak an alert push carries on the widgets before the alert shows, and writes the
/// partner's name into the alert, which the server does not know. Both travel in the push, so nothing is fetched; the
/// alert shows whether or not they could be read.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        PushReceipt.stamp()
        if let drawing = LatestDrawing(push: request.content.userInfo), drawing.saveIfNewer() {
            LatestDrawing.widgetKinds.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
        }
        if case .streak(let you, _, let streak) = PushPayload(push: request.content.userInfo) {
            StreakStore.save(pushed: LoveStreak(streak, you: you.rawValue))
            WidgetCenter.shared.reloadAllTimelines()
        }
        contentHandler(Self.named(request.content))
    }

    /// The alert with the partner's name as its title, and a body that reads after it.
    static func named(_ content: UNNotificationContent) -> UNNotificationContent {
        guard let couple = CoupleStore.saved(), let payload = PushPayload(push: content.userInfo),
              let named = content.mutableCopy() as? UNMutableNotificationContent else { return content }
        named.title = couple.name(of: couple.other)
        if let body = payload.bodyAfterName { named.body = body }
        return named
    }
}
