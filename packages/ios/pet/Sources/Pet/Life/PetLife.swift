import Foundation

/// What the life needs to know besides the events: whose care counts, the pair's clock, and when
/// time stood still.
public struct LifeContext: Hashable, Sendable {
  /// The pair's two devices. Each has its own Loved; a partner who has not been seen yet still
  /// counts, so the pet misses them.
  public var partners: Set<String>
  /// The pair's UTC offset in seconds, for the hour the day rhythm reads.
  public var utcOffset: Int
  /// Spans when nothing falls, such as while the porch light is on.
  public var frozen: [DateInterval]
  /// When the pet's life began: its first event. Before that it neither falls nor rises, so a new
  /// pet starts at the initial values instead of after a week alone.
  public var born: Date?

  public init(
    partners: Set<String>, utcOffset: Int, frozen: [DateInterval] = [], born: Date? = nil
  ) {
    self.partners = partners
    self.utcOffset = utcOffset
    self.frozen = frozen
    self.born = born
  }
}

/// The pet at one moment.
public struct LifeState: Hashable, Sendable {
  public var needs: PetNeeds
  /// Each partner's own Loved, by device. `needs.loved` is their soft minimum.
  public var love: [String: Double]
  public var asleep: Bool
  public var mood: Double
  /// The partner the pet misses, when one has cared for it much less than the other.
  public var missing: String?
  /// Overfed within the last `stuffedHours`: she keeps away from the bowl.
  public var stuffed = false
}

/// The pet's life as a pure function of events and time, the same on every phone and the widget.
/// Needs decay toward a floor, `n(t) = f + (n₀ − f)·e^(−Δt/τ)`; events add `g·(1 − n)^k`. The fold
/// walks a fixed grid of absolute times from a week back, or from the pet's birth if later.
public enum PetLife {
  public static func state(
    events: some Sequence<LifeEvent>, now: Date, context: LifeContext,
    config: LifeConfig = .standard
  ) -> LifeState {
    var fold = Fold(config: config, context: context)
    let step = max(60, config.stepHours * 3600)
    let horizon = now.timeIntervalSince1970 - config.horizonHours * 3600
    let born = context.born.map { min($0, now) } ?? now
    var t = (max(horizon, born.timeIntervalSince1970) / step).rounded(.down) * step
    fold.begin(at: t)
    let window = events.filter {
      $0.at.timeIntervalSince1970 >= t && $0.at <= now
    }
    var seen = Set<UUID>()
    let ordered = window.sorted(by: LifeEvent.precedes).filter { seen.insert($0.id).inserted }
    let end = now.timeIntervalSince1970
    for event in ordered {
      t = fold.advance(from: t, to: event.at.timeIntervalSince1970, step: step)
      fold.apply(event)
    }
    _ = fold.advance(from: t, to: end, step: step)
    fold.now = end
    return fold.state
  }

  public static func forecast(
    events: [LifeEvent], at times: [Date], context: LifeContext, config: LifeConfig = .standard
  ) -> [LifeState] {
    times.map { state(events: events, now: $0, context: context, config: config) }
  }

  /// Sleepiness from the hour alone, `½ + ½·cos(2π(h − h₀)/24)`: 1 at the sleepiest hour, 0
  /// twelve hours later.
  public static func sleepiness(hour: Double, config: LifeConfig = .standard) -> Double {
    0.5 + 0.5 * cos(2 * .pi * (hour - config.sleepiestHour) / 24)
  }

  /// `n + g·(1 − n)^k`, capped at 1.
  public static func gain(_ n: Double, by g: Double, returns k: Double) -> Double {
    min(1, n + g * pow(max(0, 1 - n), k))
  }

  /// `f + (n − f)·e^(−Δt/τ)`.
  public static func decay(_ n: Double, toward floor: Double, hours: Double, tau: Double) -> Double
  {
    guard tau > 0 else { return floor }
    return floor + (n - floor) * exp(-hours / tau)
  }

  /// The soft minimum `−(1/β)·ln(mean(e^(−β·Lᵢ)))`, which leans on the smaller value.
  public static func softMin(_ values: [Double], sharpness beta: Double) -> Double {
    guard let low = values.min() else { return 0 }
    guard beta > 0 else { return values.reduce(0, +) / Double(values.count) }
    let mean =
      values.reduce(0) { $0 + exp(-beta * ($1 - low)) } / Double(values.count)
    return low - log(mean) / beta
  }
}

private struct Fold {
  let config: LifeConfig
  let context: LifeContext
  let partners: [String]
  var full: Double
  var rested: Double
  var playful: Double
  var love: [String: Double]
  var asleep = false
  /// Seconds since 1970.
  var wokeAt = -Double.infinity
  var stuffedUntil = -Double.infinity
  var now = Double.infinity

  init(config: LifeConfig, context: LifeContext) {
    self.config = config
    self.context = context
    var partners = context.partners.sorted()
    // A pair always has two: the one not yet seen is missed like an absent one.
    while partners.count < 2 { partners.append("partner-\(partners.count)") }
    self.partners = partners
    full = config.initial
    rested = config.initial
    playful = config.initial
    love = Dictionary(uniqueKeysWithValues: partners.map { ($0, config.initial) })
  }

  mutating func begin(at t: Double) {
    asleep = pressure(at: t) > config.sleepAbove
  }

  mutating func advance(from t: Double, to end: Double, step: Double) -> Double {
    var t = t
    while t < end {
      let next = min(end, ((t / step).rounded(.down) + 1) * step)
      pass(from: t, to: next)
      t = next
    }
    return max(t, end)
  }

  /// One stretch short enough that the hour and whether it sleeps stay as they were at its start.
  private mutating func pass(from t: Double, to end: Double) {
    let hours = (end - t - frozenOverlap(t, end)) / 3600
    guard hours > 0 else { return }
    let f = config.floor
    let fullPace = asleep ? config.fullAsleepPace : 1
    let playPace = asleep ? config.playfulAsleepPace : 1
    full = PetLife.decay(full, toward: f, hours: hours * fullPace, tau: config.fullHours)
    playful = PetLife.decay(playful, toward: f, hours: hours * playPace, tau: config.playfulHours)
    if asleep {
      rested = 1 - (1 - rested) * exp(-hours / max(config.restedAsleepHours, 1e-6))
    } else {
      rested = PetLife.decay(rested, toward: f, hours: hours, tau: config.restedAwakeHours)
    }
    for partner in partners {
      love[partner] = PetLife.decay(
        love[partner] ?? config.initial, toward: f, hours: hours, tau: config.lovedHours)
    }
    let p = pressure(at: end)
    if asleep, p < config.wakeBelow {
      asleep = false
    } else if !asleep, p > config.sleepAbove, end - wokeAt >= config.stayUpHours * 3600 {
      asleep = true
    }
  }

  mutating func apply(_ event: LifeEvent) {
    let k = config.returns
    switch event.kind {
    case .feed:
      full = PetLife.gain(full, by: config.feedGain, returns: k)
    case .pet:
      care(event.by, config.petGain)
    case .play:
      playful = PetLife.gain(playful, by: config.playGain, returns: k)
      rested = max(config.floor, rested - config.playTiring)
      care(event.by, config.playLoveGain)
    case .note:
      for partner in partners { care(partner, config.noteGain) }
    case .sleep:
      asleep = true
      return
    case .shoo:
      return
    case .overfeed:
      full = 1
      playful = max(config.floor, playful - config.overfeedPlayfulDrop)
      stuffedUntil = event.at.timeIntervalSince1970 + config.stuffedHours * 3600
      return
    }
    asleep = false
    wokeAt = event.at.timeIntervalSince1970
  }

  /// Care from a device the pair does not know yet goes to the partner not yet seen. With both
  /// partners known it adds nothing, so a stray device ID never makes a third Loved.
  private mutating func care(_ by: String, _ g: Double) {
    guard let who = partners.contains(by) ? by : placeholders.first else { return }
    love[who] = PetLife.gain(love[who] ?? config.initial, by: g, returns: config.returns)
  }

  private var placeholders: [String] { partners.filter { !context.partners.contains($0) } }

  private func pressure(at t: Double) -> Double {
    let local = t + Double(context.utcOffset)
    let hour = local.truncatingRemainder(dividingBy: 86400) / 3600
    let s = PetLife.sleepiness(hour: hour < 0 ? hour + 24 : hour, config: config)
    return config.rhythmWeight * s + config.tirednessWeight * (1 - rested)
  }

  private func frozenOverlap(_ start: Double, _ end: Double) -> Double {
    var total = 0.0
    for span in context.frozen {
      let a = max(start, span.start.timeIntervalSince1970)
      let b = min(end, span.end.timeIntervalSince1970)
      if b > a { total += b - a }
    }
    return min(total, end - start)
  }

  var state: LifeState {
    let values = partners.map { love[$0] ?? config.floor }
    let loved = PetLife.softMin(values, sharpness: config.loveSharpness)
    let needs = PetNeeds(full: full, rested: rested, loved: loved, playful: playful)
    let most = values.max() ?? 0
    let missing = partners.first { most - (love[$0] ?? 0) >= config.missingGap }
    return LifeState(
      needs: needs, love: love, asleep: asleep, mood: needs.mood(weights: config.weights),
      missing: missing, stuffed: now < stuffedUntil)
  }
}
