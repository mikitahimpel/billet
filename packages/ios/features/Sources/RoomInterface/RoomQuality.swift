import Foundation

/// How much of the room's moving and per-pixel work is spent. The phone's heat, Low Power Mode, battery and how long
/// nobody has touched the room pick it (``RoomQualityPolicy``); Labs can force one.
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
  /// Frames a second the room's own loop draws at while something moves, and while nothing does. Only that loop has a
  /// rate to set; a `RealityView` draws every display frame.
  public var activeRate: Int
  public var idleRate: Int
  /// Pixels across per point the room's own loop draws at, never more than the screen's.
  public var scale: Double
  /// The room drawn in the wide colour range.
  public var hdr: Bool
  /// The glow pass over the bulbs, flame and window.
  public var bloom: Bool
  /// The sun's shadow map.
  public var sunShadow: Bool
  /// Only the widest point light of each room stays on. No tier asks for it: a room's lamps are what it is lit by, and
  /// at night the widest light is only the sky's. Labs can still switch it.
  public var widestLightOnly: Bool
  /// Stops of ambient light added to make up for the glow pass being off.
  public var ambientLift: Double
  /// How many times longer the flame, candle and bulbs wait between steps.
  public var pulseSlowdown: Double

  public init(
    motes: Bool, antialiasing: Bool, sway: Bool, splatRate: Int, splatDetail: SplatDetail,
    still: Bool, activeRate: Int = 60, idleRate: Int = 30, scale: Double = 2, hdr: Bool = true,
    bloom: Bool = true, sunShadow: Bool = true, widestLightOnly: Bool = false,
    ambientLift: Double = 0, pulseSlowdown: Double = 1
  ) {
    self.motes = motes
    self.antialiasing = antialiasing
    self.sway = sway
    self.splatRate = splatRate
    self.splatDetail = splatDetail
    self.still = still
    self.activeRate = activeRate
    self.idleRate = idleRate
    self.scale = scale
    self.hdr = hdr
    self.bloom = bloom
    self.sunShadow = sunShadow
    self.widestLightOnly = widestLightOnly
    self.ambientLift = ambientLift
    self.pulseSlowdown = pulseSlowdown
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
        still: false, activeRate: 30, idleRate: 20, scale: 1.5, pulseSlowdown: 1.5)
    case .serious:
      RoomQualityPlan(
        motes: false, antialiasing: false, sway: false, splatRate: 20, splatDetail: .light,
        still: false, activeRate: 30, idleRate: 20, scale: 1.25, bloom: false, sunShadow: false,
        ambientLift: 0.15, pulseSlowdown: 3)
    case .critical:
      RoomQualityPlan(
        motes: false, antialiasing: false, sway: false, splatRate: 15, splatDetail: .light,
        still: true, activeRate: 20, idleRate: 15, scale: 1, bloom: false, sunShadow: false,
        ambientLift: 0.15, pulseSlowdown: 3)
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

/// What the system says about heat and power, and what the player is doing, as plain values so the policy needs no
/// Foundation notification.
public struct RoomConditions: Equatable, Sendable {
  public enum Heat: Int, Comparable, Sendable {
    case nominal, fair, serious, critical

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
  }

  public struct Battery: Equatable, Sendable {
    /// 0 to 1.
    public var level: Double
    public var charging: Bool

    public init(level: Double, charging: Bool) {
      self.level = level
      self.charging = charging
    }
  }

  public var heat: Heat
  public var lowPower: Bool
  /// Nil where the phone does not say.
  public var battery: Battery?
  /// Seconds since a finger touched the room or anything in it moved.
  public var idle: TimeInterval
  /// A finger is dragging, a game is just starting or the pieces are being arranged: a change of look now would be seen
  /// as a hitch.
  public var busy: Bool

  public init(
    heat: Heat, lowPower: Bool, battery: Battery? = nil, idle: TimeInterval = 0, busy: Bool = false
  ) {
    self.heat = heat
    self.lowPower = lowPower
    self.battery = battery
    self.idle = idle
    self.busy = busy
  }

  /// Not charging and at or under these levels.
  public static let batteryLow = 0.2
  public static let batteryCritical = 0.1
  /// Seconds of quiet after which an unattended room is lightened. It stops at `fair`, whose look is the full one's to
  /// the eye (no glow, shadow or light goes), so a room someone is watching does not change as it sits, nor jump back
  /// when they touch it.
  public static let idleFair: TimeInterval = 60

  /// The input that asks for the tier, for the readout.
  public enum Reason: Equatable, Sendable {
    case none
    case heat(Heat)
    case lowPower
    case battery
    case idle
  }

  /// The tier the heat, power and battery ask for, before any hysteresis, and what asked. Low Power Mode alone is
  /// `fair`; a battery under 20% off the charger is `fair` and under 10% `serious`.
  public var asked: (tier: RoomQualityTier, reason: Reason) {
    var best: (tier: RoomQualityTier, reason: Reason) = (.full, .none)
    func ask(_ tier: RoomQualityTier, _ reason: Reason) {
      if tier > best.tier { best = (tier, reason) }
    }
    switch heat {
    case .critical: ask(.critical, .heat(heat))
    case .serious: ask(.serious, .heat(heat))
    case .fair: ask(.fair, .heat(heat))
    case .nominal: break
    }
    if lowPower { ask(.fair, .lowPower) }
    if let battery, !battery.charging {
      if battery.level <= Self.batteryCritical {
        ask(.serious, .battery)
      } else if battery.level <= Self.batteryLow {
        ask(.fair, .battery)
      }
    }
    return best
  }

  public var wanted: RoomQualityTier { asked.tier }

  /// What a room nobody has touched asks for. It follows the player, so it lets go the moment they return.
  public var idleAsk: RoomQualityTier {
    if busy { return .full }
    return idle >= Self.idleFair ? .fair : .full
  }
}

/// Degrades at once and recovers one step at a time, only after the conditions have asked for something better for
/// `recoverAfter` seconds, so a phone hovering at a threshold does not flip the room between looks.
///
/// Heat, power and battery go through that hysteresis. Idleness does not: it only grows until a touch, so it cannot
/// flap, and the room must be at its best the moment the player is back. A degradation the player would see as a hitch
/// (`busy`) waits until they stop, unless the system itself says `serious` or worse.
public struct RoomQualityPolicy: Equatable, Sendable {
  public static let recoverAfter: TimeInterval = 90

  /// What the room draws at.
  public private(set) var tier: RoomQualityTier
  public private(set) var reason: RoomConditions.Reason = .none
  /// The tier heat, power and battery hold, apart from idleness.
  private var base: RoomQualityTier
  private var betterSince: TimeInterval?

  /// The conditions have asked for better than the room draws at, and the wait for it has begun.
  public var isRecovering: Bool { betterSince != nil }

  public init(tier: RoomQualityTier = .full) {
    self.tier = tier
    base = tier
  }

  /// Feeds one reading taken at `now` seconds; returns the tier to draw with.
  @discardableResult
  public mutating func update(_ conditions: RoomConditions, at now: TimeInterval) -> RoomQualityTier
  {
    let asked = conditions.asked
    var wanted = asked.tier
    if conditions.busy, wanted > base, conditions.heat < .serious { wanted = base }
    if wanted >= base {
      if wanted > base { reason = asked.reason }
      base = wanted
      betterSince = nil
    } else if let since = betterSince {
      if now - since >= Self.recoverAfter {
        base = RoomQualityTier(rawValue: base.rawValue - 1) ?? .full
        betterSince = base > wanted ? now : nil
      }
    } else {
      betterSince = now
    }
    let idle = conditions.idleAsk
    if idle > base {
      tier = idle
      reason = .idle
    } else {
      tier = base
      if base == .full { reason = .none }
    }
    return tier
  }
}
