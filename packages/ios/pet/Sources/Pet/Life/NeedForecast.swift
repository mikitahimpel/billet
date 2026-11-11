import Foundation

/// A stretch of time as the sheet says it: nothing finer than an hour is promised.
public enum NeedSpan: Hashable, Sendable {
  /// Under three quarters of an hour.
  case soon
  case hours(Int)

  /// Nil past a day: too far to say anything useful about a cat.
  public init?(hours: Double) {
    guard hours.isFinite, hours >= 0, hours <= NeedForecast.horizonHours else { return nil }
    self = hours < 0.75 ? .soon : .hours(max(1, Int(hours.rounded())))
  }
}

/// Where a need is heading if nobody does anything.
public enum NeedOutlook: Hashable, Sendable {
  /// Already low: it wants something now.
  case wantsNow
  case lowIn(NeedSpan)
  /// Rising as she sleeps: met again after this long.
  case metIn(NeedSpan)
  /// Nothing changes within a day.
  case steady
}

/// When a need next reads differently, from the same decay the life folds:
/// `n(t) = f + (n₀ − f)·e^(−t/τ)`. An estimate: it takes her as staying awake or asleep as she is
/// now, and Loved as one value where the life keeps one per partner.
public enum NeedForecast {
  public static let horizonHours = 24.0

  /// Hours until a value decaying toward `floor` with time constant `tau` drops below
  /// `threshold`: 0 when it already has, nil when it never will.
  public static func hoursUntil(
    below threshold: Double, from value: Double, floor: Double, tau: Double
  ) -> Double? {
    guard value.isFinite, threshold.isFinite, floor.isFinite, tau.isFinite else { return nil }
    if value < threshold { return 0 }
    guard tau > 0, threshold > floor else { return nil }
    return tau * log((value - floor) / (threshold - floor))
  }

  /// Hours asleep until Rested climbs to `target`, by `r(t) = 1 − (1 − r₀)·e^(−t/τ)`: 0 when it
  /// is there already, nil for a target it only approaches.
  public static func hoursAsleepUntil(
    rested target: Double, from value: Double, config: LifeConfig = .standard
  ) -> Double? {
    guard value.isFinite, target.isFinite else { return nil }
    if value >= target { return 0 }
    guard target < 1, config.restedAsleepHours > 0 else { return nil }
    return config.restedAsleepHours * log((1 - value) / (1 - target))
  }

  /// The time constant `need` falls with for a cat that is `asleep` or not, in hours; nil for
  /// Rested asleep, which rises.
  static func tau(_ need: PetNeed, asleep: Bool, config: LifeConfig) -> Double? {
    switch need {
    case .full: config.fullHours / (asleep ? max(config.fullAsleepPace, 1e-6) : 1)
    case .playful: config.playfulHours / (asleep ? max(config.playfulAsleepPace, 1e-6) : 1)
    case .loved: config.lovedHours
    case .rested: asleep ? nil : config.restedAwakeHours
    }
  }

  public static func outlook(
    _ need: PetNeed, in needs: PetNeeds, asleep: Bool, config: LifeConfig = .standard
  ) -> NeedOutlook {
    let value = needs[need]
    guard let tau = tau(need, asleep: asleep, config: config) else {
      let hours = hoursAsleepUntil(rested: NeedLevel.contentFrom, from: value, config: config)
      guard let hours, hours > 0, let span = NeedSpan(hours: hours) else { return .steady }
      return .metIn(span)
    }
    let hours = hoursUntil(
      below: config.lowBelow, from: value, floor: config.floor, tau: tau)
    guard let hours else { return .steady }
    if hours <= 0 { return .wantsNow }
    return NeedSpan(hours: hours).map(NeedOutlook.lowIn) ?? .steady
  }
}

extension PetNeed {
  /// The outlook in a few words, under the need's level.
  public func hint(_ outlook: NeedOutlook) -> String {
    switch outlook {
    case .wantsNow:
      switch self {
      case .full: "Would love a meal"
      case .rested: "Ready for a nap"
      case .playful: "Would love a game"
      case .loved: "Would love a cuddle"
      }
    case .lowIn(.soon): "\(low) soon"
    case .lowIn(.hours(let hours)): "\(low) in about \(hours) h"
    case .metIn(.soon): "Rested soon"
    case .metIn(.hours(let hours)): "Rested in about \(hours) h"
    case .steady: "Fine for today"
    }
  }

  private var low: String {
    switch self {
    case .full: "Hungry"
    case .rested: "Sleepy"
    case .playful: "Bored"
    case .loved: "Lonely"
    }
  }
}
