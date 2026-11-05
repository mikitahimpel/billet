import Foundation
import UserNotifications
import WidgetKit

/// Puts the drawing an alert push carries on the drawing widgets before the alert shows. The compact strokes travel
/// in the push, so nothing is fetched; the alert shows whether or not the drawing could be read.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        if let drawing = LatestDrawing(push: request.content.userInfo), drawing.saveIfNewer() {
            WidgetCenter.shared.reloadTimelines(ofKind: LatestDrawing.widgetKind)
        }
        contentHandler(request.content)
    }
}
