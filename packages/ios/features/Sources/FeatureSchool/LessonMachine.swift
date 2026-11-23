import BilletKit
import SchoolInterface

/// One lesson being played: a cue runs, the player taps, the cat does the trick or something else.
public enum LessonMachine: Machine {
  public struct Run: Equatable, Sendable {
    public let plan: LessonPlan
    /// The round being played or just judged.
    public var round: Int
    public var hits: Int
    public var taps: [Double]

    public init(plan: LessonPlan, round: Int = 0, hits: Int = 0, taps: [Double] = []) {
      self.plan = plan
      self.round = round
      self.hits = hits
      self.taps = taps
    }

    public var current: LessonPlan.Round { plan.rounds[round] }
    var roundsLeft: Int { plan.rounds.count - round - 1 }
  }

  public enum State: Equatable, Sendable {
    /// The cue of `run.round` is running.
    case cue(Run)
    case judged(Run, hit: Bool)
    case passed(Run)
    /// Not enough hits this time. No star is lost; the lesson can be taken again.
    case missed(Run)

    public var run: Run {
      switch self {
      case .cue(let run), .judged(let run, _), .passed(let run), .missed(let run): run
      }
    }
  }

  public enum Event: Equatable, Sendable {
    /// A tap, as how far the cue had run, from 0 to 1.
    case tapped(Double)
    case cueEnded
    case next
  }

  public enum Output: Equatable, Sendable {
    case perform(SchoolMove)
  }

  public static func start(_ plan: LessonPlan) -> State { .cue(Run(plan: plan)) }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.cue(var run), .tapped(let at)):
      run.taps.append(at)
      switch run.current.judge(run.taps) {
      case .open: return (.cue(run), [])
      case .hit: return judged(run, hit: true)
      case .miss: return judged(run, hit: false)
      }
    case (.cue(let run), .cueEnded):
      return judged(run, hit: false)
    case (.cue, .next):
      return (state, [])

    case (.judged(var run, _), .next):
      if run.hits >= run.plan.needed { return (.passed(run), []) }
      guard run.hits + run.roundsLeft >= run.plan.needed else { return (.missed(run), []) }
      run.round += 1
      run.taps = []
      return (.cue(run), [])
    case (.judged, .tapped), (.judged, .cueEnded):
      return (state, [])

    case (.passed, .tapped), (.passed, .cueEnded), (.passed, .next), (.missed, .tapped),
      (.missed, .cueEnded), (.missed, .next):
      return (state, [])
    }
  }

  private static func judged(_ run: Run, hit: Bool) -> (State, [Output]) {
    var run = run
    if hit { run.hits += 1 }
    let move: SchoolMove = hit ? .trick(run.plan.trick) : .flub(SchoolFlub(turn: run.round))
    return (.judged(run, hit: hit), [.perform(move)])
  }
}
