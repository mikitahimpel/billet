import Design
import Foundation
import ProfileInterface
import MomentsInterface
import WidgetInterface
import WidgetUI
import UsInterface
import UserNotifications

extension AppSettings {
    /// Settings: the evening nudge while the love streak is at risk. In the app group, as the notification extension
    /// plans the nudge again when a streak push comes.
    static let streakNudgeKey = "streak.nudge"
}

/// One local notification at 20:00 on a day the love streak would go out at midnight (docs/love-streak.md). It is
/// planned again each time the streak changes, so the day counting takes it back, and its single id keeps it to one
/// a day.
enum StreakNudge {
    static let id = "streak-at-risk"
    static let hour = 20

    /// Where the Settings switch is kept.
    nonisolated(unsafe) static let settings = CatProfile.store

    static func isOn(in defaults: UserDefaults = settings) -> Bool {
        defaults.object(forKey: AppSettings.streakNudgeKey) as? Bool ?? true
    }

    /// A switch set while it was this app's own setting moves to the app group.
    static func moveToAppGroup(from old: UserDefaults = .standard, to group: UserDefaults = settings) {
        guard group != old, group.object(forKey: AppSettings.streakNudgeKey) == nil,
              let value = old.object(forKey: AppSettings.streakNudgeKey) as? Bool else { return }
        group.set(value, forKey: AppSettings.streakNudgeKey)
        old.removeObject(forKey: AppSettings.streakNudgeKey)
    }

    struct Plan: Equatable {
        let fire: Date
        let title: String
        let body: String
    }

    /// The next evening the streak is at risk as this phone knows it: today's while it is still ahead, or tomorrow's
    /// once today counts or this phone's person did their part. Nil when nothing is at stake.
    static func plan(for streak: LoveStreak, catName: String, now: Date, calendar: Calendar = .current) -> Plan? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let evening = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                  evening > now,
                  streak.status(on: evening, calendar: calendar) == .atRisk else { continue }
            switch streak.turn(on: evening, calendar: calendar) {
            case .partners: continue
            case .yours:
                return Plan(fire: evening, title: "\(catName) misses you tonight",
                            body: "Your partner did their part. Do yours before midnight to keep your "
                                + "\(streak.count)-day streak.")
            case nil:
                return Plan(fire: evening, title: "\(catName) misses you two tonight",
                            body: "Do one small thing together before midnight to keep your "
                                + "\(streak.count)-day streak.")
            }
        }
        return nil
    }

    /// Replaces the pending nudge with this streak's; nothing is asked for, so without permission none is added.
    static func reschedule(_ streak: LoveStreak, enabled: Bool, catName: String, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard enabled, let plan = plan(for: streak, catName: catName, now: now) else { return }
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        case .denied, .notDetermined: return
        @unknown default: return
        }
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
