import Foundation
import Testing

@testable import SchoolInterface

@Suite struct LessonPlanTests {
  @Test(arguments: SchoolTrick.allCases, [1, 2, 3])
  func everyLessonHasRoundsWithOrderedWindowsInsideTheCue(trick: SchoolTrick, star: Int) {
    let plan = LessonPlan(trick: trick, star: star, seed: 7)
    #expect(plan.rounds.count == LessonPlan.rounds)
    #expect(plan.needed <= plan.rounds.count)
    for round in plan.rounds {
      #expect(round.seconds > 0)
      #expect(!round.windows.isEmpty)
      var last = 0.0
      for window in round.windows {
        #expect(window.lowerBound >= last)
        #expect(window.upperBound <= 1)
        #expect(window.upperBound > window.lowerBound)
        last = window.upperBound
      }
    }
  }

  @Test(arguments: SchoolTrick.allCases)
  func aHigherStarNarrowsTheWindow(trick: SchoolTrick) {
    func width(_ star: Int) -> Double {
      let window = LessonPlan(trick: trick, star: star, seed: 7).rounds[0].windows[0]
      return window.upperBound - window.lowerBound
    }
    #expect(width(1) > width(2))
    #expect(width(2) > width(3))
  }

  @Test func theSurpriseTrickMovesWithTheSeedAndIsTheSameForTheSameSeed() {
    let one = LessonPlan(trick: .highFive, star: 1, seed: 1)
    #expect(one == LessonPlan(trick: .highFive, star: 1, seed: 1))
    #expect(one != LessonPlan(trick: .highFive, star: 1, seed: 2))
    #expect(Set(one.rounds.map(\.windows)).count > 1)
  }

  @Test func aRoundIsAHitOnlyWithATapInEachWindowInOrder() {
    let round = LessonPlan.Round(seconds: 2, windows: [0.2...0.4, 0.6...0.8])
    #expect(round.judge([]) == .open)
    #expect(round.judge([0.3]) == .open)
    #expect(round.judge([0.3, 0.7]) == .hit)
    #expect(round.judge([0.1]) == .miss)
    #expect(round.judge([0.3, 0.5]) == .miss)
    #expect(round.judge([0.3, 0.7, 0.9]) == .miss)
  }
}

@Suite struct SchoolBookTests {
  @Test func theCatDoesATrickMoreOftenWithMoreStars() {
    #expect(TrickSkill.chance(stars: 0) == 0)
    #expect(TrickSkill.chance(stars: 1) < TrickSkill.chance(stars: 2))
    #expect(TrickSkill.chance(stars: 3) == 1)
    let skill = TrickSkill(trick: .spin, stars: 1, teacher: "me")
    #expect(skill.lands(roll: 0.49))
    #expect(!skill.lands(roll: 0.5))
    #expect(TrickSkill(trick: .spin, stars: 9, teacher: "me").stars == 3)
  }

  @Test func theNextStarIsOneMoreUntilThree() {
    var book = SchoolBook()
    #expect(book.nextStar(of: .bow) == 1)
    #expect(!book.canBuildRoutine)
    book.skills[.bow] = TrickSkill(trick: .bow, stars: 2, teacher: "me")
    #expect(book.nextStar(of: .bow) == 3)
    #expect(book.known == [.bow])
    book.skills[.bow] = TrickSkill(trick: .bow, stars: 3, teacher: "me")
    #expect(book.nextStar(of: .bow) == nil)
  }

  @Test func aTakeReplaysItsFlubsAsTheyWent() {
    let take = RoutineTake(
      steps: [
        .init(trick: .spin, landed: true), .init(trick: .jump, landed: false),
        .init(trick: .bow, landed: false),
      ], at: Date(timeIntervalSince1970: 0))
    #expect(take.moves == [.trick(.spin), .flub(SchoolFlub(turn: 1)), .flub(SchoolFlub(turn: 2))])
    #expect(take.moves == take.moves)
    #expect(take.landed == 1)
    #expect(SchoolFlub(turn: -1) == SchoolFlub(turn: 3))
  }

  @Test func trickIdsAreWhatTheServerTakes() {
    for trick in SchoolTrick.allCases {
      #expect(trick.rawValue.wholeMatch(of: /[a-z][a-z0-9]*(-[a-z0-9]+)*/) != nil)
      #expect(trick.rawValue.count <= 24)
    }
  }
}
