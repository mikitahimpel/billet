import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import UsInterface
import UserNotifications

/// Local notifications for a planned date, a day and an hour before it. Both partners share this phone's copy of the
/// plans, so a surprise date's reminder names only the organizer and the hint.
enum DateReminders {
    enum Lead: String, CaseIterable {
        case day, hour

        var seconds: TimeInterval {
            switch self {
            case .day: 86_400
            case .hour: 3_600
            }
        }
    }

    /// When each reminder fires; leads already past are left out.
    static func fireDates(for date: Date, now: Date) -> [(Lead, Date)] {
        Lead.allCases.compactMap { lead in
            let fire = date.addingTimeInterval(-lead.seconds)
            return fire > now ? (lead, fire) : nil
        }
    }

    static func schedule(_ plan: PlannedDate, title: String, organizer: String) async {
        cancel(plan.id)
        guard plan.remind == true else { return }
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        for (lead, fire) in fireDates(for: plan.date, now: .now) {
            let content = UNMutableNotificationContent()
            let when = lead == .day ? "Tomorrow" : "In an hour"
            if plan.surprise {
                content.title = "\(when): a surprise date from \(organizer)"
                content.body = plan.hint.isEmpty ? "Keep the time free." : "Hint: \(plan.hint)"
            } else {
                content.title = "\(when): \(title)"
                content.body = plan.place.isEmpty
                    ? plan.date.formatted(date: .omitted, time: .shortened)
                    : "\(plan.date.formatted(date: .omitted, time: .shortened)), \(plan.place)"
            }
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: id(plan.id, lead), content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func cancel(_ planID: UUID) {
        let ids = Lead.allCases.map { id(planID, $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func id(_ planID: UUID, _ lead: Lead) -> String { "date-\(planID.uuidString)-\(lead.rawValue)" }
}
