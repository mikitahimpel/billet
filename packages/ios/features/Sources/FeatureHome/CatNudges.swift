import Foundation
import Labs
import Pet
import UserNotifications

/// Keeps one gentle local notification waiting for when the cat would next be hangry or lonely,
/// as ``CatNudge`` plans it. Planned again whenever the events change, so care from either
/// partner moves it or takes it away. Only for someone who has already allowed notifications.
@MainActor
enum CatNudges {
  static let id = "billet.cat.nudge"
  static let sentKey = "billet.cat.nudge.sent"
  static let plannedKey = "billet.cat.nudge.planned"

  static func plan(
    life: PetLifeModel, temperament: CatTemperament?, name: String,
    defaults: UserDefaults = .standard
  ) async {
    // A speeded-up debug clock never reaches the lock screen.
    guard life.speed <= 1 else { return }
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard DemoPush.isAllowed(settings.authorizationStatus) else { return }
    let now = Date.now
    var sent = defaults.array(forKey: sentKey)?.compactMap { $0 as? Double } ?? []
    // The one waiting last time has gone off if its time has passed.
    let planned = defaults.double(forKey: plannedKey)
    if planned > 0, planned <= now.timeIntervalSince1970, !sent.contains(planned) {
      sent.append(planned)
    }
    sent = sent.filter { now.timeIntervalSince1970 - $0 < 2 * 86400 }
    defaults.set(sent, forKey: sentKey)
    center.removePendingNotificationRequests(withIdentifiers: [id])
    guard
      let plan = CatNudge.next(
        events: life.log.all, now: now, context: life.context, config: life.config,
        temperament: temperament, name: name,
        sent: sent.map(Date.init(timeIntervalSince1970:)))
    else {
      defaults.removeObject(forKey: plannedKey)
      return
    }
    let content = UNMutableNotificationContent()
    content.body = plan.body
    content.threadIdentifier = "cat"
    content.interruptionLevel = .active
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: max(60, plan.at.timeIntervalSince(now)), repeats: false)
    do {
      try await center.add(
        UNNotificationRequest(identifier: id, content: content, trigger: trigger))
      defaults.set(plan.at.timeIntervalSince1970, forKey: plannedKey)
    } catch {
      defaults.removeObject(forKey: plannedKey)
    }
  }
}
