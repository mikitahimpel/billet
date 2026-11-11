import Foundation

/// How much of the room's moving and per-pixel work is spent. The phone's heat and Low Power Mode pick it; Labs can
/// force one.
public enum RoomQualityTier: Int, CaseIterable, Comparable, Sendable, Codable {
  case full
  case fair
  case serious
  case critical

  public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// What a tier turns down. `nil` and `false` mean "off", so a plan only ever removes work from what Labs and the
/// player asked for.
public struct RoomQualityPlan: Equatable, Sendable {
  /// Dust may drift.
  public var motes: Bool
  /// Four samples a pixel on the edges may be asked for.
  public var antialiasing: Bool
  /// The room may sway and its bulbs may pulse.
  public var sway: Bool
  /// The splat cat is rewritten and re-sorted at most this many times a second; 0 is every frame.
  public var splatRate: Int
  /// The cat's splats are cut to this share of the file's, when she loads.
  public var splatDetail: SplatDetail
  /// The room is held on its last frame while the cat is the only thing that would move.
  public var still: Bool

  public init(
    motes: Bool, antialiasing: Bool, sway: Bool, splatRate: Int, splatDetail: SplatDetail,
    still: Bool
  ) {
    self.motes = motes
    self.antialiasing = antialiasing
    self.sway = sway
    self.splatRate = splatRate
    self.splatDetail = splatDetail
    self.still = still
  }
}

extension RoomQualityTier {
  public var plan: RoomQualityPlan {
    switch self {
    case .full:
      RoomQualityPlan(
        motes: true, antialiasing: true, sway: true, splatRate: 0, splatDetail: .full, still: false)
    case .fair:
      RoomQualityPlan(
        motes: false, antialiasing: false, sway: true, splatRate: 30, splatDetail: .balanced,
        still: false)
    case .serious:
      RoomQualityPlan(
        motes: false, antialiasing: false, sway: false, splatRate: 20, splatDetail: .light,
        still: false)
    case .critical:
      RoomQualityPlan(
        motes: false, antialiasing: false, sway: false, splatRate: 15, splatDetail: .light,
        still: true)
    }
  }

  public var title: String {
    switch self {
    case .full: "full"
    case .fair: "fair"
    case .serious: "serious"
    case .critical: "critical"
    }
  }
}

/// What the system says about heat and power, as plain values so the policy needs no Foundation notification.
public struct RoomConditions: Equatable, Sendable {
  public enum Heat: Int, Comparable, Sendable {
    case nominal, fair, serious, critical

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
  }

  public var heat: Heat
  public var lowPower: Bool

  public init(heat: Heat, lowPower: Bool) {
    self.heat = heat
    self.lowPower = lowPower
  }

  /// The tier these conditions ask for, before any hysteresis. Low Power Mode alone is `fair`.
  public var wanted: RoomQualityTier {
    switch heat {
    case .critical: .critical
    case .serious: .serious
    case .fair: .fair
    case .nominal: lowPower ? .fair : .full
    }
  }
}

/// Degrades at once and recovers one step at a time, only after the conditions have asked for something better for
/// `recoverAfter` seconds, so a phone hovering at a threshold does not flip the room between looks.
public struct RoomQualityPolicy: Equatable, Sendable {
  public static let recoverAfter: TimeInterval = 90

  public private(set) var tier: RoomQualityTier
  private var betterSince: TimeInterval?

  public init(tier: RoomQualityTier = .full) {
    self.tier = tier
  }

  /// Feeds one reading taken at `now` seconds; returns the tier to draw with.
  @discardableResult
  public mutating func update(_ conditions: RoomConditions, at now: TimeInterval) -> RoomQualityTier
  {
    let wanted = conditions.wanted
    if wanted >= tier {
      tier = wanted
      betterSince = nil
    } else if let since = betterSince {
      if now - since >= Self.recoverAfter {
        tier = RoomQualityTier(rawValue: tier.rawValue - 1) ?? .full
        betterSince = tier > wanted ? now : nil
      }
    } else {
      betterSince = now
    }
    return tier
  }
}
