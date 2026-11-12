import Foundation

/// What the cat did today, hour by hour: seconds in each group, sleep included. The brain writes
/// it as it folds the day, so a phone just launched holds the same diary as one open since dawn.
public struct CatDiary: Hashable, Sendable {
  /// By local hour of the day, 0 to 23.
  public private(set) var hours: [Int: [CatActivityGroup: Double]] = [:]

  public init() {}

  /// Notes a stretch in `group`, each hour it crosses getting its own share.
  public mutating func spent(
    _ group: CatActivityGroup, from start: Double, to end: Double, utcOffset: Int
  ) {
    guard start.isFinite, end.isFinite, end > start else { return }
    var t = start
    while t < end {
      let local = t + Double(utcOffset)
      let nextHour = ((local / 3600).rounded(.down) + 1) * 3600 - Double(utcOffset)
      let stop = min(end, nextHour)
      hours[Self.hour(at: t, utcOffset: utcOffset), default: [:]][group, default: 0] += stop - t
      t = stop
    }
  }

  public static func hour(at t: Double, utcOffset: Int) -> Int {
    let hour = Int(((t + Double(utcOffset)) / 3600).rounded(.down)) % 24
    return hour < 0 ? hour + 24 : hour
  }
}

/// One thing in the cat's day worth telling: something she did on her own, or something the couple
/// did with her.
public struct CatDayMoment: Hashable, Sendable, Identifiable {
  public enum Kind: String, CaseIterable, Hashable, Sendable {
    /// Asleep through the night.
    case slept
    case napped
    case ate
    /// A game of her own: a pounce, a chase, zoomies.
    case played
    case watched
    case explored
    case groomed
    case mischief
    /// She came looking for company.
    case soughtYou
    /// A game with one of the couple.
    case playedTogether
    case petted
    case gotNote
  }

  public var kind: Kind
  /// Seconds since 1970.
  public var at: Double
  /// When it was over; `at` for something done in a moment.
  public var until: Double
  /// Whether `at` is the moment itself, for something the couple did, or the start of the hour
  /// she mostly spent this way.
  public var exact: Bool

  public var id: String { "\(kind.rawValue)-\(Int(at))" }

  public init(kind: Kind, at: Double, until: Double? = nil, exact: Bool) {
    self.kind = kind
    self.at = at
    self.until = until ?? at
    self.exact = exact
  }
}

/// The day's diary and the couple's care as a short list of moments, oldest first.
public enum CatDayStory {
  /// The most moments told; the latest are kept.
  public static let limit = 8
  /// An hour counts as spent one way from this many seconds of it.
  public static let hourShare = 600.0
  /// The same care again within this many seconds is one moment.
  public static let careGap = 1800.0
  /// Local hours a sleeping cat is asleep for the night in, as ``CatMind/night``.
  static let night = CatMind.night

  public static func moments(
    diary: CatDiary, events: some Sequence<LifeEvent>, dayStart: Double, now: Double,
    utcOffset: Int
  ) -> [CatDayMoment] {
    guard dayStart.isFinite, now.isFinite, now > dayStart else { return [] }
    let care = careMoments(events, dayStart: dayStart, now: now)
    var own: [CatDayMoment] = []
    var slot = dayStart
    // A day is 24 slots; a clock set far ahead never walks further.
    while slot < now, slot < dayStart + 86400 {
      defer { slot += 3600 }
      let hour = CatDiary.hour(at: slot, utcOffset: utcOffset)
      guard let kind = kind(of: diary.hours[hour] ?? [:], hour: hour) else { continue }
      // What the couple did in this hour is told by its own moment, at its own minute.
      let told = care.contains {
        $0.at >= slot && $0.at < slot + 3600 && covers($0.kind, kind)
      }
      if told { continue }
      // Hours in a row spent the same way are one moment, and a night's sleep that runs into
      // the morning is still the night's sleep.
      if let last = own.last, slot == last.until,
        last.kind == kind || (last.kind == .slept && kind == .napped)
      {
        own[own.count - 1].until = min(slot + 3600, now)
        continue
      }
      own.append(CatDayMoment(kind: kind, at: slot, until: min(slot + 3600, now), exact: false))
    }
    let all = (own + care).sorted { ($0.at, $0.kind.rawValue) < ($1.at, $1.kind.rawValue) }
    return Array(all.suffix(limit))
  }

  /// What an hour was mostly spent on, if on anything for long enough. Sitting about and
  /// reflexes are not worth telling.
  static func kind(of hour: [CatActivityGroup: Double], hour index: Int) -> CatDayMoment.Kind? {
    let told = hour.filter { $0.key != .idle && $0.key != .react && $0.value >= hourShare }
    // Ties fall to the group that comes first, so every phone tells the same day.
    let groups = CatActivityGroup.allCases
    guard
      let top = told.max(by: { a, b in
        a.value != b.value
          ? a.value < b.value
          : (groups.firstIndex(of: a.key) ?? 0) > (groups.firstIndex(of: b.key) ?? 0)
      })
    else { return nil }
    switch top.key {
    case .rest:
      return Double(index) >= night.from || Double(index) < night.until ? .slept : .napped
    case .eat: return .ate
    case .play: return .played
    case .watch: return .watched
    case .explore: return .explored
    case .groom: return .groomed
    case .mischief: return .mischief
    case .social: return .soughtYou
    case .idle, .react: return nil
    }
  }

  static func careMoments(_ events: some Sequence<LifeEvent>, dayStart: Double, now: Double)
    -> [CatDayMoment]
  {
    var last: [CatDayMoment.Kind: Double] = [:]
    var out: [CatDayMoment] = []
    let today = events.map { ($0.kind, $0.at.timeIntervalSince1970) }
      .filter { $0.1 >= dayStart && $0.1 <= now }
      .sorted { $0.1 < $1.1 }
    for (event, at) in today {
      let kind: CatDayMoment.Kind
      switch event {
      case .feed: kind = .ate
      case .play: kind = .playedTogether
      case .pet: kind = .petted
      case .note: kind = .gotNote
      case .sleep, .shoo, .overfeed: continue
      }
      if let before = last[kind], at - before < careGap {
        last[kind] = at
        continue
      }
      last[kind] = at
      out.append(CatDayMoment(kind: kind, at: at, exact: true))
    }
    return out
  }

  /// Whether a moment of the couple's care already tells what the cat did in that hour.
  private static func covers(_ care: CatDayMoment.Kind, _ own: CatDayMoment.Kind) -> Bool {
    switch (care, own) {
    case (.ate, .ate), (.playedTogether, .played), (.petted, .soughtYou): true
    default: false
    }
  }
}
