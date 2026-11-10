import Foundation

/// One stretch of a day the cat spent in one step, from the brain's own moves.
public struct CatSegment: Hashable, Sendable {
  public var start: Double
  public var end: Double
  public var step: CatActivityStep
  public var asleep: Bool

  public var length: Double { end - start }
  public var group: CatActivityGroup { step.group }
}

/// Measures how a day of the brain looks to someone watching: where the time goes, how long each
/// thing lasts, how often it repeats itself and how much of the day there is something to see.
public struct CatLifeAudit: Sendable {
  public var segments: [CatSegment]
  public let start: Double
  public let end: Double
  public let utcOffset: Int

  /// The brain run untouched from `start` for `hours`, every move kept.
  public init(
    events: [LifeEvent] = [], context: LifeContext, seed: UInt64,
    temperament: CatTemperament? = nil, room: RoomAffordances, start: Double, hours: Double = 24
  ) {
    var config = CatBrainConfig()
    config.transitionCount = .max
    var runner = CatBrainRunner(
      events: events, now: start, context: context, seed: seed, temperament: temperament,
      room: room, config: config)
    let end = start + hours * 3600
    var t = start
    while t < end {
      t += 60
      runner.advance(to: min(t, end))
    }
    var current = (at: start, step: CatActivityStep.sit, asleep: false)
    var first = true
    var out: [CatSegment] = []
    func close(at time: Double) {
      guard time > current.at else { return }
      out.append(
        CatSegment(start: current.at, end: time, step: current.step, asleep: current.asleep))
    }
    for move in runner.brain.transitions where move.at >= start {
      if first {
        current = (start, move.from.step, move.from.vitality == .asleep)
        first = false
      }
      let to = (step: move.to.step, asleep: move.to.vitality == .asleep)
      if to.step == current.step && to.asleep == current.asleep { continue }
      close(at: move.at)
      current = (move.at, to.step, to.asleep)
    }
    close(at: end)
    segments = out
    self.start = start
    self.end = end
    utcOffset = context.utcOffset
  }

  // MARK: - Time

  public func hour(_ t: Double) -> Double {
    var hour = (t + Double(utcOffset)).truncatingRemainder(dividingBy: 86400) / 3600
    if hour < 0 { hour += 24 }
    return hour
  }

  public func share(of test: (CatSegment) -> Bool) -> Double {
    segments.filter(test).reduce(0) { $0 + $1.length } / max(end - start, 1)
  }

  public func share(of group: CatActivityGroup) -> Double { share { $0.group == group } }

  /// Steps whose picture is the cat sitting or lying where it is, with at most its head moving.
  public static let quiet: Set<CatActivityStep> = [
    .sit, .loaf, .lookAround, .curl, .waitByBowl, .waitByDoor, .sulk, .sitInCardigan, .sitOnDesk,
    .watchWindow, .watchPartnerWindow,
  ]

  public var asleepShare: Double { share { $0.asleep } }

  /// Awake and in a step that moves or acts, over the hours the cat is up.
  public func activeShare(from: Double = 8, to: Double = 22) -> Double {
    let day = segments.filter { (from..<to).contains(hour($0.start)) }
    let total = day.reduce(0) { $0 + $1.length }
    let active = day.filter { !$0.asleep && !Self.quiet.contains($0.step) }
      .reduce(0) { $0 + $1.length }
    return active / max(total, 1)
  }

  // MARK: - Episodes

  /// Consecutive segments of one group, as the cat lives them.
  public var episodes: [CatSegment] {
    var out: [CatSegment] = []
    for segment in segments {
      if var last = out.last, last.group == segment.group {
        last.end = segment.end
        out[out.count - 1] = last
      } else {
        out.append(segment)
      }
    }
    return out
  }

  public func lengths(of group: CatActivityGroup) -> [Double] {
    episodes.filter { $0.group == group }.map(\.length).sorted()
  }

  public static func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    return sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
  }

  // MARK: - Repetition

  /// Moves to the same step it just played, and to the same group, as a share of all moves.
  public var stepRepeats: Int {
    zip(segments, segments.dropFirst()).filter { $0.step == $1.step && $0.asleep == $1.asleep }
      .count
  }

  /// Short stays that go straight back: A, B for under `within` seconds, A again.
  public func flipFlops(within: Double = 8) -> Int {
    let e = episodes
    guard e.count > 2 else { return 0 }
    return (1..<(e.count - 1)).filter {
      e[$0].length < within && e[$0 - 1].group == e[$0 + 1].group
    }.count
  }

  /// Shannon entropy, in bits, of the time spent per step in `hour` (0 to 23) of the day.
  public func entropy(hour: Int) -> Double {
    var time: [CatActivityStep: Double] = [:]
    for s in segments where Int(self.hour(s.start)) == hour { time[s.step, default: 0] += s.length }
    let total = time.values.reduce(0, +)
    guard total > 0 else { return 0 }
    return -time.values.map { $0 / total }.map { $0 > 0 ? $0 * log2($0) : 0 }.reduce(0, +)
  }

  /// How many different steps began in `hour`, and how many of them are not quiet ones.
  public func distinctSteps(hour: Int, visible: Bool = false) -> Int {
    Set(
      segments.filter {
        Int(self.hour($0.start)) == hour && !$0.asleep
          && (!visible || !Self.quiet.contains($0.step))
      }.map(\.step)
    ).count
  }

  /// The longest stretch awake with nothing but quiet steps, in seconds.
  public var longestDull: Double {
    var best = 0.0
    var run = 0.0
    for s in segments {
      if !s.asleep && Self.quiet.contains(s.step) { run += s.length } else { run = 0 }
      best = max(best, run)
    }
    return best
  }

  public func count(of step: CatActivityStep) -> Int {
    segments.filter { $0.step == step }.count
  }

  // MARK: - Report

  public func report(_ title: String) -> String {
    var lines = ["== \(title)"]
    let groups = CatActivityGroup.allCases.map {
      "\($0.rawValue) \(Int((share(of: $0) * 100).rounded()))%"
    }
    lines.append("time: " + groups.joined(separator: ", "))
    lines.append(
      "asleep \(pct(asleepShare)), active when up (08-22) \(pct(activeShare())), longest dull stretch \(Int(longestDull / 60)) min"
    )
    let eps = episodes.filter { !$0.asleep }
    lines.append("episodes: \(eps.count) awake, \(episodes.count) in all")
    for group in CatActivityGroup.allCases {
      let l = lengths(of: group)
      guard !l.isEmpty else { continue }
      lines.append(
        "  \(group.rawValue): n=\(l.count) median \(Int(Self.percentile(l, 0.5))) s p90 \(Int(Self.percentile(l, 0.9))) s"
      )
    }
    lines.append(
      "repeats: same step \(stepRepeats) of \(segments.count), flip-flops \(flipFlops())"
    )
    let hours = (8..<22).map { entropy(hour: $0) }
    let distinct = (8..<22).map { distinctSteps(hour: $0) }
    let visible = (8..<22).map { distinctSteps(hour: $0, visible: true) }
    lines.append(
      "8-22h per hour: entropy "
        + String(format: "%.2f", hours.reduce(0, +) / Double(hours.count))
        + " bits, distinct steps \(distinct.min() ?? 0)-\(distinct.max() ?? 0), visible steps \(visible.min() ?? 0)-\(visible.max() ?? 0)"
    )
    let used = Set(segments.map(\.step))
    let unused = CatActivityStep.allCases.filter { !used.contains($0) }.map(\.rawValue)
    lines.append("steps never played: " + (unused.isEmpty ? "none" : unused.joined(separator: " ")))
    return lines.joined(separator: "\n")
  }

  private func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
}
