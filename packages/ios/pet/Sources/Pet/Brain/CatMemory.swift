import Foundation

/// Where the cat likes to be: seconds rested at each kind of spot, a minute more per pet there. A
/// day starts with yesterday at half strength, rehearsed from its canonical start, so a phone just
/// launched remembers the same as one run all week; anything older than two days is gone.
public struct CatMemory: Hashable, Sendable {
  public private(set) var spots: [RoomAffordance.Kind: Double] = [:]
  /// Seconds spent in each group, by local hour of the day, today and as of yesterday.
  public private(set) var hours: [Int: [CatActivityGroup: Double]] = [:]
  public private(set) var yesterday: [Int: [CatActivityGroup: Double]] = [:]

  public init() {}

  /// What one pet counts for, in seconds of rest.
  public static let petWorth = 60.0

  public mutating func rested(at kind: RoomAffordance.Kind, seconds: Double) {
    guard seconds > 0 else { return }
    spots[kind, default: 0] += seconds
  }

  public mutating func petted(at kind: RoomAffordance.Kind) {
    spots[kind, default: 0] += Self.petWorth
  }

  public mutating func spent(_ group: CatActivityGroup, hour: Int, seconds: Double) {
    guard seconds > 0, group != .rest, group != .react else { return }
    hours[hour, default: [:]][group, default: 0] += seconds
  }

  /// How much yesterday's `hour` leaned to `group`: 1 for no habit, up to 1.8 when that was all
  /// the cat did in that hour.
  public func habit(_ group: CatActivityGroup, hour: Int) -> Double {
    guard let day = yesterday[hour] else { return 1 }
    let total = day.values.reduce(0, +)
    guard total > 0 else { return 1 }
    return 1 + 0.8 * (day[group] ?? 0) / total
  }

  /// How much of the cat's rest and petting happened at `kind`, from 0 to 1.
  public func fondness(_ kind: RoomAffordance.Kind) -> Double {
    let total = spots.values.reduce(0, +)
    guard total > 0 else { return 0 }
    return (spots[kind] ?? 0) / total
  }

  /// The spot it likes best, if it has rested anywhere.
  public var favourite: RoomAffordance.Kind? {
    spots.max { a, b in a.value != b.value ? a.value < b.value : a.key.rawValue > b.key.rawValue }?
      .key
  }

  /// This memory as the next day begins with it: the same spots, half as strong.
  public func carried() -> CatMemory {
    var next = CatMemory()
    for (kind, seconds) in spots { next.spots[kind] = seconds / 2 }
    next.yesterday = hours
    return next
  }
}

/// What a day of the brain starts with: the personality as experience has moved it, and the
/// memory of yesterday.
public struct CatDay: Hashable, Sendable {
  public var personality: CatPersonality
  public var memory: CatMemory
  public var upbringing: CatUpbringing

  public init(
    personality: CatPersonality, memory: CatMemory = CatMemory(),
    upbringing: CatUpbringing = .none
  ) {
    self.personality = personality
    self.memory = memory
    self.upbringing = upbringing
  }
}

extension CatPersonality {
  /// How far experience can move a trait from the one the cat was born with.
  public static let driftLimit = 0.15
  /// The days of events a drift reads, inside the week every phone keeps.
  public static let driftDays = 6.0
  /// Seconds for an event's weight in the drift to fall by 1/e.
  static let driftFade = 3 * 86400.0

  /// This personality moved by what happened before `t`: games make the cat more playful and less
  /// lazy, pets more cuddly, notes more vocal and a little more curious, and any care a little
  /// bolder. Each trait moves at most ``driftLimit``.
  public func drifted(by events: some Sequence<LifeEvent>, at t: Double) -> CatPersonality {
    var play = 0.0
    var pet = 0.0
    var note = 0.0
    var feed = 0.0
    for event in events {
      let age = t - event.at.timeIntervalSince1970
      guard age > 0, age <= Self.driftDays * 86400 else { continue }
      let weight = exp(-age / Self.driftFade)
      switch event.kind {
      case .play: play += weight
      case .pet: pet += weight
      case .note: note += weight
      case .feed: feed += weight
      case .sleep, .shoo, .overfeed: break
      }
    }
    func move(_ amount: Double) -> Double { min(max(amount, -Self.driftLimit), Self.driftLimit) }
    var next = self
    next[.playful] += move(0.012 * play)
    next[.lazy] += move(-0.008 * play)
    next[.cuddly] += move(0.008 * pet)
    next[.vocal] += move(0.006 * note)
    next[.curious] += move(0.003 * note)
    next[.bold] += move(0.003 * (play + pet + feed))
    return next
  }
}
