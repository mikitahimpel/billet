import Foundation
import Persistence
import Pet

/// The cat in the corner of the note widget: how it sits, and the one thing it asks for.
///
/// Never stored. The same snapshot read at another hour can give another pose and another ask.
public struct WidgetCat: Equatable, Sendable {
  public enum Pose: String, Equatable, Sendable {
    case sleeping
    case sitting
    /// Awake, and wanting something: it shows what in a bubble.
    case waiting
  }

  public var pose: Pose
  /// What the button offers.
  public var care: WidgetCare
  /// The need in the cat's bubble, while its needs are on and one is low.
  public var thought: PetNeed?

  public init(snapshot: WidgetSnapshot, now: Date, calendar: Calendar) {
    let current = snapshot.current(now: now, calendar: calendar)
    let treatGiven = current.treat == .waitingOnPartner || current.treat == .fed
    if let life = snapshot.life {
      let state = life.state(at: now)
      thought = life.thought(at: now)
      pose = state.asleep ? .sleeping : thought == nil ? .sitting : .waiting
      care = thought == .full ? .treat : .pet
    } else {
      thought = nil
      let hour = calendar.component(.hour, from: now)
      if Self.isNight(hour: hour) {
        pose = .sleeping
      } else {
        pose = treatGiven ? .sitting : .waiting
      }
      care = treatGiven ? .pet : .treat
    }
  }

  /// Night runs from 22:00 to 06:00, when a cat without its needs on is asleep.
  static func isNight(hour: Int) -> Bool {
    hour >= 22 || hour < 6
  }
}

/// What the widget's one button does for the cat.
public enum WidgetCare: String, Codable, CaseIterable, Sendable {
  case pet
  case treat

  /// The plays the room is sent for this care, in order. A treat is the day's treat while it is
  /// this phone's to give, and food either way, as a treat given in the app is.
  public func plays(treat: WidgetSnapshot.Treat) -> [PlayKind] {
    switch self {
    case .pet: [.pet]
    case .treat:
      switch treat {
      case .neither, .waitingOnMe: [.treat, .feed]
      case .waitingOnPartner, .fed: [.feed]
      }
    }
  }

  /// The widget action the app carries out when the room cannot be reached from the widget.
  public var action: WidgetActionKind {
    switch self {
    case .pet: .pet
    case .treat: .treat
    }
  }

  /// The past tense, for "You petted Mochi" and "Your partner fed Mochi".
  public var done: String {
    switch self {
    case .pet: "petted"
    case .treat: "fed"
    }
  }
}

/// When this phone last cared for the cat from a widget, kept so the button cannot be spammed.
public struct CatCareRecord: Codable, Equatable, Sendable {
  public var care: WidgetCare
  public var at: Date

  public init(care: WidgetCare, at: Date) {
    self.care = care
    self.at = at
  }
}

/// What a tap on the widget's care button comes to.
public enum CatCareRequest {
  public enum Refusal: Error, Equatable, Sendable {
    /// The last care from a widget was less than ``cooldown`` ago.
    case tooSoon(until: Date)
    /// The app has not published the pair yet.
    case notPaired
  }

  /// How long after one care the button waits before it works again.
  public static let cooldown: TimeInterval = 10 * 60

  /// When the button works again, or nil when it works now.
  public static func cooling(last: CatCareRecord?, now: Date) -> Date? {
    guard let last else { return nil }
    let until = last.at.addingTimeInterval(cooldown)
    // A clock set back puts `last` in the future, which would lock the button for that long.
    return now >= last.at && now < until ? until : nil
  }

  public static func decide(
    snapshot: WidgetSnapshot?, last: CatCareRecord?, now: Date, calendar: Calendar
  ) -> Result<WidgetCare, Refusal> {
    guard let snapshot else { return .failure(.notPaired) }
    if let until = cooling(last: last, now: now) { return .failure(.tooSoon(until: until)) }
    return .success(WidgetCat(snapshot: snapshot, now: now, calendar: calendar).care)
  }

  /// The snapshot with the care already in it, so the widget shows it before the app has heard.
  /// The app writes its own snapshot over this one the next time it publishes.
  public static func applied(
    _ plays: [(id: UUID, kind: PlayKind)], by device: String?, to snapshot: WidgetSnapshot,
    now: Date, calendar: Calendar
  ) -> WidgetSnapshot {
    var next = snapshot.current(now: now, calendar: calendar)
    for play in plays {
      switch play.kind {
      case .treat:
        next.treat = next.treat == .waitingOnMe ? .fed : .waitingOnPartner
        if next.treat == .fed { next.streak += 1 }
      case .pet, .feed, .play, .sleep:
        guard let device, let kind = play.kind.lifeKind, var life = next.life else { continue }
        life.events.append(LifeEvent(id: play.id, kind: kind, by: device, at: now))
        next.life = life
      }
    }
    return next
  }
}

/// The last care from a widget, as a file of the App Group.
public struct CatCareStore: Sendable {
  public static let fileName = "widget-care.json"

  private let storage: AppGroupStorage

  public init(storage: AppGroupStorage) {
    self.storage = storage
  }

  public static func appGroup() -> CatCareStore? {
    (try? AppGroupStorage.appGroup(identifier: AppGroupStorage.billetIdentifier))
      .map(CatCareStore.init)
  }

  public func load() -> CatCareRecord? {
    (try? storage.readJSON(CatCareRecord.self, named: Self.fileName)) ?? nil
  }

  public func save(_ record: CatCareRecord) throws(PersistenceError) {
    try storage.writeJSON(record, named: Self.fileName)
  }
}

/// The partner's latest care for the cat, which their widget's button sent or their app did.
public struct PartnerCare: Codable, Hashable, Sendable {
  /// How long the line stays on the widget.
  public static let lifetime: TimeInterval = 12 * 60 * 60

  public var care: WidgetCare
  public var at: Date

  public init(care: WidgetCare, at: Date) {
    self.care = care
    self.at = at
  }

  /// The partner's newest pet or meal in `events`, if `me` knows who the partner is not.
  public static func latest(in events: [LifeEvent], me: String) -> PartnerCare? {
    events.last { $0.by != me && ($0.kind == .pet || $0.kind == .feed) }.map {
      PartnerCare(care: $0.kind == .pet ? .pet : .treat, at: $0.at)
    }
  }

  /// "Your partner petted Mochi", without the time, which the widget draws so it keeps counting.
  public func line(cat: String?) -> String {
    "Your partner \(care.done) \(cat ?? "the cat")"
  }

  public func isFresh(at now: Date) -> Bool {
    now.timeIntervalSince(at) < Self.lifetime
  }
}
