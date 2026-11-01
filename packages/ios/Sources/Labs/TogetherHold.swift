import Foundation

/// Two fingers on the cat at the same moment. Each phone knows when its own finger went down and
/// when the partner's did; only the time both are down counts.
public struct TogetherHold: Equatable, Sendable {
  /// How long both must hold for the wisps to reach the heart.
  public static let needed: TimeInterval = 1.2

  public private(set) var mine: Date?
  public private(set) var partners: Date?

  public init() {}

  public mutating func iHold(_ holding: Bool, at date: Date) {
    mine = holding ? (mine ?? date) : nil
  }

  public mutating func partnerHolds(_ holding: Bool, at date: Date) {
    partners = holding ? (partners ?? date) : nil
  }

  public var partnerIsHolding: Bool { partners != nil }
  public var iAmHolding: Bool { mine != nil }

  /// How long both fingers have been down together, as of `now`.
  public func overlap(at now: Date) -> TimeInterval {
    guard let mine, let partners else { return 0 }
    return max(0, now.timeIntervalSince(max(mine, partners)))
  }

  /// 0 when the wisps have not started, 1 when they have met.
  public func progress(at now: Date) -> Double {
    min(1, overlap(at: now) / Self.needed)
  }

  public func isTogether(at now: Date) -> Bool {
    progress(at: now) >= 1
  }
}
