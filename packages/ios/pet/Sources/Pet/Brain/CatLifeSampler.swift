import Foundation

/// The pet's life as the brain reads it at one moment.
public struct CatLifeSample: Hashable, Sendable {
  public var needs: PetNeeds
  public var mood: Double
  public var asleep: Bool
  /// `rhythm·s(h) + tiredness·(1 − Rested)`, the needs engine's sleep pressure.
  public var pressure: Double
  /// Overfed within the hour: she keeps away from the bowl.
  public var stuffed: Bool

  public init(needs: PetNeeds, mood: Double, asleep: Bool, pressure: Double, stuffed: Bool = false)
  {
    self.needs = needs
    self.mood = mood
    self.asleep = asleep
    self.pressure = pressure
    self.stuffed = stuffed
  }
}

/// Reads ``PetLife`` for the brain on a coarse grid. The life only changes slowly between events,
/// so a sample holds from one grid line, or the latest event, to the next; the brain asks many
/// times a minute and works the life out a few times an hour.
public struct CatLifeSampler: Sendable {
  public let context: LifeContext
  public let config: LifeConfig
  /// Seconds between samples with no event between them.
  public let grid: Double
  private let events: [LifeEvent]
  private let times: [Double]
  private var cache: [Double: CatLifeSample] = [:]

  public init(
    events: some Sequence<LifeEvent>, context: LifeContext, config: LifeConfig = .standard,
    grid: Double = 900
  ) {
    var seen = Set<UUID>()
    let ordered = events.sorted(by: LifeEvent.precedes).filter { seen.insert($0.id).inserted }
    self.events = ordered
    times = ordered.map(\.at.timeIntervalSince1970)
    self.context = context
    self.config = config
    self.grid = grid
  }

  public var all: [LifeEvent] { events }

  /// The moment a sample at `t` is worked out for: the grid line before it, or the latest event
  /// since then.
  public func key(at t: Double) -> Double {
    let line = (t / grid).rounded(.down) * grid
    guard let index = lastIndex(atOrBefore: t) else { return line }
    return max(line, times[index])
  }

  public mutating func sample(at t: Double) -> CatLifeSample {
    let key = key(at: t)
    if let cached = cache[key] { return cached }
    let state = PetLife.state(
      events: events, now: Date(timeIntervalSince1970: key), context: context, config: config)
    let local = key + Double(context.utcOffset)
    var hour = local.truncatingRemainder(dividingBy: 86400) / 3600
    if hour < 0 { hour += 24 }
    let pressure =
      config.rhythmWeight * PetLife.sleepiness(hour: hour, config: config)
      + config.tirednessWeight * (1 - state.needs.rested)
    let sample = CatLifeSample(
      needs: state.needs, mood: state.mood, asleep: state.asleep, pressure: pressure,
      stuffed: state.stuffed)
    if cache.count > 512 { cache.removeAll(keepingCapacity: true) }
    cache[key] = sample
    return sample
  }

  /// The events from `start`, exclusive, up to `end`, inclusive, in fold order.
  public func events(after start: Double, through end: Double) -> ArraySlice<LifeEvent> {
    let low = times.firstIndex { $0 > start } ?? times.endIndex
    let high = (lastIndex(atOrBefore: end).map { $0 + 1 }) ?? times.startIndex
    return low < high ? events[low..<high] : []
  }

  private func lastIndex(atOrBefore t: Double) -> Int? {
    var low = 0
    var high = times.count
    while low < high {
      let middle = (low + high) / 2
      if times[middle] <= t { low = middle + 1 } else { high = middle }
    }
    return low > 0 ? low - 1 : nil
  }
}
