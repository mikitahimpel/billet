import BilletKit
import RaidInterface

/// A round of the raid on one phone, passed from hand to hand: the keeper sets the level, the runner makes
/// the run, both watch it again, and the roles swap.
public enum RaidMachine: Machine {
  /// What the keeper's next tap on the floor puts down.
  public enum Tool: Equatable, Sendable {
    case jar, box, cucumber, squeakyBoard
    /// The first tap of a vacuum is where it starts.
    case vacuum
    /// The second is where it turns round.
    case vacuumEnd(from: RaidPoint)
  }

  public struct Draft: Equatable, Sendable {
    public let board: RaidBoard
    public var jar: RaidPoint?
    public var defences: [RaidDefence] = []
    public var tool: Tool = .jar
    /// Rounds finished on this board since the screen opened.
    public var round = 0
    var nextID = 1

    public init(board: RaidBoard) { self.board = board }

    public var level: RaidLevel? { jar.map { RaidLevel(jar: $0, defences: defences) } }
    public var problem: RaidLevel.Problem? { level?.problem(on: board) }
    public var canHandOver: Bool { level != nil && problem == nil }
    public var hasRoom: Bool { defences.count < RaidRules.maxDefences }
  }

  public struct Round: Equatable, Sendable {
    public let board: RaidBoard
    public let level: RaidLevel
    public let round: Int
  }

  public struct Session: Equatable, Sendable {
    public let round: Round
    public var run: RaidRun
    public var inputs: [RaidInput]
  }

  public struct Finished: Equatable, Sendable {
    public let round: Round
    public let inputs: [RaidInput]
    public let run: RaidRun
    public let outcome: RaidOutcome
  }

  public struct Replay: Equatable, Sendable {
    public let finished: Finished
    public var run: RaidRun
    public var index: Int
  }

  public enum State: Equatable, Sendable {
    case setting(Draft)
    /// The level is set and the phone is on its way to the runner.
    case handover(Round)
    case running(Session)
    case finished(Finished)
    case replaying(Replay)
  }

  public enum Event: Equatable, Sendable {
    case chose(Tool)
    case tapped(RaidPoint)
    case removed(Int)
    case handedOver
    case started
    case tick(RaidInput)
    case watch
    case replayTick
    case replayEnded
    /// A new round on the same board, the other way round.
    case again
  }

  public enum Output: Equatable, Sendable {
    case felt(RaidRun.Happening)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.setting(var draft), .chose(let tool)):
      draft.tool = tool
      return (.setting(draft), [])

    case (.setting(var draft), .tapped(let point)):
      let place = draft.board.clamped(point)
      switch draft.tool {
      case .jar:
        draft.jar = place
      case .box:
        add(.box, at: place, to: &draft)
      case .cucumber:
        add(.cucumber, at: place, to: &draft)
      case .squeakyBoard:
        add(.squeakyBoard, at: place, to: &draft)
      case .vacuum:
        if draft.hasRoom { draft.tool = .vacuumEnd(from: place) }
      case .vacuumEnd(let from):
        add(.vacuum(to: place), at: from, to: &draft)
        draft.tool = .vacuum
      }
      return (.setting(draft), [])

    case (.setting(var draft), .removed(let id)):
      draft.defences.removeAll { $0.id == id }
      return (.setting(draft), [])

    case (.setting(let draft), .handedOver):
      guard let level = draft.level, draft.problem == nil else { return (state, []) }
      return (.handover(Round(board: draft.board, level: level, round: draft.round)), [])

    case (.handover(let round), .started):
      let run = RaidRun(board: round.board, level: round.level)
      return (.running(Session(round: round, run: run, inputs: [])), [])

    case (.running(var session), .tick(let input)):
      session.run.step(input)
      session.inputs.append(input)
      let felt = session.run.happenings.map(Output.felt)
      if let outcome = session.run.outcome {
        let finished = Finished(
          round: session.round, inputs: session.inputs, run: session.run, outcome: outcome)
        return (.finished(finished), felt)
      }
      return (.running(session), felt)

    case (.finished(let finished), .watch):
      let run = RaidRun(board: finished.round.board, level: finished.round.level)
      return (.replaying(Replay(finished: finished, run: run, index: 0)), [])

    case (.replaying(var replay), .replayTick):
      guard replay.index < replay.finished.inputs.count else {
        return (.finished(replay.finished), [])
      }
      replay.run.step(replay.finished.inputs[replay.index])
      replay.index += 1
      return (.replaying(replay), [])

    case (.replaying(let replay), .replayEnded):
      return (.finished(replay.finished), [])

    case (.finished(let finished), .again):
      return (.setting(next(after: finished)), [])

    case (.replaying(let replay), .again):
      return (.setting(next(after: replay.finished)), [])

    case (.setting, .started), (.setting, .tick), (.setting, .watch), (.setting, .replayTick),
      (.setting, .replayEnded), (.setting, .again),
      (.handover, .chose), (.handover, .tapped), (.handover, .removed), (.handover, .handedOver),
      (.handover, .tick), (.handover, .watch), (.handover, .replayTick), (.handover, .replayEnded),
      (.handover, .again),
      (.running, .chose), (.running, .tapped), (.running, .removed), (.running, .handedOver),
      (.running, .started), (.running, .watch), (.running, .replayTick), (.running, .replayEnded),
      (.running, .again),
      (.finished, .chose), (.finished, .tapped), (.finished, .removed), (.finished, .handedOver),
      (.finished, .started), (.finished, .tick), (.finished, .replayTick),
      (.finished, .replayEnded),
      (.replaying, .chose), (.replaying, .tapped), (.replaying, .removed),
      (.replaying, .handedOver), (.replaying, .started), (.replaying, .tick), (.replaying, .watch):
      return (state, [])
    }
  }

  private static func next(after finished: Finished) -> Draft {
    var draft = Draft(board: finished.round.board)
    draft.round = finished.round.round + 1
    return draft
  }

  private static func add(_ kind: RaidDefence.Kind, at point: RaidPoint, to draft: inout Draft) {
    guard draft.hasRoom else { return }
    draft.defences.append(RaidDefence(id: draft.nextID, kind: kind, at: point))
    draft.nextID += 1
  }
}

public typealias RaidStore = Store<RaidMachine>

extension Store where M == RaidMachine {
  /// `feel` plays a happening as a haptic or a sound; the machine itself needs no other work done.
  @MainActor
  public static func raid(
    board: RaidBoard, feel: @escaping @Sendable (RaidRun.Happening) async -> Void = { _ in }
  ) -> RaidStore {
    Store(initial: .setting(RaidMachine.Draft(board: board))) { output in
      switch output {
      case .felt(let happening):
        await feel(happening)
        return nil
      }
    }
  }
}
