import RaidInterface
import Testing

@testable import FeatureRaid

private let empty = RaidBoard(pieces: [], start: RaidPoint(x: -0.4, z: 0))

private func run(
  _ level: RaidLevel, on board: RaidBoard = empty, ticks: Int = RaidRules.ticks,
  input: (RaidRun) -> RaidInput
) -> RaidRun {
  var run = RaidRun(board: board, level: level)
  for _ in 0..<ticks where !run.isOver { run.step(input(run)) }
  return run
}

/// Runs at `target` and lets go once near it.
private func head(for target: RaidPoint, within: Double = 0.03) -> (RaidRun) -> RaidInput {
  { $0.cat.distance(to: target) < within ? .idle : RaidInput(steer: target) }
}

@Suite struct RaidRunTests {
  let jar = RaidPoint(x: 0.3, z: 0)

  @Test func aStraightRunToAnUnguardedJarGetsIt() {
    let done = run(RaidLevel(jar: jar), input: head(for: jar))
    guard case .got(let seconds) = done.outcome else {
      Issue.record("\(String(describing: done.outcome))")
      return
    }
    #expect(seconds < 8)
  }

  @Test func standingStillTheKeeperKeepsIt() {
    let done = run(RaidLevel(jar: jar)) { _ in .idle }
    #expect(done.outcome == .kept(closest: 0.7))
    #expect(done.tick == RaidRules.ticks)
  }

  @Test func theSameInputsReplayTheSameRun() {
    let level = RaidLevel(
      jar: jar,
      defences: [
        RaidDefence(id: 1, kind: .cucumber, at: RaidPoint(x: 0, z: 0)),
        RaidDefence(id: 2, kind: .box, at: RaidPoint(x: 0.15, z: 0.05)),
        RaidDefence(
          id: 3, kind: .vacuum(to: RaidPoint(x: -0.1, z: 0.3)), at: RaidPoint(x: -0.1, z: -0.3)),
      ])
    var live = RaidRun(board: empty, level: level)
    var inputs: [RaidInput] = []
    while !live.isOver {
      let input = RaidInput(steer: jar, jump: live.tick % 50 == 49, sniff: live.tick == 10)
      inputs.append(input)
      live.step(input)
    }
    #expect(RaidRun.replay(board: empty, level: level, inputs: inputs) == live)
  }

  @Test func aCucumberSendsHerBackOnceAndShowsItself() {
    let cucumber = RaidDefence(id: 1, kind: .cucumber, at: RaidPoint(x: 0, z: 0))
    var leapt = 0
    var furthestBack = 0.0
    var live = RaidRun(board: empty, level: RaidLevel(jar: jar, defences: [cucumber]))
    #expect(!live.shows(cucumber))
    while !live.isOver {
      live.step(head(for: jar)(live))
      if live.happenings.contains(.startled) {
        leapt += 1
        furthestBack = live.cat.x
      }
    }
    #expect(leapt == 1)
    #expect(furthestBack < -0.05)
    #expect(live.shows(cucumber))
    #expect(live.outcome != .kept(closest: live.closest))
  }

  @Test func aBoxHoldsHerForItsTimeThenLetsHerPass() {
    let box = RaidDefence(id: 1, kind: .box, at: RaidPoint(x: 0, z: 0))
    var inBox = 0
    var live = RaidRun(board: empty, level: RaidLevel(jar: jar, defences: [box]))
    while !live.isOver {
      live.step(head(for: jar)(live))
      if case .inBox = live.mode { inBox += 1 }
    }
    #expect(inBox == RaidRules.boxTicks)
    if case .got = live.outcome {} else { Issue.record("she never left the box") }
  }

  @Test func runningWideOfABoxBeatsItsPull() {
    let box = RaidDefence(id: 1, kind: .box, at: RaidPoint(x: 0, z: 0.09))
    let done = run(RaidLevel(jar: jar, defences: [box]), input: head(for: jar))
    var boxed = false
    var live = RaidRun(board: empty, level: RaidLevel(jar: jar, defences: [box]))
    while !live.isOver {
      live.step(head(for: jar)(live))
      if live.happenings.contains(.boxed) { boxed = true }
    }
    #expect(!boxed)
    #expect(done.outcome == live.outcome)
  }

  @Test func runningOverASqueakyBoardAndOnIsCarriedBack() {
    let board = RaidDefence(id: 1, kind: .squeakyBoard, at: RaidPoint(x: 0, z: 0))
    var caught = false
    var live = RaidRun(board: empty, level: RaidLevel(jar: jar, defences: [board]))
    for _ in 0..<200 {
      live.step(RaidInput(steer: jar))
      if live.happenings.contains(.caught) { caught = true }
    }
    #expect(caught)
    #expect(live.shows(board))
  }

  @Test func freezingUnderTheLampIsSafe() {
    let board = RaidDefence(id: 1, kind: .squeakyBoard, at: RaidPoint(x: 0, z: 0))
    var caught = false
    var live = RaidRun(board: empty, level: RaidLevel(jar: jar, defences: [board]))
    while !live.isOver {
      live.step(live.lampIsOn ? .idle : head(for: jar)(live))
      if live.happenings.contains(.caught) { caught = true }
    }
    #expect(!caught)
    if case .got = live.outcome {} else { Issue.record("\(String(describing: live.outcome))") }
  }

  @Test func creepingOverASqueakyBoardIsQuiet() {
    let board = RaidDefence(id: 1, kind: .squeakyBoard, at: RaidPoint(x: 0, z: 0))
    var squeaked = false
    var live = RaidRun(board: empty, level: RaidLevel(jar: jar, defences: [board]))
    // A finger held a little ahead of her is a creep.
    for _ in 0..<RaidRules.ticks where !live.isOver {
      let ahead = RaidPoint(x: live.cat.x + 0.04, z: 0)
      live.step(live.cat.x < 0.27 ? RaidInput(steer: ahead) : .idle)
      if live.happenings.contains(.squeaked) { squeaked = true }
    }
    #expect(!squeaked)
    #expect(live.cat.x > 0.2)
  }

  @Test func touchingTheVacuumIsARide() {
    let vacuum = RaidDefence(
      id: 1, kind: .vacuum(to: RaidPoint(x: 0, z: 0.3)), at: RaidPoint(x: 0, z: -0.3))
    var riding = 0
    var live = RaidRun(board: empty, level: RaidLevel(jar: jar, defences: [vacuum]))
    // Stand in its path and wait.
    let wait = RaidPoint(x: 0, z: 0)
    for _ in 0..<600 {
      live.step(head(for: wait)(live))
      if case .riding = live.mode { riding += 1 }
    }
    #expect(riding >= RaidRules.rideTicks - 1)
  }

  @Test func aSniffFindsWhatIsHiddenNearbyAndRunsOut() {
    let near = RaidDefence(id: 1, kind: .cucumber, at: RaidPoint(x: -0.3, z: 0.1))
    let far = RaidDefence(id: 2, kind: .squeakyBoard, at: RaidPoint(x: 0.3, z: 0.3))
    var live = RaidRun(board: empty, level: RaidLevel(jar: jar, defences: [near, far]))
    live.step(RaidInput(sniff: true))
    #expect(live.happenings == [.sniffed(found: 1)])
    #expect(live.shows(near))
    #expect(!live.shows(far))
    for _ in 0..<5 { live.step(RaidInput(sniff: true)) }
    #expect(live.sniffsLeft == 0)
  }

  @Test func aTallPieceIsAWallOnTheFloorAndAFloorOnceJumpedOn() {
    let sofa = RaidPiece(
      id: "sofa", title: "Sofa", centre: RaidPoint(x: 0, z: 0), halfX: 0.1, halfZ: 0.3, height: 0.2)
    let room = RaidBoard(pieces: [sofa], start: RaidPoint(x: -0.4, z: 0))
    let onSofa = RaidPoint(x: 0.02, z: 0)
    let walked = run(RaidLevel(jar: onSofa), on: room, ticks: 300) { _ in RaidInput(steer: onSofa) }
    #expect(walked.on == nil)
    #expect(walked.cat.x < -0.1)

    let jumped = run(RaidLevel(jar: onSofa), on: room) { run in
      if run.on == "sofa" { return head(for: onSofa)(run) }
      return RaidInput(steer: onSofa, jump: run.cat.x > -0.25)
    }
    if case .got = jumped.outcome {} else { Issue.record("\(String(describing: jumped.outcome))") }
  }

  @Test func theJarOnAPieceIsOutOfReachFromTheFloor() {
    let table = RaidPiece(
      id: "table", title: "Table", centre: RaidPoint(x: 0.3, z: 0), halfX: 0.05, halfZ: 0.05,
      height: 0.2)
    let room = RaidBoard(pieces: [table], start: RaidPoint(x: -0.4, z: 0))
    // Pushing at the table's side gets her no nearer than its edge.
    let done = run(RaidLevel(jar: RaidPoint(x: 0.27, z: 0)), on: room) { run in
      run.tick < 200 ? RaidInput(steer: RaidPoint(x: 0.27, z: 0)) : .idle
    }
    #expect(done.cat.distance(to: RaidPoint(x: 0.27, z: 0)) < RaidRules.pawReach)
    if case .kept = done.outcome {} else { Issue.record("\(String(describing: done.outcome))") }
  }
}

@Suite struct RaidLevelTests {
  @Test func aLevelIsRefusedForWhatWouldMakeItUnfair() {
    let sofa = RaidPiece(
      id: "sofa", title: "Sofa", centre: RaidPoint(x: 0, z: 0.3), halfX: 0.1, halfZ: 0.1,
      height: 0.2)
    let room = RaidBoard(pieces: [sofa], start: RaidPoint(x: -0.4, z: 0))
    let jar = RaidPoint(x: 0.3, z: 0)
    #expect(RaidLevel(jar: RaidPoint(x: -0.3, z: 0)).problem(on: room) == .jarTooNearStart)
    let near = RaidDefence(id: 1, kind: .box, at: RaidPoint(x: -0.35, z: 0))
    #expect(RaidLevel(jar: jar, defences: [near]).problem(on: room) == .defenceNearStart(1))
    let onSofa = RaidDefence(id: 2, kind: .cucumber, at: RaidPoint(x: 0, z: 0.3))
    #expect(RaidLevel(jar: jar, defences: [onSofa]).problem(on: room) == .defenceOnFurniture(2))
    let vacuumEnd = RaidDefence(
      id: 3, kind: .vacuum(to: RaidPoint(x: -0.4, z: 0.05)), at: RaidPoint(x: 0.2, z: -0.3))
    #expect(RaidLevel(jar: jar, defences: [vacuumEnd]).problem(on: room) == .defenceNearStart(3))
    let four = (1...4).map { RaidDefence(id: $0, kind: .box, at: RaidPoint(x: 0.1, z: -0.3)) }
    #expect(RaidLevel(jar: jar, defences: four).problem(on: room) == .tooManyDefences)
    #expect(RaidLevel(jar: jar, defences: Array(four.prefix(3))).problem(on: room) == nil)
  }
}
