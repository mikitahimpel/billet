import Foundation

/// One petting, from the first stroke to a pause: when the purr starts and stops, when a heart
/// floats up, and when a long pet has gone on long enough for the cat to roll onto its back.
public struct CatPetting: Sendable {
  public enum Event: Hashable, Sendable {
    case purrStarted
    case heart
    case rolled
    case purrEnded
  }

  /// A pause longer than this ends the petting.
  public static let pause = 0.5
  public static let heartEvery = 0.6
  /// How long a petting goes on before the cat rolls over.
  public static let rollAfter = 2.5
  /// How long after a roll before another can come.
  public static let rollCooldown = 10.0

  private var started: Double?
  private var lastTouch = -Double.infinity
  private var lastHeart = -Double.infinity
  private var lastRoll = -Double.infinity
  private var rolledThisTime = false

  public init() {}

  public var isPurring: Bool { started != nil }

  public mutating func touch(at now: Double) -> [Event] {
    var events = tick(at: now)
    lastTouch = now
    if started == nil {
      started = now
      rolledThisTime = false
      lastHeart = now
      events += [.purrStarted, .heart]
    }
    events += due(at: now, canRoll: true)
    return events
  }

  /// Time passed with no new touch: hearts keep coming while the petting lasts, and a pause ends it.
  /// Only a touch rolls the cat, so the roll reaches whoever is stroking.
  public mutating func tick(at now: Double) -> [Event] {
    guard started != nil else { return [] }
    if now - lastTouch > Self.pause {
      started = nil
      return [.purrEnded]
    }
    return due(at: now, canRoll: false)
  }

  private mutating func due(at now: Double, canRoll: Bool) -> [Event] {
    guard let started else { return [] }
    var events: [Event] = []
    if now - lastHeart >= Self.heartEvery {
      lastHeart = now
      events.append(.heart)
    }
    if canRoll, !rolledThisTime, now - started >= Self.rollAfter,
      now - lastRoll >= Self.rollCooldown
    {
      rolledThisTime = true
      lastRoll = now
      events.append(.rolled)
    }
    return events
  }
}
