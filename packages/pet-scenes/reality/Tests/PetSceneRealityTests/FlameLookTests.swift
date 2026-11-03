import Foundation
import Pet
import PetScene
import Testing
import simd

@testable import PetSceneReality

@Suite("FlameLook")
struct FlameLookTests {
  private func look(_ streak: Int, today: FlameContributions = .init()) -> FlameLook {
    FlameLook(flame: StreakFlame(streak: streak), today: today)
  }

  @Test func everythingGrowsTogetherDayByDay() {
    var last = look(1)
    for day in 2...400 {
      let now = look(day)
      #expect(now.height >= last.height, "day \(day)")
      #expect(now.brightness >= last.brightness, "day \(day)")
      #expect(now.reach >= last.reach, "day \(day)")
      #expect(now.light >= last.light, "day \(day)")
      #expect(now.sparks >= last.sparks, "day \(day)")
      last = now
    }
    #expect(look(1).sparks == 0)
    #expect(look(365).sparks > look(14).sparks)
    #expect(look(365).sparks <= FlameLook.mostSparks)
  }

  @Test func aGrownFlameBurnsWarmer() {
    // Less blue in the colour is a warmer amber.
    #expect(look(365).core.z < look(1).core.z)
  }

  @Test func theEmberStillGlows() {
    let ember = look(0)
    #expect(ember.isEmber)
    #expect(ember.brightness > 0.3)
    #expect(ember.light > 0)
    #expect(ember.height > 0)
    #expect(ember.holder == .dish)
  }

  @Test func theHolderSuitsTheStage() {
    #expect(look(1).holder == .dish)
    #expect(look(3).holder == .candle)
    #expect(look(10).holder == .candle)
    #expect(look(14).holder == .lantern)
    #expect(look(30).holder == .hearth(logs: 2))
    #expect(look(60).holder == .hearth(logs: 3))
    #expect(look(365).holder == .hearth(logs: 4))
  }

  @Test func whoAddedTodayBurnsBrighter() {
    let quiet = look(10)
    let mine = look(10, today: FlameContributions(mine: true))
    #expect(simd_reduce_add(mine.mine) > simd_reduce_add(quiet.mine))
    #expect(mine.theirs == quiet.theirs)
    let both = look(10, today: FlameContributions(mine: true, theirs: true))
    #expect(both.brightness > quiet.brightness)
  }

  @Test func eachPartnerHasTheirOwnColour() {
    #expect(look(10).mine != look(10).theirs)
    #expect(look(0).mine != look(0).theirs)
  }

  @Test func reduceMotionFlickersLessWithFewerSparks() {
    let calm = FlameLook(flame: StreakFlame(streak: 120), reduceMotion: true)
    #expect(calm.flicker < look(120).flicker)
    #expect(calm.sparks < look(120).sparks)
  }

  @Test func momentsRiseAndSettleBackToNothing() {
    #expect(FlameMoments.swell(0) == 0)
    #expect(FlameMoments.swell(0.3) > 0.8)
    #expect(FlameMoments.swell(FlameMoments.burstLength) == 0)
    #expect(FlameMoments.pulse(-1) == 0)
    #expect(FlameMoments.pulse(FlameMoments.pulseLength / 4) > 0.5)
    #expect(FlameMoments.pulse(FlameMoments.pulseLength) == 0)
    #expect(FlameMoments.caught(0) == 0)
    #expect(FlameMoments.caught(5) == 1)
  }
}
