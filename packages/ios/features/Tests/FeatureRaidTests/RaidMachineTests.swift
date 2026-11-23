import DecorInterface
import RaidInterface
import Testing

@testable import FeatureRaid

private let board = RaidBoard(pieces: [], start: RaidPoint(x: -0.4, z: 0))
private let jar = RaidPoint(x: 0.3, z: 0)
private let level = RaidLevel(jar: jar)
private let round = RaidMachine.Round(board: board, level: level, round: 0)

private func draft(_ change: (inout RaidMachine.Draft) -> Void = { _ in }) -> RaidMachine.State {
  var draft = RaidMachine.Draft(board: board)
  change(&draft)
  return .setting(draft)
}

private func finished() -> RaidMachine.Finished {
  let inputs = Array(repeating: RaidInput.idle, count: RaidRules.ticks)
  let run = RaidRun.replay(board: board, level: level, inputs: inputs)
  return RaidMachine.Finished(round: round, inputs: inputs, run: run, outcome: run.outcome!)
}

private func step(_ state: RaidMachine.State, _ events: RaidMachine.Event...) -> RaidMachine.State {
  events.reduce(state) { RaidMachine.transition($0, $1).0 }
}

@Suite struct RaidMachineTests {
  @Test func theKeeperPutsDownTheJarThenDefencesUpToTheLimit() {
    let set = step(
      draft(), .tapped(jar), .chose(.box), .tapped(RaidPoint(x: 0, z: 0)), .chose(.cucumber),
      .tapped(RaidPoint(x: 0.1, z: 0.1)), .chose(.vacuum), .tapped(RaidPoint(x: 0, z: -0.3)),
      .tapped(RaidPoint(x: 0, z: 0.3)), .chose(.squeakyBoard), .tapped(RaidPoint(x: 0.2, z: 0.2)))
    guard case .setting(let draft) = set else {
      Issue.record("\(set)")
      return
    }
    #expect(draft.jar == jar)
    #expect(draft.defences.map(\.id) == [1, 2, 3])
    #expect(draft.defences.last?.kind == .vacuum(to: RaidPoint(x: 0, z: 0.3)))
    #expect(draft.canHandOver)
    #expect(!draft.hasRoom)
  }

  @Test func aTapOutsideTheRoomLandsInsideIt() {
    guard case .setting(let draft) = step(draft(), .tapped(RaidPoint(x: 3, z: -3))) else { return }
    #expect(draft.jar == board.clamped(RaidPoint(x: 3, z: -3)))
  }

  @Test func aDefenceCanBeTakenBack() {
    let set = step(draft(), .chose(.box), .tapped(RaidPoint(x: 0, z: 0)), .removed(1))
    #expect(set == draft { $0.tool = .box; $0.nextID = 2 })
  }

  @Test func aLevelWithAProblemIsNotHandedOver() {
    let unfair = step(draft(), .tapped(RaidPoint(x: -0.35, z: 0)))
    #expect(step(unfair, .handedOver) == unfair)
    #expect(step(draft(), .handedOver) == draft())
  }

  @Test func aRoundRunsFromHandoverToItsOutcomeAndSwaps() {
    var state = step(draft(), .tapped(jar), .handedOver)
    #expect(state == .handover(round))
    state = step(state, .started)
    var felt: [RaidMachine.Output] = []
    for _ in 0..<RaidRules.ticks {
      let (next, outputs) = RaidMachine.transition(state, .tick(.idle))
      state = next
      felt += outputs
    }
    #expect(state == .finished(finished()))
    #expect(felt == [.felt(.timeUp)])
    #expect(step(state, .again) == draft { $0.round = 1 })
  }

  @Test func theReplayStepsThroughTheSameRunAndEnds() {
    let done = finished()
    var state = step(.finished(done), .watch)
    for _ in 0..<RaidRules.ticks { state = step(state, .replayTick) }
    guard case .replaying(let replay) = state else {
      Issue.record("\(state)")
      return
    }
    #expect(replay.run == done.run)
    #expect(step(state, .replayTick) == .finished(done))
    #expect(step(state, .replayEnded) == .finished(done))
    #expect(step(state, .again) == draft { $0.round = 1 })
  }

  static let rejected: [(RaidMachine.State, [RaidMachine.Event])] = {
    let setting: [RaidMachine.Event] = [.chose(.box), .tapped(jar), .removed(1), .handedOver]
    let session = RaidMachine.Session(
      round: round, run: RaidRun(board: board, level: level), inputs: [])
    let done = finished()
    let replay = RaidMachine.Replay(
      finished: done, run: RaidRun(board: board, level: level), index: 0)
    return [
      (draft(), [.started, .tick(.idle), .watch, .replayTick, .replayEnded, .again]),
      (.handover(round), setting + [.tick(.idle), .watch, .replayTick, .replayEnded, .again]),
      (.running(session), setting + [.started, .watch, .replayTick, .replayEnded, .again]),
      (.finished(done), setting + [.started, .tick(.idle), .replayTick, .replayEnded]),
      (.replaying(replay), setting + [.started, .tick(.idle), .watch]),
    ]
  }()

  @Test(arguments: rejected)
  func eventsOutOfPlaceChangeNothing(state: RaidMachine.State, events: [RaidMachine.Event]) {
    for event in events {
      let (next, outputs) = RaidMachine.transition(state, event)
      #expect(next == state, "\(event)")
      #expect(outputs.isEmpty)
    }
  }
}

@Suite struct RaidBoardLayoutTests {
  @Test func theUntouchedRoomIsItsOwnFurnitureWithTheRugLyingFlat() {
    let board = RaidBoard(layout: DecorLayout())
    let ids = Set(board.pieces.map(\.id))
    #expect(ids.contains("base-cattree"))
    #expect(ids.contains("base-donutbed"))
    #expect(board.pieces.first { $0.id == "base-rug" }?.isFlat == true)
    #expect(board.pieces.allSatisfy { !$0.id.contains("bedroom") })
    #expect(board.top(at: board.start) == nil)
    #expect(abs(board.start.x) < RaidRules.reach && abs(board.start.z) < RaidRules.reach)
  }

  @Test func aLevelCanAlwaysBeSetInTheUntouchedRoom() {
    let board = RaidBoard(layout: DecorLayout())
    let corners = [(-0.4, -0.4), (0.4, -0.4), (-0.4, 0.4), (0.4, 0.4)].map(RaidPoint.init)
    #expect(corners.contains { RaidLevel(jar: $0).problem(on: board) == nil })
  }
}
