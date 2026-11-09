import Foundation

/// The cat's water bowl: past the brim the jug spills into a puddle. A bowl filled to the line's
/// band can be served; too much can be poured back out, and the puddle wiped up.
public struct WaterBowl: Equatable, Sendable {
  public enum Rating: Equatable, Sendable {
    case perfect, good
    /// A puddle is still on the floor; she drinks anyway.
    case spill
  }

  /// The fill line, as a share of the bowl's depth.
  public static let line = 0.72
  /// How far either side of the line still counts.
  public static let band = 0.07
  /// Seconds of full flow from empty to the line.
  public static let fillTime = 3.6
  /// A puddle smaller than this is a few drops, nothing to wipe.
  public static let dry = 0.02

  /// 0 empty, 1 at the brim.
  public private(set) var level: Double = 0
  /// What went over the brim and is still on the floor, in bowls' depths.
  public private(set) var puddle: Double = 0

  public init() {}

  public var isOverLine: Bool { level > Self.line + Self.band }
  public var isSpilling: Bool { level >= 1 }
  public var canServe: Bool { level >= Self.line - Self.band }

  /// Pours for `dt` seconds at `flow` (0...1 of the jug's full stream).
  public mutating func pour(flow: Double, dt: Double) {
    level += min(max(flow, 0), 1) / Self.fillTime * Self.line * dt
    if level > 1 {
      puddle += level - 1
      level = 1
    }
  }

  /// Tips the bowl out for `dt` seconds, at a quarter of the jug's stream.
  public mutating func pourOut(dt: Double) {
    level = max(0, level - 0.25 / Self.fillTime * Self.line * dt)
  }

  /// A wipe of the cloth takes up `amount` of the puddle.
  public mutating func wipe(_ amount: Double) {
    puddle = max(0, puddle - amount)
    if puddle < Self.dry / 4 { puddle = 0 }
  }

  public var rating: Rating {
    if puddle > Self.dry { return .spill }
    return abs(level - Self.line) <= Self.band / 2 ? .perfect : .good
  }

  public var hint: String {
    if puddle > Self.dry, !isSpilling { return "Wipe up the puddle, or serve it as it is" }
    if isSpilling { return "Spilling!" }
    if isOverLine { return "Past the line: tip some out" }
    if canServe { return "Right there. Let go" }
    return level < 0.05 ? "Hold to pour" : "A little more…"
  }
}
