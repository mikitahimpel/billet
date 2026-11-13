import ActivityKit
import DrawInterface
import Foundation
import Persistence
import PetScene
import ServerSync
import Transport
import UIKit
import UserNotifications
import WidgetKit

extension DrawingSync {
    static func app(api: APIClient, accounts: AccountStore) -> DrawingSync {
        DrawingSync(
            api: api, accounts: accounts, defaults: .standard,
            reloadWidgets: { WidgetCenter.shared.reloadTimelines(ofKind: $0) })
    }

    /// Asks once; later launches only register, because the token can change.
    static func requestPushes(asking: Bool) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        // A perf run never asks: the system alert would make the app inactive, and nothing answers it on CI.
        if status == .notDetermined, asking, !ScenePerf.isOn {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }
}

extension DrawingSync {
    /// Keeps the push-to-start token of the drawing Live Activity, and the newest such activity only. The server
    /// starts one per drawing, so without this they pile up on the lock screen. Runs as long as the app does.
    static func watchLiveActivities() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await token in Activity<DrawingAttributes>.pushToStartTokenUpdates {
                    PushTokens.save(liveActivity: token.map { String(format: "%02x", $0) }.joined())
                    await MainActor.run { NotificationCenter.default.post(name: .pushTokenChanged, object: nil) }
                }
            }
            group.addTask {
                for await started in Activity<DrawingAttributes>.activityUpdates {
                    for activity in Activity<DrawingAttributes>.activities where activity.id != started.id {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                }
            }
        }
    }
}

/// Receives the APNs device token; the app's only reason for an app delegate.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushTokens.save(alert: deviceToken.map { String(format: "%02x", $0) }.joined())
        NotificationCenter.default.post(name: .pushTokenChanged, object: nil)
    }
}

extension Notification.Name {
    static let pushTokenChanged = Notification.Name("com.ourio.app.push-token-changed")
}
