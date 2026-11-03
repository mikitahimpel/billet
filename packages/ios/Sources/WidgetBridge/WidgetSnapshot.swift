import Foundation
import Persistence
import Pet

/// What the app last knew about the pair, written for surfaces that cannot ask the room.
///
/// It is only a picture of a moment: read it through ``current(now:calendar:)``, which drops what a
/// later day has made untrue.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
  public enum Treat: String, Codable, Sendable {
    case neither
    case waitingOnPartner
    case waitingOnMe
    case fed

    public init(_ status: TreatLedger.Status) {
      switch status {
      case .neither: self = .neither
      case .waitingOnPartner: self = .waitingOnPartner
      case .waitingOnMe: self = .waitingOnMe
      case .fed: self = .fed
      }
    }
  }

  /// How long a "partner is here" stays believable after the app last said so.
  public static let presenceLifetime: TimeInterval = 10 * 60

  public var catName: String?
  /// Today's treat, on `treatDay`.
  public var treat: Treat
  public var treatDay: String
  /// The shared streak as of `treatDay`.
  public var streak: Int
  public var partnerHere: Bool
  public var pairedSince: Date?
  public var lastSentAt: Date?
  public var lastReceivedAt: Date?
  /// The newest note the partner sent, the one a heart from a widget answers.
  public var latestReceivedNote: UUID?
  /// The cat's life, when its needs are switched on in Labs.
  public var life: WidgetLife?
  /// The partner's latest pet or meal for the cat, which the note widget mentions.
  public var partnerCare: PartnerCare?
  public var updatedAt: Date

  public init(
    catName: String? = nil,
    treat: Treat = .neither,
    treatDay: String,
    streak: Int = 0,
    partnerHere: Bool = false,
    pairedSince: Date? = nil,
    lastSentAt: Date? = nil,
    lastReceivedAt: Date? = nil,
    latestReceivedNote: UUID? = nil,
    life: WidgetLife? = nil,
    partnerCare: PartnerCare? = nil,
    updatedAt: Date
  ) {
    self.catName = catName
    self.treat = treat
    self.treatDay = treatDay
    self.streak = streak
    self.partnerHere = partnerHere
    self.pairedSince = pairedSince
    self.lastSentAt = lastSentAt
    self.lastReceivedAt = lastReceivedAt
    self.latestReceivedNote = latestReceivedNote
    self.life = life
    self.partnerCare = partnerCare
    self.updatedAt = updatedAt
  }

  /// The snapshot as it stands at `now`: a new day has no treat yet, a missed day ends the streak,
  /// and a presence the app has not repeated lately is gone.
  public func current(now: Date, calendar: Calendar) -> WidgetSnapshot {
    var copy = self
    let today = TreatDay.key(for: now, calendar: calendar)
    if today != treatDay {
      let yesterday = TreatDay.previous(today, calendar: calendar)
      let dayAfter = treatDay < today && yesterday == treatDay
      copy.streak = dayAfter && treat == .fed ? streak : 0
      copy.treat = .neither
      copy.treatDay = today
    }
    if now.timeIntervalSince(updatedAt) > Self.presenceLifetime {
      copy.partnerHere = false
    }
    return copy
  }

  /// Whole days since the pair began, counting the first day as day one.
  public func daysTogether(now: Date, calendar: Calendar) -> Int? {
    guard let pairedSince else { return nil }
    let from = calendar.startOfDay(for: pairedSince)
    let to = calendar.startOfDay(for: now)
    let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
    return max(days, 0) + 1
  }

  /// Whole days since this device last drew a note, or nil when it never has.
  public func daysSinceLastSent(now: Date, calendar: Calendar) -> Int? {
    guard let lastSentAt else { return nil }
    let days =
      calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: lastSentAt), to: calendar.startOfDay(for: now)
      ).day ?? 0
    return max(days, 0)
  }
}

/// The snapshot as a file of the App Group.
public struct WidgetSnapshotStore: Sendable {
  public static let fileName = "widget-snapshot.json"

  private let storage: AppGroupStorage

  public init(storage: AppGroupStorage) {
    self.storage = storage
  }

  public static func appGroup() -> WidgetSnapshotStore? {
    (try? AppGroupStorage.appGroup(identifier: AppGroupStorage.billetIdentifier))
      .map(WidgetSnapshotStore.init)
  }

  public func load() -> WidgetSnapshot? {
    (try? storage.readJSON(WidgetSnapshot.self, named: Self.fileName)) ?? nil
  }

  public func save(_ snapshot: WidgetSnapshot) throws(PersistenceError) {
    try storage.writeJSON(snapshot, named: Self.fileName)
  }

  public func remove() {
    try? storage.remove(Self.fileName)
  }
}
