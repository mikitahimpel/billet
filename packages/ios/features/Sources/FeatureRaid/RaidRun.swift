import Foundation
import RaidInterface

/// One run of the cat at the jar, a tick at a time. It is a pure function of the board, the level and the
/// inputs: no clock and no dice, so the list of inputs replays the run exactly on any phone.
public struct RaidRun: Equatable, Sendable {
  public enum Mode: Equatable, Sendable {
    case free
    case jumping(from: RaidPoint, to: RaidPoint, left: Int)
    /// Leaping back from a cucumber, then the fright wearing off.
    case startled(from: RaidPoint, to: RaidPoint, left: Int)
    case inBox(defence: Int, left: Int)
    case riding(defence: Int, left: Int)
    /// Caught moving under the lamp and carried back to where she started.
    case carried(from: RaidPoint, left: Int)
  }

  /// What happened in a tick that the screen may want to mark with a sound or a haptic.
  public enum Happening: Equatable, Sendable {
    case jumped, landed, startled, boxed, rode, squeaked, caught, sniffed(found: Int), got, timeUp
  }

  public let board: RaidBoard
  public let level: RaidLevel

  public private(set) var cat: RaidPoint
  /// Radians, zero facing +x.
  public private(set) var heading: Double
  /// The piece she stands on; nil on the floor.
  public private(set) var on: String?
  public private(set) var mode: Mode = .free
  public private(set) var tick = 0
  public private(set) var sniffsLeft = RaidRules.sniffs
  /// Hidden defences she has found, by going off or by a sniff.
  public private(set) var revealed: Set<Int> = []
  public private(set) var lampLeft = 0
  /// Ticks she has stood still at the jar.
  public private(set) var pawing = 0
  public private(set) var closest: Double
  public private(set) var outcome: RaidOutcome?
  public private(set) var happenings: [Happening] = []

  private var jumpRest = 0
  private var lampGrace = 0
  /// Cucumbers that went off; a cat is fooled once.
  private var spent: Set<Int> = []
  /// Ticks a defence still leaves her alone.
  private var immune: [Int: Int] = [:]
  /// Squeaky boards she is standing on, so one step is one squeak.
  private var treading: Set<Int> = []

  public init(board: RaidBoard, level: RaidLevel) {
    self.board = board
    self.level = level
    cat = board.start
    heading = atan2(level.jar.z - board.start.z, level.jar.x - board.start.x)
    closest = board.start.distance(to: level.jar)
  }

  public var isOver: Bool { outcome != nil }
  public var secondsLeft: Double {
    Double(max(0, RaidRules.ticks - tick)) / Double(RaidRules.tickRate)
  }
  public var lampIsOn: Bool { lampLeft > 0 }
  /// The piece the jar stands on; nil on the floor.
  public var jarPiece: String? { board.top(at: level.jar)?.id }

  /// Whether the runner sees `defence` now.
  public func shows(_ defence: RaidDefence) -> Bool {
    !defence.isHidden || revealed.contains(defence.id)
  }

  /// Where a vacuum is at this tick: to and fro along its line at a steady pace.
  public func vacuumPlace(_ defence: RaidDefence) -> RaidPoint {
    guard case .vacuum(let to) = defence.kind else { return defence.at }
    let length = defence.at.distance(to: to)
    guard length > 1e-6 else { return defence.at }
    let travelled = Double(tick) / Double(RaidRules.tickRate) * RaidRules.vacuumSpeed
    let lap = travelled.truncatingRemainder(dividingBy: 2 * length)
    return defence.at.toward(to, share: (lap <= length ? lap : 2 * length - lap) / length)
  }

  /// The whole run from its inputs; inputs past the end are not read.
  public static func replay(board: RaidBoard, level: RaidLevel, inputs: [RaidInput]) -> RaidRun {
    var run = RaidRun(board: board, level: level)
    for input in inputs where !run.isOver { run.step(input) }
    return run
  }

  public mutating func step(_ input: RaidInput) {
    happenings = []
    guard outcome == nil else { return }
    tick += 1
    jumpRest = max(0, jumpRest - 1)
    lampLeft = max(0, lampLeft - 1)
    lampGrace = max(0, lampGrace - 1)
    immune = immune.compactMapValues { $0 > 1 ? $0 - 1 : nil }

    if input.sniff { sniff() }

    switch mode {
    case .free:
      moveFreely(input)
    case .jumping(let from, let to, let left):
      cat = arc(from, to, left: left, of: RaidRules.jumpTicks)
      if left <= 1 {
        land(at: to)
      } else {
        mode = .jumping(from: from, to: to, left: left - 1)
      }
    case .startled(let from, let to, let left):
      let leap = RaidRules.startleTicks * 2 / 5
      let flown = RaidRules.startleTicks - left + 1
      cat = from.toward(to, share: min(1, Double(flown) / Double(leap)))
      if left <= 1 {
        on = board.top(at: cat)?.id
        mode = .free
      } else {
        mode = .startled(from: from, to: to, left: left - 1)
      }
    case .inBox(let defence, let left):
      if left <= 1 {
        immune[defence] = RaidRules.immuneTicks
        mode = .free
      } else {
        mode = .inBox(defence: defence, left: left - 1)
      }
    case .riding(let defence, let left):
      if let vacuum = level.defences.first(where: { $0.id == defence }) {
        cat = board.clamped(vacuumPlace(vacuum))
      }
      if left <= 1 {
        immune[defence] = RaidRules.immuneTicks
        mode = .free
      } else {
        mode = .riding(defence: defence, left: left - 1)
      }
    case .carried(let from, let left):
      let share = 1 - Double(left - 1) / Double(RaidRules.carriedTicks)
      cat = from.toward(board.start, share: share)
      if left <= 1 {
        on = nil
        mode = .free
      } else {
        mode = .carried(from: from, left: left - 1)
      }
    }

    closest = min(closest, cat.distance(to: level.jar))
    if outcome == nil, tick >= RaidRules.ticks {
      outcome = .kept(closest: closest)
      happenings.append(.timeUp)
    }
  }

  private mutating func sniff() {
    guard sniffsLeft > 0 else { return }
    sniffsLeft -= 1
    let found = level.defences.filter {
      $0.isHidden && !revealed.contains($0.id) && $0.at.distance(to: cat) <= RaidRules.sniffRadius
    }
    revealed.formUnion(found.map(\.id))
    happenings.append(.sniffed(found: found.count))
  }

  private mutating func moveFreely(_ input: RaidInput) {
    let before = cat
    var speed = 0.0
    if let target = input.steer {
      let distance = cat.distance(to: target)
      if distance > RaidRules.stillWithin {
        heading = atan2(target.z - cat.z, target.x - cat.x)
        speed = RaidRules.runSpeed * min(1, distance / RaidRules.fullSpeedAt)
      }
    }

    if input.jump, jumpRest == 0 {
      let to = board.clamped(
        RaidPoint(
          x: cat.x + cos(heading) * RaidRules.jumpLength,
          z: cat.z + sin(heading) * RaidRules.jumpLength))
      mode = .jumping(from: cat, to: to, left: RaidRules.jumpTicks)
      pawing = 0
      happenings.append(.jumped)
      return
    }

    var step = RaidPoint(
      x: cos(heading) * speed / Double(RaidRules.tickRate),
      z: sin(heading) * speed / Double(RaidRules.tickRate))
    if on == nil, let pull = boxPull() {
      step.x += pull.x
      step.z += pull.z
    }
    walk(by: step)

    let moved = cat.distance(to: before) * Double(RaidRules.tickRate)
    if lampLeft > 0, lampGrace == 0, moved > 1e-6 {
      mode = .carried(from: cat, left: RaidRules.carriedTicks)
      lampLeft = 0
      pawing = 0
      happenings.append(.caught)
      return
    }
    if on == nil { meetDefences(speed: moved) }
    guard mode == .free else {
      pawing = 0
      return
    }
    paw(moved: moved)
  }

  /// Moves her by `step`, sliding along what she cannot walk through. On a piece she walks its top and steps
  /// down off its edge; on the floor a piece taller than a step is a wall.
  private mutating func walk(by step: RaidPoint) {
    for axis in [RaidPoint(x: step.x, z: 0), RaidPoint(x: 0, z: step.z)] {
      let next = board.clamped(RaidPoint(x: cat.x + axis.x, z: cat.z + axis.z))
      if let here = on {
        if board.piece(here)?.contains(next) == true {
          cat = next
        } else if let other = board.top(at: next) {
          let drop = (board.piece(here)?.height ?? 0) - other.height
          if drop > -RaidRules.stepOver {
            cat = next
            on = other.id
          }
        } else {
          cat = next
          on = nil
        }
      } else if !board.pieces.contains(where: {
        !$0.isLow && $0.contains(next, margin: RaidRules.catRadius)
      }) {
        cat = next
      }
    }
  }

  private mutating func land(at point: RaidPoint) {
    cat = point
    on = board.top(at: point)?.id
    if on == nil, let wall = board.pieces.first(where: {
      !$0.isLow && $0.contains(point, margin: RaidRules.catRadius)
    }) {
      // She came down against a piece's side, not on its top: she ends up on it.
      on = wall.id
      cat = RaidPoint(
        x: min(max(point.x, wall.centre.x - wall.halfX), wall.centre.x + wall.halfX),
        z: min(max(point.z, wall.centre.z - wall.halfZ), wall.centre.z + wall.halfZ))
    }
    mode = .free
    jumpRest = RaidRules.jumpRestTicks
    happenings.append(.landed)
    if on == nil { meetDefences(speed: RaidRules.runSpeed) }
  }

  /// The tug of the nearest box in reach, as a step for this tick.
  private func boxPull() -> RaidPoint? {
    let boxes = level.defences.filter {
      $0.kind == .box && immune[$0.id] == nil
        && $0.at.distance(to: cat) < RaidRules.boxPull
    }
    guard let box = boxes.min(by: { $0.at.distance(to: cat) < $1.at.distance(to: cat) }) else {
      return nil
    }
    let distance = box.at.distance(to: cat)
    guard distance > 1e-9 else { return nil }
    let pace = RaidRules.boxPullSpeed / Double(RaidRules.tickRate)
    return RaidPoint(x: (box.at.x - cat.x) / distance * pace, z: (box.at.z - cat.z) / distance * pace)
  }

  /// What the floor does to her where she now stands. `speed` is how fast she got here, in metres a second.
  private mutating func meetDefences(speed: Double) {
    var stillTreading: Set<Int> = []
    for defence in level.defences where immune[defence.id] == nil {
      switch defence.kind {
      case .vacuum:
        guard vacuumPlace(defence).distance(to: cat) < RaidRules.vacuumRadius + RaidRules.catRadius
        else { continue }
        mode = .riding(defence: defence.id, left: RaidRules.rideTicks)
        happenings.append(.rode)
        return
      case .box:
        guard defence.at.distance(to: cat) < RaidRules.boxCatch else { continue }
        cat = defence.at
        mode = .inBox(defence: defence.id, left: RaidRules.boxTicks)
        happenings.append(.boxed)
        return
      case .cucumber:
        guard !spent.contains(defence.id),
          defence.at.distance(to: cat) < RaidRules.cucumberTrigger
        else { continue }
        spent.insert(defence.id)
        revealed.insert(defence.id)
        let to = board.clamped(cat.away(from: defence.at, by: RaidRules.startleLeap))
        mode = .startled(from: cat, to: to, left: RaidRules.startleTicks)
        happenings.append(.startled)
        return
      case .squeakyBoard:
        guard defence.at.distance(to: cat) < RaidRules.boardRadius else { continue }
        stillTreading.insert(defence.id)
        guard !treading.contains(defence.id), speed > RaidRules.creepSpeed else { continue }
        revealed.insert(defence.id)
        lampLeft = RaidRules.lampTicks
        lampGrace = RaidRules.lampGraceTicks
        happenings.append(.squeaked)
      }
    }
    treading = stillTreading
  }

  private mutating func paw(moved: Double) {
    let atJar = cat.distance(to: level.jar) < RaidRules.pawReach && on == jarPiece
    guard atJar, moved < RaidRules.creepSpeed / 2 else {
      pawing = 0
      return
    }
    pawing += 1
    if pawing >= RaidRules.pawTicks {
      outcome = .got(seconds: Double(tick) / Double(RaidRules.tickRate))
      happenings.append(.got)
    }
  }

  private func arc(_ from: RaidPoint, _ to: RaidPoint, left: Int, of total: Int) -> RaidPoint {
    from.toward(to, share: 1 - Double(left - 1) / Double(total))
  }
}
