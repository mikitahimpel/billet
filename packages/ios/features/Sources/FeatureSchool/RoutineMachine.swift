import BilletKit
import Foundation
import SchoolInterface

/// A routine being put together, tried and sent to the partner.
public enum RoutineMachine: Machine {
  public enum State: Equatable, Sendable {
    case picking([SchoolTrick])
    /// The cat tried it; this is how the take went.
    case tried(RoutineTake)
    case sending(RoutineTake)
    case sent(RoutineTake)
    /// The room did not answer. The take is kept; sending again sends the same one.
    case failed(RoutineTake)

    public var picks: [SchoolTrick] {
      switch self {
      case .picking(let picks): picks
      case .tried(let take), .sending(let take), .sent(let take), .failed(let take):
        take.steps.map(\.trick)
      }
    }
  }

  public enum Event: Equatable, Sendable {
    case pick(SchoolTrick)
    case removeLast
    /// `rolls` has one number from 0 up to 1 for each pick; `stars` is how well each is known.
    case tryIt(rolls: [Double], stars: [SchoolTrick: Int], at: Date)
    case again
    case send
    case sent
    case sendFailed
  }

  public enum Output: Equatable, Sendable {
    case play([SchoolMove])
    case send(RoutineTake)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.picking(let picks), .pick(let trick)):
      guard picks.count < RoutineTake.length.upperBound else { return (state, []) }
      return (.picking(picks + [trick]), [])
    case (.picking(let picks), .removeLast):
      return (.picking(Array(picks.dropLast())), [])
    case (.picking(let picks), .tryIt(let rolls, let stars, let at)):
      guard RoutineTake.length.contains(picks.count), rolls.count == picks.count else {
        return (state, [])
      }
      let steps = zip(picks, rolls).map { trick, roll in
        RoutineTake.Step(
          trick: trick, landed: roll < TrickSkill.chance(stars: stars[trick] ?? 0))
      }
      let take = RoutineTake(steps: steps, at: at)
      return (.tried(take), [.play(take.moves)])
    case (.picking, .again), (.picking, .send), (.picking, .sent), (.picking, .sendFailed):
      return (state, [])

    case (.tried(let take), .again), (.failed(let take), .again), (.sent(let take), .again):
      return (.picking(take.steps.map(\.trick)), [])
    case (.tried(let take), .send), (.failed(let take), .send):
      return (.sending(take), [.send(take)])
    case (.tried, .pick), (.tried, .removeLast), (.tried, .tryIt), (.tried, .sent),
      (.tried, .sendFailed):
      return (state, [])

    case (.sending(let take), .sent):
      return (.sent(take), [])
    case (.sending(let take), .sendFailed):
      return (.failed(take), [])
    case (.sending, .pick), (.sending, .removeLast), (.sending, .tryIt), (.sending, .again),
      (.sending, .send):
      return (state, [])

    case (.sent, .pick), (.sent, .removeLast), (.sent, .tryIt), (.sent, .send), (.sent, .sent),
      (.sent, .sendFailed):
      return (state, [])
    case (.failed, .pick), (.failed, .removeLast), (.failed, .tryIt), (.failed, .sent),
      (.failed, .sendFailed):
      return (state, [])
    }
  }
}
