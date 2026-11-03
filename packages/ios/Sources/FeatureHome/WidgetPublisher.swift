import FeatureInbox
import Foundation
import Persistence
import Pet
import WidgetBridge
import WidgetKit

/// Writes what the pair's widgets need to know and asks them to redraw when it changed.
struct WidgetPublisher: Sendable {
  /// How often the snapshot is written again while nothing changes, so a presence it reports
  /// stays believable.
  static let refresh = Duration.seconds(5 * 60)

  let store: WidgetSnapshotStore?
  let reload: @Sendable () -> Void

  static func live() -> WidgetPublisher {
    WidgetPublisher(
      store: .appGroup(), reload: { WidgetCenter.shared.reloadAllTimelines() })
  }

  /// The snapshot for the pair right now. `partnerHere` is false whenever the app is not in
  /// front, because the room connection closes then and the app can no longer vouch for it.
  static func snapshot(
    play: PairPlay, notes: [NoteRecord], partnerHere: Bool, previous: WidgetSnapshot?,
    now: Date, calendar: Calendar, life: WidgetLife? = nil, dailyShared: Set<String> = []
  ) -> WidgetSnapshot {
    let day = TreatDay.key(for: now, calendar: calendar)
    return WidgetSnapshot(
      catName: play.catName,
      treat: WidgetSnapshot.Treat(play.status(on: day)),
      treatDay: day,
      streak: play.ledger.streak(
        today: day, calendar: calendar, paused: [], alsoShared: dailyShared),
      partnerHere: partnerHere,
      pairedSince: [previous?.pairedSince, notes.map(\.date).min()].compactMap { $0 }.min() ?? now,
      lastSentAt: notes.first { $0.direction == .sent }?.date,
      lastReceivedAt: notes.first { $0.direction == .received }?.date,
      latestReceivedNote: notes.first { $0.direction == .received }?.id,
      life: life,
      updatedAt: now)
  }

  func publish(
    play: PairPlay, notes: [NoteRecord], partnerHere: Bool, now: Date = .now,
    calendar: Calendar = .current, life: WidgetLife? = nil, dailyShared: Set<String> = []
  ) {
    guard let store else { return }
    let previous = store.load()
    let next = Self.snapshot(
      play: play, notes: notes, partnerHere: partnerHere, previous: previous, now: now,
      calendar: calendar, life: life, dailyShared: dailyShared)
    try? store.save(next)
    var changed = next
    changed.updatedAt = previous?.updatedAt ?? next.updatedAt
    if changed != previous { reload() }
  }

  func clear() {
    store?.remove()
    reload()
  }
}
