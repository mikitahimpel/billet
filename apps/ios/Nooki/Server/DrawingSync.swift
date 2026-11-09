import ActivityKit
import Foundation
import OurioShared
import Persistence
import PetScene
import Transport
import UIKit
import UserNotifications
import WidgetKit
import Wire

/// Fetches unseen notes, saves the partner's newest drawing for the widgets, and registers APNs tokens.
@MainActor
struct DrawingSync {
    let api: APIClient
    let accounts: AccountStore
    var defaults: UserDefaults = .standard

    static let cursorKey = "drawings.lastSeq"

    func fetchLatest() async {
        let viewer = (try? accounts.load())?.record.userID
        var after = defaults.object(forKey: Self.cursorKey) as? Int
        var newest: LatestDrawing?
        while let page = try? await api.listNotes(after), let last = page.lastSeq {
            for entry in page.notes {
                if let drawing = LatestDrawing(entry.note, seq: entry.seq, viewer: viewer) { newest = drawing }
            }
            after = last
            defaults.set(last, forKey: Self.cursorKey)
        }
        save(newest)
    }

    /// A note that came over the socket while the app was open.
    func received(_ note: Wire.Note, seq: Int) {
        save(LatestDrawing(note, seq: seq, viewer: (try? accounts.load())?.record.userID))
    }

    private func save(_ drawing: LatestDrawing?) {
        guard let drawing, drawing.saveIfNewer() else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: LatestDrawing.widgetKind)
    }

    /// Sends the server any APNs token it does not have yet: the alert token, the widgets' token and the Live
    /// Activity push-to-start token.
    func registerPushTokens() async {
        let tokens = PushTokens.load()
        #if DEBUG
        let environment = ApnsEnvironment.sandbox
        #else
        let environment = ApnsEnvironment.production
        #endif
        if let alert = tokens.alert, alert != tokens.registeredAlert,
           (try? await api.registerPushToken(.init(kind: .alert, environment: environment, token: PushToken(alert)))) != nil {
            PushTokens.update { $0.registeredAlert = alert }
        }
        if let widget = tokens.widget, widget != tokens.registeredWidget,
           (try? await api.registerPushToken(.init(kind: .widget, environment: environment, token: PushToken(widget)))) != nil {
            PushTokens.update { $0.registeredWidget = widget }
        }
        if let start = tokens.liveActivity, start != tokens.registeredLiveActivity,
           (try? await api.registerPushToken(.init(kind: .liveactivity, environment: environment,
                                                   token: PushToken(start)))) != nil {
            PushTokens.update { $0.registeredLiveActivity = start }
        }
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
