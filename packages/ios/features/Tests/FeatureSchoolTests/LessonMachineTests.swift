import SchoolInterface
import Testing

@testable import FeatureSchool

@Suite struct LessonMachineTests {
  typealias M = LessonMachine
  private let plan = LessonPlan(trick: .jump, star: 1)

  private var hit: Double {
    let window = plan.rounds[0].windows[0]
    return (window.lowerBound + window.upperBound) / 2
  }

  private func play(_ rounds: [Bool]) -> M.State {
    var state = M.start(plan)
    for (index, good) in rounds.enumerated() {
      state = M.transition(state, good ? .tapped(hit) : .cueEnded).0
      if index < rounds.count - 1 { state = M.transition(state, .next).0 }
    }
    return state
  }

  @Test func aTapInTheWindowIsAHitAndTheCatDoesTheTrick() {
    let (state, outputs) = M.transition(M.start(plan), .tapped(hit))
    #expect(state == .judged(M.Run(plan: plan, round: 0, hits: 1, taps: [hit]), hit: true))
    #expect(outputs == [.perform(.trick(.jump))])
  }

  @Test func aTapOutsideOrNoTapIsAMissAndTheCatDoesSomethingElse() {
    let (early, earlyOut) = M.transition(M.start(plan), .tapped(0.01))
    #expect(early == .judged(M.Run(plan: plan, taps: [0.01]), hit: false))
    #expect(earlyOut == [.perform(.flub(SchoolFlub(turn: 0)))])
    let (late, lateOut) = M.transition(M.start(plan), .cueEnded)
    #expect(late == .judged(M.Run(plan: plan), hit: false))
    #expect(lateOut == [.perform(.flub(SchoolFlub(turn: 0)))])
  }

  @Test func aTrickOfTwoBeatsWaitsForBoth() {
    let spin = LessonPlan(trick: .spin, star: 1)
    let windows = spin.rounds[0].windows
    let (open, none) = M.transition(M.start(spin), .tapped(windows[0].lowerBound))
    #expect(open == .cue(M.Run(plan: spin, taps: [windows[0].lowerBound])))
    #expect(none == [])
    let (done, outputs) = M.transition(open, .tapped(windows[1].upperBound))
    #expect(done.run.hits == 1)
    #expect(outputs == [.perform(.trick(.spin))])
  }

  @Test func threeHitsPassAndTheLessonEndsThere() {
    let state = M.transition(play([true, false, true, true]), .next).0
    #expect(state == .passed(M.Run(plan: plan, round: 3, hits: 3, taps: [hit])))
  }

  @Test func theLessonEndsAsSoonAsThreeHitsAreOutOfReach() {
    let state = M.transition(play([false, false, false]), .next).0
    #expect(state == .missed(M.Run(plan: plan, round: 2, hits: 0, taps: [])))
    let close = M.transition(play([true, false, false, true, false]), .next).0
    #expect(close == .missed(M.Run(plan: plan, round: 4, hits: 2, taps: [])))
  }

  @Test func nextMovesToAFreshRound() {
    let state = M.transition(play([true]), .next).0
    #expect(state == .cue(M.Run(plan: plan, round: 1, hits: 1, taps: [])))
  }

  @Test(arguments: [M.Event.tapped(0.5), .cueEnded, .next])
  func aFinishedLessonTakesNothing(event: M.Event) {
    for state in [M.State.passed(M.Run(plan: plan, hits: 3)), .missed(M.Run(plan: plan))] {
      let (next, outputs) = M.transition(state, event)
      #expect(next == state)
      #expect(outputs == [])
    }
  }

  @Test func aJudgedRoundIgnoresTapsAndACueIgnoresNext() {
    let judged = play([true])
    #expect(M.transition(judged, .tapped(hit)).0 == judged)
    #expect(M.transition(judged, .cueEnded).0 == judged)
    #expect(M.transition(M.start(plan), .next).0 == M.start(plan))
  }
}
