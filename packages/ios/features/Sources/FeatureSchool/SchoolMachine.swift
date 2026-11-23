import BilletKit
import Foundation
import SchoolInterface

/// The cat school of one pair: what the cat knows, and the sheet's screens over it. The lesson and
/// the routine are machines of their own, run here under the screen that shows them.
public enum SchoolMachine: Machine {
  public enum Screen: Equatable, Sendable {
    case closed
    case list
    case lesson(LessonMachine.State)
    case routine(RoutineMachine.State)
    /// The partner's last routine is playing in the room.
    case watching(RoutineTake)
  }

  /// A star on its way to the room.
  public enum Saving: Equatable, Sendable {
    case idle
    case saving(SchoolTrick, star: Int)
    /// The room did not answer. The star is kept here and sent again on `retrySave`.
    case failed(SchoolTrick, star: Int)
  }

  public struct Desk: Equatable, Sendable {
    public var book: SchoolBook
    public var screen: Screen
    public var saving: Saving

    public init(book: SchoolBook, screen: Screen = .closed, saving: Saving = .idle) {
      self.book = book
      self.screen = screen
      self.saving = saving
    }

    func showing(_ screen: Screen) -> Desk {
      var next = self
      next.screen = screen
      return next
    }
  }

  public enum State: Equatable, Sendable {
    /// No school: the flag is off or there is no partner.
    case unavailable
    case loading
    case ready(Desk)

    public var desk: Desk? {
      switch self {
      case .unavailable, .loading: nil
      case .ready(let desk): desk
      }
    }

    public var isOpen: Bool {
      switch desk?.screen {
      case nil, .closed: false
      case .list, .lesson, .routine, .watching: true
      }
    }
  }

  public enum Event: Equatable, Sendable {
    case enabled
    case disabled
    case fetched(SchoolBook)
    case refresh
    case opened
    case dismissed
    case back
    /// Ask for a trick the cat knows. `roll` is from 0 up to 1.
    case ask(SchoolTrick, roll: Double)
    case teach(SchoolTrick, seed: UInt64)
    case lesson(LessonMachine.Event)
    case saved(SchoolBook)
    case saveFailed
    case retrySave
    case buildRoutine
    case routine(RoutineMachine.Event)
    /// The room took the routine and answered with the school after it.
    case routineSent(SchoolBook)
    case watchPartner
  }

  public enum Output: Equatable, Sendable {
    case fetch
    case perform(SchoolMove)
    case play([SchoolMove])
    case teach(SchoolTrick, star: Int)
    case send(RoutineTake)
    /// The cat did a trick it was asked for.
    case count(SchoolTrick)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.unavailable, .enabled):
      return (.loading, [.fetch])
    case (.unavailable, .disabled), (.unavailable, .fetched), (.unavailable, .refresh),
      (.unavailable, .opened), (.unavailable, .dismissed), (.unavailable, .back),
      (.unavailable, .ask), (.unavailable, .teach), (.unavailable, .lesson),
      (.unavailable, .saved), (.unavailable, .saveFailed), (.unavailable, .retrySave),
      (.unavailable, .buildRoutine), (.unavailable, .routine), (.unavailable, .routineSent),
      (.unavailable, .watchPartner):
      return (state, [])

    case (.loading, .disabled), (.ready, .disabled):
      return (.unavailable, [])
    case (.loading, .enabled), (.ready, .enabled):
      return (state, [])

    case (.loading, .fetched(let book)):
      return (.ready(Desk(book: book)), [])
    case (.loading, .refresh):
      return (state, [.fetch])
    case (.loading, .opened), (.loading, .dismissed), (.loading, .back), (.loading, .ask),
      (.loading, .teach), (.loading, .lesson), (.loading, .saved), (.loading, .saveFailed),
      (.loading, .retrySave), (.loading, .buildRoutine), (.loading, .routine),
      (.loading, .routineSent), (.loading, .watchPartner):
      return (state, [])

    case (.ready(var desk), .fetched(let book)):
      desk.book = book
      return (.ready(desk), [])
    case (.ready, .refresh):
      return (state, [.fetch])

    case (.ready(let desk), .opened):
      switch desk.screen {
      case .closed: return (.ready(desk.showing(.list)), [.fetch])
      case .list, .lesson, .routine, .watching: return (state, [])
      }
    case (.ready(let desk), .dismissed):
      return (.ready(desk.showing(.closed)), [])
    case (.ready(let desk), .back):
      switch desk.screen {
      case .closed, .list: return (state, [])
      case .lesson, .routine, .watching: return (.ready(desk.showing(.list)), [])
      }

    case (.ready(let desk), .ask(let trick, let roll)):
      switch desk.screen {
      case .list:
        guard let skill = desk.book.skills[trick] else { return (state, []) }
        guard skill.lands(roll: roll) else {
          return (state, [.perform(.flub(SchoolFlub(turn: Int(roll * 1000))))])
        }
        return (state, [.perform(.trick(trick)), .count(trick)])
      case .closed, .lesson, .routine, .watching:
        return (state, [])
      }

    case (.ready(let desk), .teach(let trick, let seed)):
      switch desk.screen {
      case .list:
        guard let star = desk.book.nextStar(of: trick), !desk.saving.isBusy else {
          return (state, [])
        }
        let plan = LessonPlan(trick: trick, star: star, seed: seed)
        return (.ready(desk.showing(.lesson(LessonMachine.start(plan)))), [])
      case .closed, .lesson, .routine, .watching:
        return (state, [])
      }

    case (.ready(var desk), .lesson(let event)):
      switch desk.screen {
      case .lesson(let lesson):
        let (next, outputs) = LessonMachine.transition(lesson, event)
        desk.screen = .lesson(next)
        var out = outputs.map { output -> Output in
          switch output {
          case .perform(let move): .perform(move)
          }
        }
        if case .passed(let run) = next, next != lesson {
          desk.saving = .saving(run.plan.trick, star: run.plan.star)
          out.append(.teach(run.plan.trick, star: run.plan.star))
        }
        return (.ready(desk), out)
      case .closed, .list, .routine, .watching:
        return (state, [])
      }

    case (.ready(var desk), .saved(let book)):
      desk.book = book
      desk.saving = .idle
      return (.ready(desk), [])
    case (.ready(var desk), .saveFailed):
      switch desk.saving {
      case .saving(let trick, let star):
        desk.saving = .failed(trick, star: star)
        return (.ready(desk), [])
      case .idle, .failed:
        return (state, [])
      }
    case (.ready(var desk), .retrySave):
      switch desk.saving {
      case .failed(let trick, let star):
        desk.saving = .saving(trick, star: star)
        return (.ready(desk), [.teach(trick, star: star)])
      case .idle, .saving:
        return (state, [])
      }

    case (.ready(let desk), .buildRoutine):
      switch desk.screen {
      case .list:
        guard desk.book.canBuildRoutine else { return (state, []) }
        return (.ready(desk.showing(.routine(.picking([])))), [])
      case .closed, .lesson, .routine, .watching:
        return (state, [])
      }

    case (.ready(let desk), .routine(let event)):
      return routine(desk, event) ?? (state, [])
    case (.ready(var desk), .routineSent(let book)):
      desk.book = book
      return routine(desk, .sent) ?? (.ready(desk), [])

    case (.ready(let desk), .watchPartner):
      switch desk.screen {
      case .list:
        guard let take = desk.book.partner else { return (state, []) }
        return (.ready(desk.showing(.watching(take))), [.play(take.moves)])
      case .closed, .lesson, .routine, .watching:
        return (state, [])
      }
    }
  }

  /// Nil when no routine is on the screen.
  private static func routine(_ desk: Desk, _ event: RoutineMachine.Event) -> (State, [Output])? {
    switch desk.screen {
    case .routine(let routine):
      if case .pick(let trick) = event, desk.book.skills[trick] == nil { return nil }
      let (next, outputs) = RoutineMachine.transition(routine, event)
      let out = outputs.map { output -> Output in
        switch output {
        case .play(let moves): .play(moves)
        case .send(let take): .send(take)
        }
      }
      return (.ready(desk.showing(.routine(next))), out)
    case .closed, .list, .lesson, .watching:
      return nil
    }
  }
}

extension SchoolMachine.Saving {
  public var isBusy: Bool {
    switch self {
    case .idle: false
    case .saving, .failed: true
    }
  }
}
