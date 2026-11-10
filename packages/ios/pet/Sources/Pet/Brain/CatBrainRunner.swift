import Foundation

/// Runs a ``CatBrain`` on one phone: replays it from the day's start on launch, folds forward as
/// time passes, and copes with events that arrive late, such as the partner's, by going back to a
/// checkpoint from before them. The result at any moment equals a fresh ``replay``.
public struct CatBrainRunner: Sendable {
  public private(set) var brain: CatBrain
  public private(set) var sampler: CatLifeSampler
  /// This phone's own touch, over the brain's interaction region. It never changes the fold.
  public var live: CatInteraction?
  private var checkpoints: [CatBrain] = []
  private let seed: UInt64
  private let temperament: CatTemperament?
  private let personality: CatPersonality?
  private let config: CatBrainConfig

  /// Brain time between checkpoints, and how many are kept: two hours back.
  static let checkpointEvery = 300.0
  static let checkpointCount = 24

  public init(
    events: some Sequence<LifeEvent>, now: Double, context: LifeContext, seed: UInt64,
    temperament: CatTemperament? = nil, personality: CatPersonality? = nil,
    room: RoomAffordances, weather: ViewWeather = .clear,
    lifeConfig: LifeConfig = .standard, config: CatBrainConfig = .standard
  ) {
    self.seed = seed
    self.temperament = temperament
    self.personality = personality
    self.config = config
    sampler = CatLifeSampler(events: events, context: context, config: lifeConfig)
    brain = Self.start(
      sampler: &sampler, now: now, seed: seed, temperament: temperament,
      personality: personality, room: room,
      weather: weather, config: config)
    advance(to: now)
  }

  public var frame: CatBrainFrame { brain.frame(live: live) }

  /// Folds up to `now`, leaving a checkpoint every few minutes of brain time.
  public mutating func advance(to now: Double) {
    guard now >= brain.nextDecision else { return }
    var mark = (checkpoints.last?.time ?? brain.time) + Self.checkpointEvery
    while mark <= now {
      brain.advance(to: mark, life: &sampler)
      checkpoints.append(brain)
      if checkpoints.count > Self.checkpointCount { checkpoints.removeFirst() }
      mark += Self.checkpointEvery
    }
    brain.advance(to: now, life: &sampler)
  }

  /// Takes new events. One from before the brain's time sends it back to the last checkpoint
  /// before it, or to a fresh replay, and forward again to `now`.
  public mutating func receive(_ events: [LifeEvent], now: Double) {
    let known = Set(sampler.all.map(\.id))
    let fresh = events.filter { !known.contains($0.id) }
    guard !fresh.isEmpty else { return }
    sampler = CatLifeSampler(
      events: sampler.all + fresh, context: sampler.context, config: sampler.config,
      grid: sampler.grid)
    let earliest = fresh.map(\.at.timeIntervalSince1970).min() ?? now
    if earliest > brain.time {
      brain.schedule(fresh)
    } else if let index = checkpoints.lastIndex(where: { $0.time < earliest }),
      Self.dayStart(of: checkpoints[index]) == Self.dayStart(of: brain)
    {
      brain = checkpoints[index]
      checkpoints.removeSubrange((index + 1)...)
      // Events at the checkpoint's own time were already folded into it.
      brain.schedule(sampler.events(after: brain.time, through: .infinity))
    } else {
      checkpoints.removeAll()
      brain = Self.start(
        sampler: &sampler, now: now, seed: seed, temperament: temperament,
        personality: personality, room: brain.room,
        weather: brain.weather, config: config)
    }
    advance(to: now)
  }

  /// A debug nudge: plays a script of `group` now. See ``CatBrain/force(_:)``.
  public mutating func force(_ group: CatActivityGroup) {
    brain.force(group)
  }

  /// A different room or weather from now on.
  public mutating func setRoom(_ room: RoomAffordances, weather: ViewWeather) {
    guard room != brain.room || weather != brain.weather else { return }
    brain.setRoom(room, weather: weather)
    for index in checkpoints.indices { checkpoints[index].setRoom(room, weather: weather) }
  }

  /// The brain at `now` for these events, worked out from scratch. Both phones get the same.
  public static func replay(
    events: some Sequence<LifeEvent>, now: Double, context: LifeContext, seed: UInt64,
    temperament: CatTemperament? = nil, personality: CatPersonality? = nil,
    room: RoomAffordances, weather: ViewWeather = .clear,
    lifeConfig: LifeConfig = .standard, config: CatBrainConfig = .standard
  ) -> CatBrain {
    var sampler = CatLifeSampler(events: events, context: context, config: lifeConfig)
    var brain = start(
      sampler: &sampler, now: now, seed: seed, temperament: temperament,
      personality: personality, room: room,
      weather: weather, config: config)
    brain.advance(to: now, life: &sampler)
    return brain
  }

  /// A brain at the start of the day `now` falls in, or at the pet's birth if later, with the
  /// events before it remembered and the rest scheduled.
  private static func start(
    sampler: inout CatLifeSampler, now: Double, seed: UInt64, temperament: CatTemperament?,
    personality: CatPersonality?,
    room: RoomAffordances, weather: ViewWeather, config: CatBrainConfig
  ) -> CatBrain {
    let context = sampler.context
    let dayStart = CatBrain.dayStart(before: now, utcOffset: context.utcOffset, config: config)
    let born = context.born?.timeIntervalSince1970 ?? sampler.all.first?.at.timeIntervalSince1970
    let start = min(max(dayStart, born ?? dayStart), now)
    let day = CatBrain.opening(
      at: start, seed: seed, temperament: temperament,
      nature: personality ?? CatBrain.nature(seed: seed, temperament: temperament), room: room,
      weather: weather,
      sampler: &sampler, utcOffset: context.utcOffset, config: config)
    var brain = CatBrain(
      seed: seed, temperament: temperament, personality: personality, day: day, room: room,
      weather: weather,
      start: start, life: sampler.sample(at: start), utcOffset: context.utcOffset,
      lifeConfig: sampler.config, config: config)
    brain.remember(sampler.all.filter { $0.at.timeIntervalSince1970 < brain.time })
    brain.schedule(sampler.events(after: brain.time - 1e-9, through: .infinity))
    return brain
  }

  private static func dayStart(of brain: CatBrain) -> Double {
    brain.dayStart(after: brain.time) - 86400
  }
}

extension CatBrain {
  /// The latest local `dayStartHour` at or before `t`.
  public static func dayStart(before t: Double, utcOffset: Int, config: CatBrainConfig) -> Double {
    let local = t + Double(utcOffset) - config.dayStartHour * 3600
    let day = (local / 86400).rounded(.down)
    return day * 86400 + config.dayStartHour * 3600 - Double(utcOffset)
  }

  /// What a day starting at `t` begins with: the personality moved by the days before, what the
  /// cat learned from them, and the memory of a rehearsal of the day before from its canonical
  /// start. The rehearsal starts with no memory, so it reaches back one day only.
  public static func opening(
    at t: Double, seed: UInt64, temperament: CatTemperament? = nil, nature: CatPersonality,
    room: RoomAffordances,
    weather: ViewWeather, sampler: inout CatLifeSampler, utcOffset: Int, config: CatBrainConfig
  ) -> CatDay {
    let personality = nature.drifted(by: sampler.all, at: t)
    let birth =
      sampler.context.born?.timeIntervalSince1970
      ?? sampler.all.first?.at
      .timeIntervalSince1970
    let start = max(t - 86400, birth ?? t)
    let upbringing = CatUpbringing.learned(from: sampler.all, at: t, utcOffset: utcOffset)
    guard start < t else { return CatDay(personality: personality, upbringing: upbringing) }
    var rehearsal = CatBrain(
      seed: seed, temperament: temperament, personality: nature,
      day: CatDay(
        personality: nature.drifted(by: sampler.all, at: start),
        upbringing: .learned(from: sampler.all, at: start, utcOffset: utcOffset)),
      room: room,
      weather: weather, start: start, life: sampler.sample(at: start), utcOffset: utcOffset,
      lifeConfig: sampler.config, config: config)
    rehearsal.remember(sampler.all.filter { $0.at.timeIntervalSince1970 < rehearsal.time })
    rehearsal.schedule(sampler.events(after: rehearsal.time - 1e-9, through: t - 1e-9))
    // Up to just before the day line, so the rehearsal never starts a day of its own.
    rehearsal.advance(to: t - config.decisionStep / 2, life: &sampler)
    return CatDay(
      personality: personality, memory: rehearsal.memory.carried(), upbringing: upbringing)
  }
}
