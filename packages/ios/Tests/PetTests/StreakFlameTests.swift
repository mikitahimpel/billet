import Foundation
import Testing

@testable import Pet

@Suite("StreakFlame")
struct StreakFlameTests {
  @Test func stagesBeginOnTheirDays() {
    let expected: [(Int, FlameStage)] = [
      (0, .ember), (1, .spark), (2, .spark), (3, .candle), (6, .candle), (7, .steady),
      (13, .steady), (14, .lantern), (29, .lantern), (30, .hearth), (59, .hearth), (60, .fire),
      (99, .fire), (100, .beacon), (364, .beacon), (365, .everglow), (1000, .everglow),
    ]
    for (streak, stage) in expected {
      #expect(FlameStage(streak: streak) == stage, "day \(streak)")
    }
  }

  @Test func eachStageBeginsWhereTheOneBeforeEnds() {
    for stage in FlameStage.allCases {
      #expect(FlameStage(streak: stage.firstDay) == stage)
      if stage.firstDay > 0 {
        #expect(FlameStage(streak: stage.firstDay - 1) < stage)
      }
    }
  }

  @Test func aNegativeStreakIsAnEmber() {
    #expect(StreakFlame(streak: -3).stage == .ember)
    #expect(StreakFlame(streak: -3).streak == 0)
  }

  @Test func growthRisesEveryDayWithNoJumpBack() {
    var last = -1.0
    for day in 0...730 {
      let growth = StreakFlame(streak: day).growth
      #expect(growth > last, "day \(day)")
      last = growth
    }
    #expect(StreakFlame(streak: 0).growth == 0)
    #expect(StreakFlame(streak: 365).growth == 1)
    #expect(StreakFlame(streak: 5000).growth <= 1.1)
  }

  @Test func captionNamesTheDaysAndTheNextGlow() {
    #expect(StreakFlame(streak: 12).caption == "12 days · next glow at 14")
    #expect(StreakFlame(streak: 1).caption == "1 day · next glow at 3")
    #expect(StreakFlame(streak: 400).caption == "400 days · glowing for good")
  }

  @Test func aBrokenStreakRestsAsAnEmberWithNoBlame() {
    let flame = StreakFlame(streak: 0)
    #expect(flame.isEmber)
    #expect(flame.caption == "Resting as a warm ember")
    for word in ["lost", "broke", "died", "dead", "out", "miss", "fail"] {
      #expect(!flame.caption.lowercased().contains(word))
    }
  }

  @Test func contributionsSayWhoAddedWithoutNudging() {
    #expect(FlameContributions(mine: true, theirs: true).line == "You both added to it today")
    #expect(FlameContributions(mine: true).line == "You added to it today")
    #expect(FlameContributions(theirs: true).line == "Your partner added to it today")
    #expect(FlameContributions().line == nil)
  }
}

@Suite("FlameMemory")
struct FlameMemoryTests {
  private let note = UUID()
  private let later = UUID()

  @Test func theFirstVisitCelebratesTheStageAlreadyReached() {
    var memory = FlameMemory()
    #expect(memory.visit(streak: 12, newestNote: note) == FlameVisit(milestone: .steady))
  }

  @Test func aFirstVisitAsAnEmberShowsNothing() {
    var memory = FlameMemory()
    #expect(memory.visit(streak: 0, newestNote: nil) == .quiet)
  }

  @Test func aMilestoneIsCelebratedOnce() {
    var memory = FlameMemory()
    _ = memory.visit(streak: 5, newestNote: note)
    #expect(memory.visit(streak: 7, newestNote: note) == FlameVisit(milestone: .steady))
    #expect(memory.visit(streak: 7, newestNote: note) == .quiet)
    #expect(memory.visit(streak: 8, newestNote: note) == .quiet)
  }

  @Test func stagesSkippedBetweenVisitsAreCelebratedAsTheHighest() {
    var memory = FlameMemory()
    _ = memory.visit(streak: 2, newestNote: note)
    #expect(memory.visit(streak: 31, newestNote: note).milestone == .hearth)
    #expect(memory.visit(streak: 31, newestNote: note).milestone == nil)
  }

  @Test func theFlameRekindlesOnceAfterResting() {
    var memory = FlameMemory()
    _ = memory.visit(streak: 9, newestNote: note)
    #expect(memory.visit(streak: 0, newestNote: note) == .quiet)
    let back = memory.visit(streak: 1, newestNote: note)
    #expect(back.rekindled)
    #expect(back.milestone == nil)
    #expect(memory.visit(streak: 1, newestNote: note) == .quiet)
  }

  @Test func aRunThatEndedUnseenStillRekindles() {
    var memory = FlameMemory()
    _ = memory.visit(streak: 30, newestNote: note)
    let back = memory.visit(streak: 2, newestNote: note)
    #expect(back.rekindled)
    #expect(memory.visit(streak: 3, newestNote: note).milestone == .candle)
  }

  @Test func theNextRunCelebratesItsStagesAgain() {
    var memory = FlameMemory()
    _ = memory.visit(streak: 20, newestNote: note)
    _ = memory.visit(streak: 0, newestNote: note)
    _ = memory.visit(streak: 1, newestNote: note)
    #expect(memory.visit(streak: 7, newestNote: note).milestone == .steady)
  }

  @Test func aNewNotePulsesOnce() {
    var memory = FlameMemory()
    _ = memory.visit(streak: 4, newestNote: note)
    #expect(memory.visit(streak: 4, newestNote: later).pulse)
    #expect(!memory.visit(streak: 4, newestNote: later).pulse)
  }

  @Test func memoryOutlastsALaunch() throws {
    var memory = FlameMemory()
    _ = memory.visit(streak: 7, newestNote: note)
    var restored = try JSONDecoder().decode(
      FlameMemory.self, from: JSONEncoder().encode(memory))
    #expect(restored == memory)
    #expect(restored.visit(streak: 7, newestNote: note) == .quiet)
  }
}
