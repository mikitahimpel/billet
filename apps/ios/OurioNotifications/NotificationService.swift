import DrawInterface
import Foundation
import MomentsInterface
import OurioShared
import ProfileInterface
import UsInterface
import UserNotifications
import WidgetKit
import Wire

/// Puts the drawing an alert push carries on the drawing widgets before the alert shows, and writes the partner's
/// name into the alert, which the server does not know. The compact strokes travel in the push, so nothing is
/// fetched; the alert shows whether or not the drawing could be read.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        PushReceipt.stamp()
        if let drawing = LatestDrawing(push: request.content.userInfo), drawing.saveIfNewer() {
            WidgetCenter.shared.reloadTimelines(ofKind: LatestDrawing.widgetKind)
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
