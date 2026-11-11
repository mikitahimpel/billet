import DrawInterface
import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import UIKit
import UsInterface
import UserNotifications
import WidgetKit

/// Whether what the partner sends can reach this phone: the alert permission, the push token, the last push that
/// arrived and the widgets on the Home Screen.
struct DeliveryHealth: Equatable {
    var notificationsAllowed: Bool
    var hasPushToken: Bool
    var lastPush: Date?
    var widgetCount: Int

    /// A push can arrive only with the permission and a token the server knows to send to.
    var pushesWork: Bool { notificationsAllowed && hasPushToken }

    /// The line shown where a missed alert costs most, the Inbox and a new pair; nil while alerts are on. A missing
    /// token is left to Settings: the phone registers again by itself, and there is nothing to tap.
    func notice(partner: String) -> String? {
        notificationsAllowed ? nil : "You won't hear when \(partner) sends something."
    }

    var pushDetail: String {
        if !notificationsAllowed { return "Off: you won't hear when your partner sends something" }
        if !hasPushToken { return "On, but this phone isn't registered yet" }
        return "On"
    }

    var lastPushDetail: String {
        guard let lastPush else { return "None yet" }
        return lastPush.formatted(.relative(presentation: .named))
    }

    var widgetDetail: String {
        switch widgetCount {
        case 0: "None on your Home Screen"
        case 1: "1 on your Home Screen"
        default: "\(widgetCount) on your Home Screen"
        }
    }

    /// Asks for alerts the first time; once asked, only the system's Settings can turn them back on.
    @MainActor
    static func turnOn() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            await DrawingSync.requestPushes(asking: true)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            await UIApplication.shared.open(url)
        }
    }

    static func check() async -> DeliveryHealth {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let allowed: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: allowed = true
        case .denied, .notDetermined: allowed = false
        @unknown default: allowed = false
        }
        let widgets = (try? await WidgetCenter.shared.currentConfigurations().count) ?? 0
        return DeliveryHealth(
            notificationsAllowed: allowed, hasPushToken: PushTokens.load().alert != nil,
            lastPush: PushReceipt.last(), widgetCount: widgets)
    }
}
