import DrawInterface
import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import ProfileInterface
import UsInterface
import UserNotifications
import Persistence
import WidgetKit
import Wire

/// Puts the drawing or the love streak an alert push carries on the widgets before the alert shows, and writes the
/// partner's name into the alert, which the server does not know. Both travel in the push, so nothing is fetched; the
/// alert shows whether or not they could be read. A streak push also plans the evening nudge again, so tomorrow's
/// comes without the app being opened.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        PushReceipt.stamp()
        if let drawing = LatestDrawing(push: request.content.userInfo), drawing.saveIfNewer() {
            LatestDrawing.widgetKinds.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
        }
        let named = Self.named(request.content)
        guard case .streak(let you, _, let streak) = PushPayload(push: request.content.userInfo) else {
            contentHandler(named)
            return
        }
        StreakStore.save(pushed: LoveStreak(streak, you: you.rawValue))
        WidgetCenter.shared.reloadAllTimelines()
        // The file, not the push: it may be newer than an out-of-order push, and has this phone's unsent days on top.
        let saved = SharedFile.read(LoveStreak.self, from: StreakStore.file) ?? LoveStreak(streak, you: you.rawValue)
        // The system's handler may be called from any thread, once, and the content is no longer changed here; the SDK
        // marks neither Sendable.
        nonisolated(unsafe) let deliver = contentHandler
        nonisolated(unsafe) let content = named
        Task {
            await StreakNudge.reschedule(saved, enabled: StreakNudge.isOn(), catName: CatProfile.name())
            deliver(content)
        }
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
