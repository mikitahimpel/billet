import Foundation

/// What the cat has learned from how the pair treats it, on top of its fixed temperament. Each
/// habit is a 0–1 counter worked out at each day start from recent events, the newer weighing more,
/// so it fades when the care stops. Both phones fold the same events and raise the same cat.
public struct CatUpbringing: Hashable, Sendable {
  /// Petted often: it seeks you out more and comes right up to a finger.
  public var affection = 0.0
  /// Played with a lot: it brings toys and asks to play.
  public var playfulness = 0.0
  /// Left alone for days: it keeps to itself, until care warms it up again.
  public var aloofness = 0.0
  /// Shooed off where it sat: it learns to stay off the desk and the cardigan.
  public var stayingOff = 0.0
  /// The local hour meals have come at on most of the last days, or nil without such an hour.
  public var mealHour: Int?
  /// The local hour pets come at most, or nil with too few pets to tell.
  public var petHour: Int?

  public init(
    affection: Double = 0, playfulness: Double = 0, aloofness: Double = 0, stayingOff: Double = 0,
    mealHour: Int? = nil, petHour: Int? = nil
  ) {
    self.affection = affection
    self.playfulness = playfulness
    self.aloofness = aloofness
    self.stayingOff = stayingOff
    self.mealHour = mealHour
    self.petHour = petHour
  }

  public static let none = CatUpbringing()

  /// Where a double tap on the cat shoos it off instead of asking for a trick.
  public static let shooable: Set<CatActivityStep> = [.sitOnDesk, .sitInCardigan]

  /// The days of events it learns from, inside the week every phone keeps.
  public static let days = 6.0
  /// Seconds for an event's weight to fall by 1/e.
  static let fade = 2.5 * 86400.0
  /// The weighted count at which a habit is about two thirds learned.
  static let pets = 14.0
  static let games = 8.0
  static let shoos = 3.0
  /// Days of no care at all before the cat starts to keep to itself, and the days it takes to
  /// keep to itself fully.
  static let quietGrace = 1.0
  static let quietFull = 3.0
  /// Meals near the same hour on this many of the last days make a mealtime.
  static let mealDays = 3

  /// The tricks it knows, unlocked by care and lost again when the care stops.
  public var tricks: Set<CatLearnedTrick> {
    var known = Set<CatLearnedTrick>()
    if affection >= 0.5, aloofness < 0.5 { known.insert(.comesWhenCalled) }
    if playfulness >= 0.5, affection >= 0.3 { known.insert(.highFive) }
    return known
  }

  public static func learned(
    from events: some Sequence<LifeEvent>, at t: Double, utcOffset: Int
  ) -> CatUpbringing {
    var pets = 0.0
    var games = 0.0
    var shoos = 0.0
    var lastCare: Double?
    var careSinceQuiet = 0.0
    var longestQuiet = 0.0
    var cares: [Double] = []
    var meals: [Double] = []
    var petTimes: [Double] = []
    let window = days * 86400
    var counted = Set<UUID>()
    for event in events.sorted(by: LifeEvent.precedes) where counted.insert(event.id).inserted {
      let at = event.at.timeIntervalSince1970
      let age = t - at
      guard age > 0, age <= window else { continue }
      let weight = exp(-age / fade)
      switch event.kind {
      case .pet:
        pets += weight
        petTimes.append(at)
      case .play: games += weight
      case .shoo: shoos += weight
      case .feed: meals.append(at)
      case .note, .sleep: break
      }
      if event.kind.isCare { cares.append(at) }
    }
    // The longest stretch without care, and the care that came after it.
    var previous = t - window
    for at in cares {
      let quiet = at - previous
      if quiet >= longestQuiet {
        longestQuiet = quiet
        careSinceQuiet = 0
      }
      careSinceQuiet += 1
      previous = at
      lastCare = at
    }
    let quietNow = t - (lastCare ?? t - window)
    if quietNow >= longestQuiet {
      longestQuiet = quietNow
      careSinceQuiet = 0
    }
    let quietDays = longestQuiet / 86400
    let neglect = min(max((quietDays - quietGrace) / (quietFull - quietGrace), 0), 1)
    return CatUpbringing(
      affection: learnt(pets, by: Self.pets), playfulness: learnt(games, by: Self.games),
      aloofness: neglect * exp(-careSinceQuiet / 4), stayingOff: learnt(shoos, by: Self.shoos),
      mealHour: habitHour(meals, utcOffset: utcOffset, days: mealDays),
      petHour: habitHour(petTimes, utcOffset: utcOffset, days: 3))
  }

  /// A count learned towards 1 and never past it: `1 − e^(−count/scale)`.
  static func learnt(_ count: Double, by scale: Double) -> Double {
    1 - exp(-max(count, 0) / scale)
  }

  /// The local hour most of `times` fall within an hour of, if they do so on at least `days`
  /// different days. Between hours with as many, the one they lie closest to wins, then the
  /// earlier.
  static func habitHour(_ times: [Double], utcOffset: Int, days: Int) -> Int? {
    var best: (hour: Int, count: Int, gaps: Double)?
    for hour in 0..<24 {
      var seen = Set<Int>()
      var count = 0
      var gaps = 0.0
      for at in times {
        let local = at + Double(utcOffset)
        let minute = local.truncatingRemainder(dividingBy: 86400) / 60
        let gap = abs(minute - Double(hour * 60))
        guard min(gap, 1440 - gap) <= 60 else { continue }
        seen.insert(Int((local / 86400).rounded(.down)))
        count += 1
        gaps += min(gap, 1440 - gap)
      }
      guard seen.count >= days else { continue }
      if let best, count < best.count || (count == best.count && gaps >= best.gaps) { continue }
      best = (hour, count, gaps)
    }
    return best?.hour
  }

  // MARK: - What it changes

  /// How much likelier each activity is than for a cat that learned nothing. Around the hour pets
  /// usually come, a loved cat comes looking for them.
  public func bias(_ group: CatActivityGroup, hour: Double) -> Double {
    switch group {
    case .social:
      (1 + 0.6 * affection + 0.3 * playfulness) * (1 - 0.6 * aloofness)
        * (isPetHour(hour) ? 1 + affection : 1)
    case .play: 1 + 0.5 * playfulness
    case .mischief: 1 - 0.5 * stayingOff
    case .idle: 1 + 0.4 * aloofness
    case .explore, .rest, .groom, .eat, .watch, .react: 1
    }
  }

  func isPetHour(_ hour: Double) -> Bool {
    guard let petHour else { return false }
    let gap = abs(hour - Double(petHour))
    return min(gap, 24 - gap) <= 1
  }

  /// How far it keeps from a finger, from its temperament's `personalSpace`: closer when loved,
  /// further when left alone.
  public func personalSpace(from space: Double) -> Double {
    min(max(space * (1 - 0.7 * affection) + 0.4 * aloofness, 0), 1)
  }

  /// Whether the hour around `t` is its mealtime: from twenty minutes before to twenty after.
  public func isMealtime(at t: Double, utcOffset: Int) -> Bool {
    guard let mealHour else { return false }
    let minute = (t + Double(utcOffset)).truncatingRemainder(dividingBy: 86400) / 60
    let gap = abs(minute - Double(mealHour * 60))
    return min(gap, 1440 - gap) <= 20
  }

  /// A few of its habits in plain words, the strongest first, for its profile.
  public var habits: [String] {
    var lines: [(String, Double)] = []
    if affection >= 0.4 {
      lines.append(
        (petHour.map { "Loves \(Self.partOfDay($0)) pets" } ?? "Loves a cuddle", affection))
    }
    if let mealHour {
      lines.append(("Waits for \(Self.meal(mealHour)) at \(Self.clock(mealHour))", 0.9))
    }
    if playfulness >= 0.4 { lines.append(("Brings you toys", playfulness)) }
    if stayingOff >= 0.4 { lines.append(("Stays off the desk", stayingOff)) }
    if aloofness >= 0.3 { lines.append(("A little aloof lately", aloofness + 0.2)) }
    if tricks.contains(.comesWhenCalled) { lines.append(("Comes when called", 0.6)) }
    if tricks.contains(.highFive) { lines.append(("Knows high-five", 0.65)) }
    return lines.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
  }

  static func partOfDay(_ hour: Int) -> String {
    switch hour {
    case 5..<12: "morning"
    case 12..<17: "afternoon"
    case 17..<22: "evening"
    default: "late-night"
    }
  }

  static func meal(_ hour: Int) -> String {
    switch hour {
    case 4..<11: "breakfast"
    case 11..<16: "lunch"
    default: "dinner"
    }
  }

  /// `hour` on a twelve-hour clock, as people say it: 8, 12, 7.
  static func clock(_ hour: Int) -> String {
    let twelve = hour % 12
    return String(twelve == 0 ? 12 : twelve)
  }
}

/// A trick the cat learns from care.
public enum CatLearnedTrick: String, CaseIterable, Hashable, Sendable {
  /// Comes every time it is called, however tired of being called it is.
  case comesWhenCalled
  /// Raises a paw to a finger when asked for a trick.
  case highFive
}

extension LifeEvent.Kind {
  /// Whether it is someone looking after the cat, as opposed to telling it off.
  var isCare: Bool {
    switch self {
    case .feed, .pet, .play, .note: true
    case .sleep, .shoo: false
    }
  }
}
