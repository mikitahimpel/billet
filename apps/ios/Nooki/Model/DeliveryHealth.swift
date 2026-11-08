import Foundation
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
