import Foundation

/// The brain's clock as the Labs observatory runs it: wall time scaled by `speed` from an anchor,
/// so changing the speed never makes the cat's time jump.
public struct CatClock: Hashable, Sendable {
  public private(set) var speed: Double
  private var realAnchor: Double
  private var simAnchor: Double

  public static let speeds: [Double] = [1, 10, 60]

  public init(now: Double, speed: Double = 1) {
    self.speed = speed
    realAnchor = now
    simAnchor = now
  }

  /// The brain's time when the wall clock reads `real`.
  public func sim(at real: Double) -> Double { simAnchor + (real - realAnchor) * speed }

  public mutating func set(speed: Double, at real: Double) {
    simAnchor = sim(at: real)
    realAnchor = real
    self.speed = speed
  }
}

/// One thing the cat did, for the observatory's timeline.
public struct CatObservation: Hashable, Sendable {
  public var start: Double
  public var end: Double?
  public var step: CatActivityStep
  public var asleep: Bool
  public var cause: String

  public var group: CatActivityGroup { step.group }
}

/// What the Labs observatory remembers: the last stretches of the cat's life, and a line the owner
/// can paste to say what he saw.
public struct CatObservatory: Hashable, Sendable {
  public static let capacity = 20

  public private(set) var episodes: [CatObservation] = []

  public init() {}

  /// Notes the brain's stack at brain time `t`; a new step starts a new stretch.
  public mutating func observe(_ stack: CatBrainStack, at t: Double, cause: String) {
    let asleep = stack.vitality == .asleep
    if let last = episodes.last, last.step == stack.step, last.asleep == asleep { return }
    if !episodes.isEmpty { episodes[episodes.count - 1].end = t }
    episodes.append(
      CatObservation(start: t, end: nil, step: stack.step, asleep: asleep, cause: cause))
    if episodes.count > Self.capacity { episodes.removeFirst(episodes.count - Self.capacity) }
  }

  /// A short plain-text account, newest first, with the brain's clock and speed.
  public func log(now: Double, speed: Double, utcOffset: Int, seed: UInt64, top: [CatUtilityScore])
    -> String
  {
    func clock(_ t: Double) -> String {
      var local = (t + Double(utcOffset)).truncatingRemainder(dividingBy: 86400)
      if local < 0 { local += 86400 }
      return String(
        format: "%02d:%02d:%02d", Int(local / 3600), Int(local / 60) % 60, Int(local) % 60)
    }
    var lines = ["cat-log seed=\(seed) at \(clock(now)) x\(Int(speed))"]
    if !top.isEmpty {
      lines.append(
        "scores: "
          + top.sorted { $0.score > $1.score }.prefix(4).map {
            "\($0.group.rawValue) \(String(format: "%.2f", $0.score))"
          }.joined(separator: ", "))
    }
    for episode in episodes.reversed() {
      let length = (episode.end ?? now) - episode.start
      lines.append(
        "\(clock(episode.start)) \(episode.group.rawValue)/\(episode.step.rawValue)"
          + (episode.asleep ? " (asleep)" : "") + " \(Int(length.rounded())) s [\(episode.cause)]")
    }
    return lines.joined(separator: "\n")
  }
}
