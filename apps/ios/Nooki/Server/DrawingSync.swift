import Foundation
import Persistence
import Transport
import UIKit
import UserNotifications
import WidgetKit
import Wire

/// Keeps the drawing widgets and the push lanes up to date from the app's side: fetches the notes this phone has not
/// seen and saves the partner's newest drawing for the widgets, and registers the APNs tokens with the server.
@MainActor
struct DrawingSync {
    let api: APIClient
    let accounts: AccountStore
    var defaults: UserDefaults = .standard

    static let cursorKey = "drawings.lastSeq"

    /// Pages through the notes after the last one seen and saves the newest drawing the partner sent.
    func fetchLatest() async {
        let viewer = (try? accounts.load())?.record.userID
        var after = defaults.object(forKey: Self.cursorKey) as? Int
        var newest: LatestDrawing?
        while let page = try? await api.listNotes(after), let last = page.notes.last {
            for entry in page.notes {
                if let drawing = LatestDrawing(entry.note, seq: entry.seq, viewer: viewer) { newest = drawing }
            }
            after = last.seq
            defaults.set(last.seq, forKey: Self.cursorKey)
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

    /// Sends the server any APNs token it does not have yet: the app's alert token and the widgets' token.
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
    }

    /// Asks once to show the partner's drawings as notifications, then registers for pushes. Later launches only
    /// register, because the token can change.
    static func requestPushes(asking: Bool) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined, asking {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
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
    static let pushTokenChanged = Notification.Name("com.mikitahimpel.billet.push-token-changed")
}
