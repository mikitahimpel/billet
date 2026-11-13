import Foundation

/// The care the sheet offers.
public enum Care: String, CaseIterable, Hashable, Sendable {
  case feed, pet, play, water, brush, treat
}

/// When she has had enough of a care: a need already met, or a run of the same care in a short time.
public struct CareLimits: Equatable, Sendable {
  /// A need at or above this has nothing more to take.
  public var met = 0.95
  /// How many of a care may come within `window` before she asks for a rest.
  public var bursts: [Care: (count: Int, window: TimeInterval)] = [
    .pet: (6, 5 * 60), .play: (3, 15 * 60), .water: (2, 30 * 60), .brush: (2, 30 * 60),
    .treat: (3, 60 * 60),
  ]

  public init() {}

  public static let standard = CareLimits()

  public static func == (a: CareLimits, b: CareLimits) -> Bool {
    a.met == b.met
      && Care.allCases.allSatisfy {
        a.bursts[$0]?.count == b.bursts[$0]?.count && a.bursts[$0]?.window == b.bursts[$0]?.window
      }
  }

  /// The need a care fills, where it fills one.
  static func need(_ care: Care) -> PetNeed? {
    switch care {
    case .feed, .treat: .full
    case .pet, .brush: .loved
    case .play: .playful
    case .water: nil
    }
  }
}

/// What is left of her appetite for care on this phone: the care given lately, and whether the next is welcome.
/// A refused tap changes nothing, so asking again does not push the rest further away.
public struct CareGate: Equatable, Sendable {
  public enum Refusal: Equatable, Sendable {
    /// The need it fills is already met.
    case met
    /// Too many in a row; she wants a rest.
    case tired
  }

  public enum Verdict: Equatable, Sendable {
    case open
    /// `until` is when a tired refusal lifts; nil for a met need, which only time away from the sheet changes.
    case refused(Refusal, until: Date?)

    public var isOpen: Bool { self == .open }
  }

  public private(set) var given: [Care: [Date]] = [:]
  public let limits: CareLimits

  public init(limits: CareLimits = .standard) {
    self.limits = limits
  }

  /// Whether `care` would be welcome now, from her needs (nil while they are unknown, when only bursts count).
  public func verdict(_ care: Care, needs: PetNeeds?, now: Date) -> Verdict {
    if let needs, let need = CareLimits.need(care), needs[need] >= limits.met {
      return .refused(.met, until: nil)
    }
    guard let burst = limits.bursts[care] else { return .open }
    let recent = (given[care] ?? []).filter {
      now.timeIntervalSince($0) < burst.window && $0 <= now
    }
    .sorted()
    guard recent.count >= burst.count else { return .open }
    let oldest = recent[recent.count - burst.count]
    return .refused(.tired, until: oldest.addingTimeInterval(burst.window))
  }

  /// Asks for `care`: given and remembered when welcome, refused and forgotten otherwise.
  public mutating func attempt(_ care: Care, needs: PetNeeds?, now: Date) -> Verdict {
    let verdict = verdict(care, needs: needs, now: now)
    guard verdict.isOpen else { return verdict }
    let horizon = limits.bursts.values.map(\.window).max() ?? 0
    given[care] = ((given[care] ?? []).filter { now.timeIntervalSince($0) < horizon }) + [now]
    return verdict
  }
}
